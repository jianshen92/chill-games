defmodule Doudizhu.Domain.InvariantsTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Domain.{Bidding, Finished, Game, Hand, Playing}
  import Doudizhu.DomainHelpers

  test "cards are conserved and unique through accepted transitions" do
    game0 = new_game()
    game1 = deal(game0)
    game2 = bid_three(game1)
    lead = game2 |> hand_cards(first_id()) |> hd()
    {game3, _events} = execute!(game2, {:play_cards, first_id(), [lead]})

    assert game1.version == game0.version + 1
    assert game2.version == game1.version + 1
    assert game3.version == game2.version + 1

    for game <- [game1, game2, game3] do
      cards = cards_in_state(game.state)
      assert length(cards) == 54
      assert MapSet.size(MapSet.new(cards)) == 54
    end
  end

  test "rejected commands leave state and version unchanged" do
    game = new_game() |> deal()
    original = game

    assert {:error, {:not_players_turn, _, _}} = Game.execute(game, {:bid, second_id(), :pass})
    assert game == original
    assert game.version == original.version
  end

  test "finished settlement is always zero sum" do
    winning_hand =
      triple(:three) ++
        triple(:four) ++
        triple(:five) ++
        triple(:six) ++ pair(:seven) ++ pair(:eight) ++ pair(:nine) ++ pair(:ten)

    game = new_game() |> deal(deck_with_first_landlord_hand(winning_hand)) |> bid_three()
    {finished, _events} = execute!(game, {:play_cards, first_id(), winning_hand})
    assert finished.state.settlement.deltas |> Map.values() |> Enum.sum() == 0
  end

  defp cards_in_state(%Bidding{} = state) do
    cards_in_hands(state.hands) ++ state.bottom_cards
  end

  defp cards_in_state(%Playing{} = state) do
    cards_in_hands(state.hands) ++ MapSet.to_list(state.played_cards)
  end

  defp cards_in_state(%Finished{} = state) do
    cards_in_hands(state.hands) ++ MapSet.to_list(state.played_cards)
  end

  defp cards_in_hands(hands) do
    hands |> Map.values() |> Enum.flat_map(&Hand.cards/1)
  end
end
