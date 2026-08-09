defmodule Doudizhu.Domain.GameTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Domain.{Card, Game}
  import Doudizhu.DomainHelpers

  test "standard deck contains 54 unique physical cards" do
    deck = Card.standard_deck()
    assert length(deck) == 54
    assert MapSet.size(MapSet.new(deck)) == 54
    assert Enum.count(deck, &Card.standard_rank?(&1.rank)) == 52
  end

  test "deal gives each player 17 cards and starts requested bidder" do
    game = new_game() |> deal()
    view = Game.status(game)

    assert view.phase == :bidding
    assert view.current_bidder == first_id()
    assert view.hand_counts == %{first_id() => 17, second_id() => 17, third_id() => 17}
    assert game.version == 1
  end

  test "three opening passes void the deal" do
    game0 = new_game() |> deal()
    {game1, _} = execute!(game0, {:bid, first_id(), :pass})
    {game2, _} = execute!(game1, {:bid, second_id(), :pass})
    {game3, events} = execute!(game2, {:bid, third_id(), :pass})

    assert Game.status(game3) == %{phase: :awaiting_deal, deal_number: 2}
    assert %{type: :deal_voided, deal_number: 1} in events
    assert game3.version == 4
  end

  test "auction continues until two passes follow highest bid" do
    game0 = new_game() |> deal()
    {game1, _} = execute!(game0, {:bid, first_id(), 1})
    {game2, _} = execute!(game1, {:bid, second_id(), :pass})
    {game3, _} = execute!(game2, {:bid, third_id(), 2})
    {game4, _} = execute!(game3, {:bid, first_id(), :pass})
    {game5, _} = execute!(game4, {:bid, second_id(), :pass})
    view = Game.status(game5)

    assert view.phase == :playing
    assert view.landlord == third_id()
    assert view.current_player == third_id()
    assert view.winning_bid == 2
    assert view.hand_counts == %{first_id() => 17, second_id() => 17, third_id() => 20}
  end

  test "bid of three ends auction immediately" do
    game = new_game() |> deal() |> bid_three()
    view = Game.status(game)

    assert view.landlord == first_id()
    assert view.current_player == first_id()
    assert view.winning_bid == 3
    assert view.hand_counts[first_id()] == 20
    assert Game.role(game, first_id()) == {:ok, :landlord}
    assert Game.role(game, second_id()) == {:ok, :farmer}
    assert Game.role(game, third_id()) == {:ok, :farmer}
  end

  test "bid must exceed current highest bid and rejection does not change state" do
    game0 = new_game() |> deal()
    {game1, _} = execute!(game0, {:bid, first_id(), 2})

    assert Game.execute(game1, {:bid, second_id(), 1}) == {:error, {:bid_must_exceed, 2}}
    assert game1.version == 2
  end

  test "two play passes clear lead and return lead to last player" do
    game0 = new_game() |> deal() |> bid_three()
    card_to_lead = game0 |> hand_cards(first_id()) |> hd()
    {game1, _} = execute!(game0, {:play_cards, first_id(), [card_to_lead]})
    {game2, _} = execute!(game1, {:pass, second_id()})
    {game3, events} = execute!(game2, {:pass, third_id()})
    view = Game.status(game3)

    assert view.current_player == first_id()
    assert view.current_lead == nil
    assert %{type: :lead_cleared, next_leader: first_id()} in events
    assert Game.execute(game3, {:pass, first_id()}) == {:error, :cannot_pass_when_leading}
  end

  test "a player cannot play cards not in hand" do
    game = new_game() |> deal() |> bid_three()
    other_players_card = game |> hand_cards(second_id()) |> hd()

    assert Game.execute(game, {:play_cards, first_id(), [other_players_card]}) ==
             {:error, {:cards_not_held, [other_players_card]}}
  end

  test "a response must beat current lead" do
    game0 = new_game() |> deal() |> bid_three()
    high_lead = game0 |> hand_cards(first_id()) |> Enum.max_by(&Card.strength/1)
    low_response = game0 |> hand_cards(second_id()) |> Enum.min_by(&Card.strength/1)
    assert Card.strength(high_lead) > Card.strength(low_response)

    {game1, _} = execute!(game0, {:play_cards, first_id(), [high_lead]})

    assert Game.execute(game1, {:play_cards, second_id(), [low_response]}) ==
             {:error, :play_does_not_beat_current_lead}
  end

  test "unknown actors are rejected explicitly" do
    game = new_game() |> deal()

    assert Game.execute(game, {:bid, "stranger", :pass}) ==
             {:error, {:unknown_player, "stranger"}}
  end

  test "landlord can win with one airplane and receives spring settlement" do
    winning_hand =
      triple(:three) ++
        triple(:four) ++
        triple(:five) ++
        triple(:six) ++ pair(:seven) ++ pair(:eight) ++ pair(:nine) ++ pair(:ten)

    assert classify!(winning_hand).kind == {:airplane_with_pairs, 4}

    game0 = new_game() |> deal(deck_with_first_landlord_hand(winning_hand)) |> bid_three()
    {game1, events} = execute!(game0, {:play_cards, first_id(), winning_hand})
    settlement = Game.status(game1).settlement

    assert settlement.winning_side == :landlord
    assert settlement.spring == :landlord_spring
    assert settlement.per_farmer_stake == 6
    assert settlement.deltas == %{first_id() => 12, second_id() => -6, third_id() => -6}
    assert Enum.any?(events, &(&1.type == :game_finished and &1.settlement == settlement))
  end

  test "bomb and spring multipliers compose in settlement" do
    bomb = quad(:three)

    airplane =
      triple(:four) ++
        triple(:five) ++
        triple(:six) ++ triple(:seven) ++ one(:eight) ++ one(:nine) ++ one(:ten) ++ one(:jack)

    assert classify!(airplane).kind == {:airplane_with_singles, 4}

    game0 = new_game() |> deal(deck_with_first_landlord_hand(bomb ++ airplane)) |> bid_three()
    {game1, _} = execute!(game0, {:play_cards, first_id(), bomb})
    {game2, _} = execute!(game1, {:pass, second_id()})
    {game3, _} = execute!(game2, {:pass, third_id()})
    {game4, _} = execute!(game3, {:play_cards, first_id(), airplane})
    settlement = Game.status(game4).settlement

    assert settlement.bomb_count == 1
    assert settlement.spring == :landlord_spring
    assert settlement.per_farmer_stake == 12
    assert settlement.deltas[first_id()] == 24
  end

  test "rocket and spring multipliers compose in settlement" do
    rocket = [small_joker(), big_joker()]
    low_pair = pair(:three)

    airplane =
      triple(:four) ++
        triple(:five) ++
        triple(:six) ++ triple(:seven) ++ one(:eight) ++ one(:nine) ++ one(:ten) ++ one(:jack)

    game0 =
      new_game()
      |> deal(deck_with_first_landlord_hand(rocket ++ low_pair ++ airplane))
      |> bid_three()

    {game1, _} = execute!(game0, {:play_cards, first_id(), rocket})
    {game2, _} = execute!(game1, {:pass, second_id()})
    {game3, _} = execute!(game2, {:pass, third_id()})
    {game4, _} = execute!(game3, {:play_cards, first_id(), low_pair})
    {game5, _} = execute!(game4, {:pass, second_id()})
    {game6, _} = execute!(game5, {:pass, third_id()})
    {game7, _} = execute!(game6, {:play_cards, first_id(), airplane})
    settlement = Game.status(game7).settlement

    assert settlement.rocket_count == 1
    assert settlement.spring == :landlord_spring
    assert settlement.per_farmer_stake == 12
    assert settlement.deltas[first_id()] == 24
  end

  test "farmers win together and anti-spring applies when landlord played once" do
    farmer_finisher =
      triple(:four) ++
        triple(:five) ++
        triple(:six) ++ triple(:seven) ++ one(:eight) ++ one(:nine) ++ one(:ten) ++ one(:jack)

    farmer_high_single = card(:clubs, :two)
    second_hand = [farmer_high_single | farmer_finisher]
    landlord_lead = card(:clubs, :three)

    available_after_second = reject_cards(Card.standard_deck(), second_hand)
    first_rest = available_after_second |> Enum.reject(&(&1 == landlord_lead)) |> Enum.take(16)
    first_hand = [landlord_lead | first_rest]
    remaining = reject_cards(Card.standard_deck(), first_hand ++ second_hand)
    bottom = Enum.take(remaining, 3)
    third_hand = Enum.drop(remaining, 3)
    deck = deck_with_hands(first_hand, second_hand, third_hand, bottom)

    game0 = new_game() |> deal(deck) |> bid_three()
    {game1, _} = execute!(game0, {:play_cards, first_id(), [landlord_lead]})
    {game2, _} = execute!(game1, {:play_cards, second_id(), [farmer_high_single]})
    {game3, _} = execute!(game2, {:pass, third_id()})
    {game4, _} = execute!(game3, {:pass, first_id()})
    {game5, _} = execute!(game4, {:play_cards, second_id(), farmer_finisher})
    settlement = Game.status(game5).settlement

    assert settlement.winning_side == :farmers
    assert settlement.winning_player == second_id()
    assert settlement.spring == :farmer_spring
    assert settlement.per_farmer_stake == 6
    assert settlement.deltas == %{first_id() => -12, second_id() => 6, third_id() => 6}
    assert settlement.deltas |> Map.values() |> Enum.sum() == 0
  end

  test "commands not valid for the current phase are rejected" do
    game = new_game()

    assert Game.execute(game, {:pass, first_id()}) ==
             {:error, {:command_not_allowed, :pass, :awaiting_deal}}
  end

  defp reject_cards(all, selected) do
    selected = MapSet.new(selected)
    Enum.reject(all, &MapSet.member?(selected, &1))
  end
end
