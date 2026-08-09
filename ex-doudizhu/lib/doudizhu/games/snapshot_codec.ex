defmodule Doudizhu.Games.SnapshotCodec do
  @moduledoc "Explicit versioned JSON-compatible codec for complete private game snapshots."

  alias Doudizhu.Domain.{
    AwaitingDeal,
    Bidding,
    Card,
    Combination,
    Finished,
    Game,
    Hand,
    Player,
    Players,
    Playing,
    RuleSet,
    Settlement
  }

  @version 1

  @spec version() :: 1
  def version, do: @version

  @spec encode(Game.t()) :: map()
  def encode(%Game{} = game) do
    %{
      "codec_version" => @version,
      "id" => game.id,
      "version" => game.version,
      "players" => Enum.map(Players.all(game.players), &encode_player/1),
      "rules" => encode_rules(game.rules),
      "state" => encode_state(game.state)
    }
  end

  @spec decode(map()) :: {:ok, Game.t()} | {:error, term()}
  def decode(%{
        "codec_version" => @version,
        "id" => id,
        "version" => version,
        "players" => encoded_players,
        "rules" => encoded_rules,
        "state" => encoded_state
      }) do
    with {:ok, players} <- decode_players(encoded_players),
         {:ok, rules} <- decode_rules(encoded_rules),
         {:ok, state} <- decode_state(encoded_state, rules) do
      {:ok, %Game{id: id, version: version, players: players, rules: rules, state: state}}
    end
  end

  def decode(%{"codec_version" => version}), do: {:error, {:unsupported_snapshot_codec, version}}
  def decode(_snapshot), do: {:error, :invalid_snapshot}

  @spec encode_rules(RuleSet.t()) :: map()
  def encode_rules(%RuleSet{} = rules) do
    %{
      "attachments" => %{
        "airplane_single_wings" => Atom.to_string(rules.attachments.airplane_single_wings),
        "four_single_wings_must_have_distinct_ranks" =>
          rules.attachments.four_single_wings_must_have_distinct_ranks,
        "both_jokers_may_be_attachments" => rules.attachments.both_jokers_may_be_attachments
      },
      "scoring" => Map.new(rules.scoring, fn {key, value} -> {Atom.to_string(key), value} end),
      "reveal_bottom_cards" => rules.reveal_bottom_cards
    }
  end

  defp encode_player(%Player{} = player), do: %{"id" => player.id, "name" => player.name}

  defp encode_state(%AwaitingDeal{} = state),
    do: %{"phase" => "awaiting_deal", "deal_number" => state.deal_number}

  defp encode_state(%Bidding{} = state) do
    %{
      "phase" => "bidding",
      "deal_number" => state.deal_number,
      "hands" => encode_hands(state.hands),
      "bottom_cards" => encode_cards(state.bottom_cards),
      "current_bidder" => state.current_bidder,
      "highest_bid" =>
        if(state.highest_bid,
          do: %{"bidder" => state.highest_bid.bidder, "bid" => state.highest_bid.bid},
          else: nil
        ),
      "consecutive_passes" => state.consecutive_passes
    }
  end

  defp encode_state(%Playing{} = state) do
    %{
      "phase" => "playing",
      "deal_number" => state.deal_number,
      "hands" => encode_hands(state.hands),
      "played_cards" => state.played_cards |> MapSet.to_list() |> encode_cards(),
      "landlord" => state.landlord,
      "winning_bid" => state.winning_bid,
      "current_player" => state.current_player,
      "current_lead" => encode_lead(state.current_lead),
      "consecutive_passes" => state.consecutive_passes,
      "bombs_played" => state.bombs_played,
      "rockets_played" => state.rockets_played,
      "plays_by_player" => state.plays_by_player
    }
  end

  defp encode_state(%Finished{} = state) do
    %{
      "phase" => "finished",
      "deal_number" => state.deal_number,
      "hands" => encode_hands(state.hands),
      "played_cards" => state.played_cards |> MapSet.to_list() |> encode_cards(),
      "landlord" => state.landlord,
      "settlement" => encode_settlement(state.settlement)
    }
  end

  defp encode_hands(hands),
    do:
      Map.new(hands, fn {player_id, hand} ->
        {player_id, hand |> Hand.cards() |> encode_cards()}
      end)

  defp encode_cards(cards), do: Enum.map(Card.sort(cards), &Card.to_id/1)

  defp encode_lead(nil), do: nil

  defp encode_lead(lead),
    do: %{"player" => lead.player, "cards" => encode_cards(lead.combination.cards)}

  defp encode_settlement(%Settlement{} = settlement) do
    %{
      "winning_side" => Atom.to_string(settlement.winning_side),
      "winning_player" => settlement.winning_player,
      "per_farmer_stake" => settlement.per_farmer_stake,
      "bomb_count" => settlement.bomb_count,
      "rocket_count" => settlement.rocket_count,
      "spring" => Atom.to_string(settlement.spring),
      "deltas" => settlement.deltas
    }
  end

  defp decode_players([first, second, third]) do
    with {:ok, first} <- decode_player(first),
         {:ok, second} <- decode_player(second),
         {:ok, third} <- decode_player(third),
         {:ok, players} <- Players.new(first, second, third) do
      {:ok, players}
    end
  end

  defp decode_players(_players), do: {:error, :invalid_players}

  defp decode_player(%{"id" => id, "name" => name}), do: Player.new(id, name)
  defp decode_player(_player), do: {:error, :invalid_player}

  defp decode_rules(%{
         "attachments" => attachments,
         "scoring" => scoring,
         "reveal_bottom_cards" => reveal_bottom_cards
       }) do
    wing_policy =
      case attachments["airplane_single_wings"] do
        "distinct_ranks" -> {:ok, :distinct_ranks}
        "pairs_allowed" -> {:ok, :pairs_allowed}
        "any_cards" -> {:ok, :any_cards}
        _ -> {:error, :invalid_wing_policy}
      end

    with {:ok, wing_policy} <- wing_policy do
      rules = %RuleSet{
        attachments: %{
          airplane_single_wings: wing_policy,
          four_single_wings_must_have_distinct_ranks:
            attachments["four_single_wings_must_have_distinct_ranks"],
          both_jokers_may_be_attachments: attachments["both_jokers_may_be_attachments"]
        },
        scoring: %{
          bomb_multiplier: scoring["bomb_multiplier"],
          rocket_multiplier: scoring["rocket_multiplier"],
          spring_multiplier: scoring["spring_multiplier"]
        },
        reveal_bottom_cards: reveal_bottom_cards
      }

      RuleSet.validate(rules)
    end
  end

  defp decode_rules(_rules), do: {:error, :invalid_rules}

  defp decode_state(%{"phase" => "awaiting_deal", "deal_number" => deal_number}, _rules),
    do: {:ok, %AwaitingDeal{deal_number: deal_number}}

  defp decode_state(%{"phase" => "bidding"} = state, _rules) do
    with {:ok, hands} <- decode_hands(state["hands"]),
         {:ok, bottom_cards} <- decode_cards(state["bottom_cards"]),
         {:ok, highest_bid} <- decode_highest_bid(state["highest_bid"]) do
      {:ok,
       %Bidding{
         deal_number: state["deal_number"],
         hands: hands,
         bottom_cards: bottom_cards,
         current_bidder: state["current_bidder"],
         highest_bid: highest_bid,
         consecutive_passes: state["consecutive_passes"]
       }}
    end
  end

  defp decode_state(%{"phase" => "playing"} = state, rules) do
    with {:ok, hands} <- decode_hands(state["hands"]),
         {:ok, played_cards} <- decode_cards(state["played_cards"]),
         {:ok, lead} <- decode_lead(state["current_lead"], rules) do
      {:ok,
       %Playing{
         deal_number: state["deal_number"],
         hands: hands,
         played_cards: MapSet.new(played_cards),
         landlord: state["landlord"],
         winning_bid: state["winning_bid"],
         current_player: state["current_player"],
         current_lead: lead,
         consecutive_passes: state["consecutive_passes"],
         bombs_played: state["bombs_played"],
         rockets_played: state["rockets_played"],
         plays_by_player: state["plays_by_player"]
       }}
    end
  end

  defp decode_state(%{"phase" => "finished"} = state, _rules) do
    with {:ok, hands} <- decode_hands(state["hands"]),
         {:ok, played_cards} <- decode_cards(state["played_cards"]),
         {:ok, settlement} <- decode_settlement(state["settlement"]) do
      {:ok,
       %Finished{
         deal_number: state["deal_number"],
         hands: hands,
         played_cards: MapSet.new(played_cards),
         landlord: state["landlord"],
         settlement: settlement
       }}
    end
  end

  defp decode_state(_state, _rules), do: {:error, :invalid_game_state}

  defp decode_hands(hands) when is_map(hands) do
    Enum.reduce_while(hands, {:ok, %{}}, fn {player_id, card_ids}, {:ok, decoded} ->
      with {:ok, cards} <- decode_cards(card_ids),
           {:ok, hand} <- Hand.new(cards) do
        {:cont, {:ok, Map.put(decoded, player_id, hand)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp decode_hands(_hands), do: {:error, :invalid_hands}

  defp decode_cards(card_ids) when is_list(card_ids) do
    Enum.reduce_while(card_ids, {:ok, []}, fn card_id, {:ok, cards} ->
      case Card.from_id(card_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      error -> error
    end
  end

  defp decode_cards(_cards), do: {:error, :invalid_cards}

  defp decode_highest_bid(nil), do: {:ok, nil}

  defp decode_highest_bid(%{"bidder" => bidder, "bid" => bid}) when bid in 1..3,
    do: {:ok, %{bidder: bidder, bid: bid}}

  defp decode_highest_bid(_highest), do: {:error, :invalid_highest_bid}

  defp decode_lead(nil, _rules), do: {:ok, nil}

  defp decode_lead(%{"player" => player, "cards" => card_ids}, rules) do
    with {:ok, cards} <- decode_cards(card_ids),
         {:ok, combination} <- Combination.classify(rules, cards) do
      {:ok, %{player: player, combination: combination}}
    end
  end

  defp decode_lead(_lead, _rules), do: {:error, :invalid_lead}

  defp decode_settlement(%{} = settlement) do
    with {:ok, winning_side} <- decode_winning_side(settlement["winning_side"]),
         {:ok, spring} <- decode_spring(settlement["spring"]) do
      {:ok,
       %Settlement{
         winning_side: winning_side,
         winning_player: settlement["winning_player"],
         per_farmer_stake: settlement["per_farmer_stake"],
         bomb_count: settlement["bomb_count"],
         rocket_count: settlement["rocket_count"],
         spring: spring,
         deltas: settlement["deltas"]
       }}
    end
  end

  defp decode_settlement(_settlement), do: {:error, :invalid_settlement}

  defp decode_winning_side("landlord"), do: {:ok, :landlord}
  defp decode_winning_side("farmers"), do: {:ok, :farmers}
  defp decode_winning_side(_side), do: {:error, :invalid_winning_side}

  defp decode_spring("none"), do: {:ok, :none}
  defp decode_spring("landlord_spring"), do: {:ok, :landlord_spring}
  defp decode_spring("farmer_spring"), do: {:ok, :farmer_spring}
  defp decode_spring(_spring), do: {:error, :invalid_spring}
end
