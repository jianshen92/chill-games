defmodule DoudizhuWeb.ReplayChannelTest do
  use Doudizhu.DataCase, async: false
  import Phoenix.ChannelTest

  @endpoint DoudizhuWeb.Endpoint

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor}
  alias Doudizhu.Sessions.LocalSession
  alias DoudizhuWeb.{ReplayChannel, SessionToken, UserSocket}
  import Doudizhu.DomainHelpers

  setup do
    game_id = "replay-channel-#{System.unique_integer([:positive])}"

    winning_hand =
      triple(:three) ++
        triple(:four) ++
        triple(:five) ++
        triple(:six) ++ pair(:seven) ++ pair(:eight) ++ pair(:nine) ++ pair(:ten)

    game = new_game(game_id)
    {:ok, ^game} = GameRepository.create(game)
    {:ok, _server} = GameSupervisor.start_game(game_id)
    GameServer.deal(game_id, deck_with_first_landlord_hand(winning_hand), first_id())

    session =
      start_supervised!(
        {LocalSession,
         owner: self(),
         identity_id: first_id(),
         game_id: game_id,
         player_id: first_id(),
         session_id: "replay-channel-session"}
      )

    assert_receive {:local_message, ^session, %{"kind" => "snapshot", "sequence" => 1}}

    assert LocalSession.command(
             session,
             command(game_id, "bid", 1, %{"type" => "place_bid", "bid" => 3})
           )[
             "status"
           ] == "accepted"

    cards = Enum.map(winning_hand, &Card.to_id/1)

    assert LocalSession.command(
             session,
             command(game_id, "play", 2, %{"type" => "play_cards", "cards" => cards})
           )["status"] == "accepted"

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
        [] -> :ok
      end
    end)

    %{game_id: game_id}
  end

  test "participant lists and seeks full-information replay frames", %{game_id: game_id} do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign(first_id())})

    assert {:ok, %{"games" => games}, _lobby} =
             subscribe_and_join(socket, ReplayChannel, "replay:lobby", %{})

    assert Enum.any?(games, &(&1["game_id"] == game_id))

    assert {:ok, %{"replay" => replay, "frame" => initial}, replay_socket} =
             subscribe_and_join(socket, ReplayChannel, "replay:#{game_id}", %{})

    assert replay["frame_count"] == 4
    assert initial["snapshot"]["game"]["phase"] == "awaiting_deal"

    ref = push(replay_socket, "frame", %{"index" => 1})
    first_id = first_id()
    second_id = second_id()
    third_id = third_id()

    assert_reply ref, :ok, %{
      "snapshot" => %{
        "sequence" => 1,
        "hands" => %{^first_id => first, ^second_id => second, ^third_id => third},
        "bottom_cards" => bottom
      },
      "history" => [_deal]
    }

    assert length(first) == 17
    assert length(second) == 17
    assert length(third) == 17
    assert length(bottom) == 3
  end

  test "any signed viewer can open a completed replay by game ID", %{game_id: game_id} do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign("public-viewer")})

    assert {:ok, %{"replay" => %{"public_replay_id" => ^game_id}}, _socket} =
             subscribe_and_join(socket, ReplayChannel, "replay:#{game_id}", %{})
  end

  defp command(game_id, command_id, expected_version, action) do
    %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => game_id,
      "command_id" => command_id,
      "expected_version" => expected_version,
      "action" => action
    }
  end
end
