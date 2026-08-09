defmodule Doudizhu.Protocol.DecoderTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Domain.Card
  alias Doudizhu.Protocol.{CommandEnvelope, Decoder, Encoder, Message}

  test "decodes a versioned play command without creating atoms" do
    payload = %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => "game-1",
      "command_id" => "command-1",
      "expected_version" => 42,
      "action" => %{"type" => "play_cards", "cards" => ["C3", "D3"]},
      "future_field" => "ignored"
    }

    assert {:ok,
            %CommandEnvelope{
              game_id: "game-1",
              command_id: "command-1",
              expected_version: 42,
              action: {:play_cards, cards}
            }} = Decoder.decode_command(payload)

    assert Enum.map(cards, &Card.to_id/1) == ["C3", "D3"]
  end

  test "decodes JSON through the same path" do
    payload =
      Jason.encode!(%{
        "protocol_version" => 1,
        "kind" => "command",
        "game_id" => "game-1",
        "command_id" => "command-2",
        "expected_version" => 1,
        "action" => %{"type" => "place_bid", "bid" => 3}
      })

    assert {:ok, %CommandEnvelope{action: {:place_bid, 3}}} = Decoder.decode_command(payload)
  end

  test "rejects malformed and unsupported protocol data" do
    assert Decoder.decode_command("{") == {:error, %{code: "malformed_json"}}

    assert Decoder.decode_command(%{"protocol_version" => 99}) ==
             {:error, %{code: "unsupported_protocol_version", field: "protocol_version"}}

    assert {:error, %{code: "invalid_card_id", details: "ZZ"}} =
             Decoder.decode_command(%{
               "protocol_version" => 1,
               "kind" => "command",
               "game_id" => "g",
               "command_id" => "c",
               "expected_version" => 0,
               "action" => %{"type" => "play_cards", "cards" => ["ZZ"]}
             })
  end

  test "command results survive a JSON wire round trip" do
    accepted = Message.accepted("game-1", "command-1", 4)
    assert Encoder.wire_round_trip(accepted) == accepted

    rejected = Message.rejected("game-1", "command-2", 4, {:stale_game_version, 4})
    assert Encoder.wire_round_trip(rejected) == rejected
    assert rejected["error"]["code"] == "stale_game_version"
  end
end
