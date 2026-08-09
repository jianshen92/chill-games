defmodule Doudizhu.Domain.Game do
  @moduledoc "Pure aggregate root for one deterministic three-player 斗地主 hand."

  alias Doudizhu.Domain.{
    AwaitingDeal,
    Bidding,
    Card,
    Combination,
    DeckOrder,
    Finished,
    Hand,
    Players,
    Playing,
    RuleSet,
    Settlement
  }

  @enforce_keys [:id, :players, :rules, :version, :state]
  defstruct [:id, :players, :rules, :version, :state]

  @type phase :: :awaiting_deal | :bidding | :playing | :finished
  @type bid :: 1 | 2 | 3
  @type command ::
          {:deal, DeckOrder.t(), String.t()}
          | {:bid, String.t(), :pass | bid()}
          | {:play_cards, String.t(), [Card.t()]}
          | {:pass, String.t()}
  @type event :: map()
  @type error :: atom() | tuple()
  @type t :: %__MODULE__{
          id: String.t(),
          players: Players.t(),
          rules: RuleSet.t(),
          version: non_neg_integer(),
          state: AwaitingDeal.t() | Bidding.t() | Playing.t() | Finished.t()
        }

  @spec new(String.t(), Players.t(), RuleSet.t()) :: {:ok, t()} | {:error, term()}
  def new(id, %Players{} = players, %RuleSet{} = rules) when is_binary(id) and id != "" do
    with {:ok, valid_rules} <- RuleSet.validate(rules) do
      {:ok,
       %__MODULE__{
         id: id,
         players: players,
         rules: valid_rules,
         version: 0,
         state: %AwaitingDeal{deal_number: 1}
       }}
    end
  end

  @spec phase(t()) :: phase()
  def phase(%__MODULE__{state: %AwaitingDeal{}}), do: :awaiting_deal
  def phase(%__MODULE__{state: %Bidding{}}), do: :bidding
  def phase(%__MODULE__{state: %Playing{}}), do: :playing
  def phase(%__MODULE__{state: %Finished{}}), do: :finished

  @spec execute(t(), command()) :: {:ok, t(), [event()]} | {:error, error()}
  def execute(
        %__MODULE__{state: %AwaitingDeal{} = state} = game,
        {:deal, %DeckOrder{} = deck, starter}
      ),
      do: handle_deal(game, state, deck, starter)

  def execute(%__MODULE__{state: %Bidding{} = state} = game, {:bid, player, :pass}),
    do: handle_auction_pass(game, state, player)

  def execute(%__MODULE__{state: %Bidding{} = state} = game, {:bid, player, bid})
      when bid in 1..3,
      do: handle_bid(game, state, player, bid)

  def execute(%__MODULE__{state: %Playing{} = state} = game, {:play_cards, player, cards}),
    do: handle_play(game, state, player, cards)

  def execute(%__MODULE__{state: %Playing{} = state} = game, {:pass, player}),
    do: handle_play_pass(game, state, player)

  def execute(%__MODULE__{} = game, {:deal, _, _}), do: command_not_allowed(game, :deal)
  def execute(%__MODULE__{} = game, {:bid, _, _}), do: command_not_allowed(game, :bid)

  def execute(%__MODULE__{} = game, {:play_cards, _, _}),
    do: command_not_allowed(game, :play_cards)

  def execute(%__MODULE__{} = game, {:pass, _}), do: command_not_allowed(game, :pass)
  def execute(%__MODULE__{}, command), do: {:error, {:unknown_command, command}}

  @spec hand(t(), String.t()) :: {:ok, Hand.t()} | :error
  def hand(%__MODULE__{state: %AwaitingDeal{}}, _player_id), do: :error
  def hand(%__MODULE__{state: state}, player_id), do: Map.fetch(state.hands, player_id)

  @spec role(t(), String.t()) :: {:ok, :landlord | :farmer} | :error
  def role(%__MODULE__{} = game, player_id) do
    if Players.contains?(game.players, player_id) do
      case game.state do
        %Playing{landlord: ^player_id} -> {:ok, :landlord}
        %Finished{landlord: ^player_id} -> {:ok, :landlord}
        %Playing{} -> {:ok, :farmer}
        %Finished{} -> {:ok, :farmer}
        _ -> :error
      end
    else
      :error
    end
  end

  @spec status(t()) :: map()
  def status(%__MODULE__{state: %AwaitingDeal{} = state}) do
    %{phase: :awaiting_deal, deal_number: state.deal_number}
  end

  def status(%__MODULE__{state: %Bidding{} = state}) do
    %{
      phase: :bidding,
      deal_number: state.deal_number,
      current_bidder: state.current_bidder,
      highest_bid: state.highest_bid,
      consecutive_passes: state.consecutive_passes,
      hand_counts: hand_counts(state.hands)
    }
  end

  def status(%__MODULE__{state: %Playing{} = state}) do
    %{
      phase: :playing,
      deal_number: state.deal_number,
      landlord: state.landlord,
      winning_bid: state.winning_bid,
      current_player: state.current_player,
      current_lead: state.current_lead,
      consecutive_passes: state.consecutive_passes,
      hand_counts: hand_counts(state.hands),
      bombs_played: state.bombs_played,
      rockets_played: state.rockets_played
    }
  end

  def status(%__MODULE__{state: %Finished{} = state}) do
    %{
      phase: :finished,
      deal_number: state.deal_number,
      landlord: state.landlord,
      hand_counts: hand_counts(state.hands),
      settlement: state.settlement
    }
  end

  defp handle_deal(%__MODULE__{} = game, %AwaitingDeal{} = state, %DeckOrder{} = deck, starter) do
    if Players.contains?(game.players, starter) do
      all_cards = DeckOrder.cards(deck)
      dealt_cards = Enum.take(all_cards, 51)

      hands =
        game.players
        |> Players.ids()
        |> Enum.with_index()
        |> Map.new(fn {player_id, player_index} ->
          cards =
            dealt_cards
            |> Enum.with_index()
            |> Enum.flat_map(fn {card, card_index} ->
              if rem(card_index, 3) == player_index, do: [card], else: []
            end)

          {:ok, hand} = Hand.new(cards)
          {player_id, hand}
        end)

      bidding = %Bidding{
        deal_number: state.deal_number,
        hands: hands,
        bottom_cards: Enum.drop(all_cards, 51),
        current_bidder: starter,
        highest_bid: nil,
        consecutive_passes: 0
      }

      {:ok, with_state(game, bidding),
       [%{type: :cards_dealt, deal_number: state.deal_number, auction_starter: starter}]}
    else
      {:error, {:unknown_player, starter}}
    end
  end

  defp handle_auction_pass(%__MODULE__{} = game, %Bidding{} = state, player) do
    with :ok <- validate_turn(game, state.current_bidder, player) do
      pass_count = state.consecutive_passes + 1
      pass_event = %{type: :auction_passed, player_id: player}

      case {state.highest_bid, pass_count} do
        {nil, 3} ->
          awaiting = %AwaitingDeal{deal_number: state.deal_number + 1}

          {:ok, with_state(game, awaiting),
           [pass_event, %{type: :deal_voided, deal_number: state.deal_number}]}

        {%{bidder: _bidder, bid: _bid} = highest, 2} ->
          {playing, landlord_event} = start_playing(game, state, highest)
          {:ok, with_state(game, playing), [pass_event, landlord_event]}

        _ ->
          bidding = %Bidding{
            state
            | current_bidder: next_player!(game, player),
              consecutive_passes: pass_count
          }

          {:ok, with_state(game, bidding), [pass_event]}
      end
    end
  end

  defp handle_bid(%__MODULE__{} = game, %Bidding{} = state, player, bid) do
    with :ok <- validate_turn(game, state.current_bidder, player),
         :ok <- validate_bid(state.highest_bid, bid) do
      highest = %{bidder: player, bid: bid}
      bid_event = %{type: :bid_placed, player_id: player, bid: bid}

      if bid == 3 do
        {playing, landlord_event} = start_playing(game, state, highest)
        {:ok, with_state(game, playing), [bid_event, landlord_event]}
      else
        bidding = %Bidding{
          state
          | current_bidder: next_player!(game, player),
            highest_bid: highest,
            consecutive_passes: 0
        }

        {:ok, with_state(game, bidding), [bid_event]}
      end
    end
  end

  defp start_playing(%__MODULE__{} = game, %Bidding{} = state, highest) do
    landlord_hand = Map.fetch!(state.hands, highest.bidder)
    {:ok, enlarged_hand} = Hand.add(landlord_hand, state.bottom_cards)
    hands = Map.put(state.hands, highest.bidder, enlarged_hand)

    playing = %Playing{
      deal_number: state.deal_number,
      hands: hands,
      played_cards: MapSet.new(),
      landlord: highest.bidder,
      winning_bid: highest.bid,
      current_player: highest.bidder,
      current_lead: nil,
      consecutive_passes: 0,
      bombs_played: 0,
      rockets_played: 0,
      plays_by_player: Map.new(Players.ids(game.players), &{&1, 0})
    }

    revealed = if game.rules.reveal_bottom_cards, do: Card.sort(state.bottom_cards)

    event = %{
      type: :landlord_chosen,
      landlord: highest.bidder,
      bid: highest.bid,
      revealed_bottom_cards: revealed
    }

    {playing, event}
  end

  defp handle_play(%__MODULE__{} = game, %Playing{} = state, player, selected_cards) do
    with :ok <- validate_turn(game, state.current_player, player),
         current_hand <- Map.fetch!(state.hands, player),
         {:ok, remaining_hand} <- map_hand_result(Hand.remove(current_hand, selected_cards)),
         {:ok, combination} <-
           map_combination_result(Combination.classify(game.rules, selected_cards)),
         :ok <- validate_beats_lead(state.current_lead, combination) do
      hands = Map.put(state.hands, player, remaining_hand)
      plays_by_player = Map.update!(state.plays_by_player, player, &(&1 + 1))

      {bombs_played, rockets_played} =
        case combination.kind do
          :bomb -> {state.bombs_played + 1, state.rockets_played}
          :rocket -> {state.bombs_played, state.rockets_played + 1}
          _ -> {state.bombs_played, state.rockets_played}
        end

      played_cards = MapSet.union(state.played_cards, MapSet.new(selected_cards))

      after_play = %Playing{
        state
        | hands: hands,
          played_cards: played_cards,
          current_lead: %{player: player, combination: combination},
          consecutive_passes: 0,
          bombs_played: bombs_played,
          rockets_played: rockets_played,
          plays_by_player: plays_by_player
      }

      play_event = %{type: :cards_played, player_id: player, combination: combination}

      if Hand.empty?(remaining_hand) do
        winning_side = if player == state.landlord, do: :landlord, else: :farmers
        settlement = calculate_settlement(game, after_play, player, winning_side)

        finished = %Finished{
          deal_number: state.deal_number,
          hands: hands,
          played_cards: played_cards,
          landlord: state.landlord,
          settlement: settlement
        }

        {:ok, with_state(game, finished),
         [play_event, %{type: :game_finished, settlement: settlement}]}
      else
        playing = %Playing{after_play | current_player: next_player!(game, player)}
        {:ok, with_state(game, playing), [play_event]}
      end
    end
  end

  defp handle_play_pass(%__MODULE__{} = game, %Playing{} = state, player) do
    with :ok <- validate_turn(game, state.current_player, player),
         {:ok, lead} <- require_lead(state.current_lead) do
      pass_event = %{type: :turn_passed, player_id: player}
      pass_count = state.consecutive_passes + 1

      if pass_count == 2 do
        playing = %Playing{
          state
          | current_player: lead.player,
            current_lead: nil,
            consecutive_passes: 0
        }

        {:ok, with_state(game, playing),
         [pass_event, %{type: :lead_cleared, next_leader: lead.player}]}
      else
        playing = %Playing{
          state
          | current_player: next_player!(game, player),
            consecutive_passes: pass_count
        }

        {:ok, with_state(game, playing), [pass_event]}
      end
    end
  end

  defp calculate_settlement(%__MODULE__{} = game, %Playing{} = state, winner, winning_side) do
    farmer_ids = Enum.reject(Players.ids(game.players), &(&1 == state.landlord))
    landlord_play_count = Map.fetch!(state.plays_by_player, state.landlord)
    farmers_play_count = Enum.sum(Enum.map(farmer_ids, &Map.fetch!(state.plays_by_player, &1)))

    spring =
      case {winning_side, farmers_play_count, landlord_play_count} do
        {:landlord, 0, _} -> :landlord_spring
        {:farmers, _, 1} -> :farmer_spring
        _ -> :none
      end

    scoring = game.rules.scoring
    spring_factor = if spring == :none, do: 1, else: scoring.spring_multiplier

    per_farmer_stake =
      state.winning_bid *
        Integer.pow(scoring.bomb_multiplier, state.bombs_played) *
        Integer.pow(scoring.rocket_multiplier, state.rockets_played) * spring_factor

    {landlord_delta, farmer_delta} =
      if winning_side == :landlord,
        do: {2 * per_farmer_stake, -per_farmer_stake},
        else: {-2 * per_farmer_stake, per_farmer_stake}

    deltas =
      Map.new([{state.landlord, landlord_delta} | Enum.map(farmer_ids, &{&1, farmer_delta})])

    %Settlement{
      winning_side: winning_side,
      winning_player: winner,
      per_farmer_stake: per_farmer_stake,
      bomb_count: state.bombs_played,
      rocket_count: state.rockets_played,
      spring: spring,
      deltas: deltas
    }
  end

  defp validate_turn(game, expected, actual) do
    cond do
      not Players.contains?(game.players, actual) -> {:error, {:unknown_player, actual}}
      expected != actual -> {:error, {:not_players_turn, expected, actual}}
      true -> :ok
    end
  end

  defp validate_bid(nil, _bid), do: :ok
  defp validate_bid(%{bid: current}, bid) when bid > current, do: :ok
  defp validate_bid(%{bid: current}, _bid), do: {:error, {:bid_must_exceed, current}}

  defp validate_beats_lead(nil, _combination), do: :ok

  defp validate_beats_lead(%{combination: current}, challenger) do
    if Combination.beats?(current, challenger),
      do: :ok,
      else: {:error, :play_does_not_beat_current_lead}
  end

  defp map_hand_result({:ok, hand}), do: {:ok, hand}

  defp map_hand_result({:error, {:duplicate_cards, cards}}),
    do: {:error, {:duplicate_cards_selected, cards}}

  defp map_hand_result({:error, {:cards_not_held, cards}}), do: {:error, {:cards_not_held, cards}}

  defp map_combination_result({:ok, combination}), do: {:ok, combination}
  defp map_combination_result({:error, reason}), do: {:error, {:invalid_combination, reason}}

  defp require_lead(nil), do: {:error, :cannot_pass_when_leading}
  defp require_lead(lead), do: {:ok, lead}

  defp next_player!(game, player) do
    {:ok, next} = Players.next_id(game.players, player)
    next
  end

  defp hand_counts(hands), do: Map.new(hands, fn {player, hand} -> {player, Hand.count(hand)} end)

  defp with_state(%__MODULE__{} = game, state),
    do: %__MODULE__{game | state: state, version: game.version + 1}

  defp command_not_allowed(game, command),
    do: {:error, {:command_not_allowed, command, phase(game)}}
end
