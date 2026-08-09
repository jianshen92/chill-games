defmodule Doudizhu.Projection.SnapshotTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Domain.Card
  alias Doudizhu.Projection.{Event, Snapshot}
  import Doudizhu.DomainHelpers

  test "player snapshot contains own hand and only opponent hand counts" do
    game = new_game() |> deal()
    {:ok, snapshot} = Snapshot.build(game, {:player, first_id()})

    own_ids = game |> hand_cards(first_id()) |> Enum.map(&Card.to_id/1)
    opponent_ids = game |> hand_cards(second_id()) |> Enum.map(&Card.to_id/1)

    assert snapshot["you"]["hand"] == Enum.sort_by(own_ids, &card_strength/1)
    assert snapshot["game"]["hand_counts"][second_id()] == 17

    encoded = Jason.encode!(snapshot)
    assert Enum.all?(own_ids, &String.contains?(encoded, ~s("#{&1}")))
    refute Enum.any?(opponent_ids, &String.contains?(encoded, ~s("#{&1}")))
  end

  test "spectator receives no private player view" do
    game = new_game() |> deal()
    {:ok, snapshot} = Snapshot.build(game, :spectator)
    assert snapshot["you"] == nil
    refute Map.has_key?(snapshot["game"], "hands")
  end

  test "public deal event does not contain dealt or bottom cards" do
    game0 = new_game()
    {game1, events} = execute!(game0, {:deal, standard_deck(), first_id()})
    [message] = Event.public(game1, events)

    assert message["sequence"] == 1

    assert message["event"] == %{
             "type" => "cards_dealt",
             "deal_number" => 1,
             "auction_starter" => first_id()
           }

    refute Jason.encode!(message) =~ "bottom"
    refute Jason.encode!(message) =~ "hand"
  end

  test "landlord choice reveals bottom cards only according to rules" do
    game0 = new_game() |> deal()
    {game1, events} = execute!(game0, {:bid, first_id(), 3})
    [_bid, landlord] = Event.public(game1, events)

    assert landlord["event"]["type"] == "landlord_chosen"
    assert length(landlord["event"]["revealed_bottom_cards"]) == 3
  end

  test "unknown player cannot obtain a private projection" do
    assert Snapshot.build(new_game(), {:player, "stranger"}) == {:error, :not_authorized}
  end

  defp card_strength(card_id) do
    {:ok, card} = Card.from_id(card_id)
    {Card.strength(card), Enum.find_index(Card.suits(), &(&1 == card.suit)) || 4}
  end
end
