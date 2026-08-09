defmodule Doudizhu.Projection.Event do
  @moduledoc "Projects internal domain events into safe public protocol events."

  alias Doudizhu.Domain.Game
  alias Doudizhu.Projection.Value

  @spec public(Game.t(), [map()]) :: [map()]
  def public(%Game{} = game, events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {event, index} ->
      %{
        "protocol_version" => 1,
        "kind" => "game_event",
        "game_id" => game.id,
        "sequence" => game.version,
        "event_index" => index,
        "event" => encode_event(event)
      }
    end)
  end

  defp encode_event(%{type: :cards_dealt} = event) do
    %{
      "type" => "cards_dealt",
      "deal_number" => event.deal_number,
      "auction_starter" => event.auction_starter
    }
  end

  defp encode_event(%{type: :auction_passed, player_id: player_id}),
    do: %{"type" => "auction_passed", "player_id" => player_id}

  defp encode_event(%{type: :bid_placed, player_id: player_id, bid: bid}),
    do: %{"type" => "bid_placed", "player_id" => player_id, "bid" => bid}

  defp encode_event(%{type: :deal_voided, deal_number: deal_number}),
    do: %{"type" => "deal_voided", "deal_number" => deal_number}

  defp encode_event(%{type: :landlord_chosen} = event) do
    %{
      "type" => "landlord_chosen",
      "landlord" => event.landlord,
      "bid" => event.bid,
      "revealed_bottom_cards" =>
        if(event.revealed_bottom_cards, do: Value.cards(event.revealed_bottom_cards), else: nil)
    }
  end

  defp encode_event(%{type: :cards_played} = event) do
    %{
      "type" => "cards_played",
      "player_id" => event.player_id,
      "combination" => Value.combination(event.combination)
    }
  end

  defp encode_event(%{type: :turn_passed, player_id: player_id}),
    do: %{"type" => "turn_passed", "player_id" => player_id}

  defp encode_event(%{type: :lead_cleared, next_leader: next_leader}),
    do: %{"type" => "lead_cleared", "next_leader" => next_leader}

  defp encode_event(%{type: :game_finished, settlement: settlement}),
    do: %{"type" => "game_finished", "settlement" => Value.settlement(settlement)}
end
