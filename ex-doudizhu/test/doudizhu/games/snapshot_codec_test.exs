defmodule Doudizhu.Games.SnapshotCodecTest do
  use ExUnit.Case, async: true

  alias Doudizhu.Games.SnapshotCodec
  import Doudizhu.DomainHelpers

  test "round trips every active phase through JSON-compatible data" do
    awaiting = new_game()
    bidding = awaiting |> deal()
    playing = bidding |> bid_three()
    card = playing |> hand_cards(first_id()) |> hd()
    {after_play, _events} = execute!(playing, {:play_cards, first_id(), [card]})

    for game <- [awaiting, bidding, playing, after_play] do
      encoded = game |> SnapshotCodec.encode() |> Jason.encode!() |> Jason.decode!()
      assert {:ok, decoded} = SnapshotCodec.decode(encoded)
      assert decoded == game
    end
  end

  test "rejects unsupported snapshot versions" do
    assert SnapshotCodec.decode(%{"codec_version" => 99}) ==
             {:error, {:unsupported_snapshot_codec, 99}}
  end
end
