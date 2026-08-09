defmodule Doudizhu.Sessions.LocalSessionTest do
  use Doudizhu.DataCase, async: false

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor}
  alias Doudizhu.Sessions.LocalSession
  import Doudizhu.DomainHelpers

  setup do
    game_id = "game-#{System.unique_integer([:positive])}"
    game = new_game(game_id)
    assert {:ok, ^game} = GameRepository.create(game)
    assert {:ok, pid} = GameSupervisor.start_game(game_id)

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{server, _}] -> DynamicSupervisor.terminate_child(GameSupervisor, server)
        [] -> :ok
      end
    end)

    %{game_id: game_id, server: pid}
  end

  test "wire-faithful local sessions support idempotency, projections, and stale versions", %{
    game_id: game_id
  } do
    deal_result = GameServer.deal(game_id, standard_deck(), first_id())
    assert deal_result["status"] == "accepted"
    assert deal_result["game_version"] == 1

    first = start_session!(game_id, first_id(), first_id(), "session-1")
    second = start_session!(game_id, second_id(), second_id(), "session-2")
    third = start_session!(game_id, third_id(), third_id(), "session-3")

    assert_snapshot(first, 1, first_id())
    assert_snapshot(second, 1, second_id())
    assert_snapshot(third, 1, third_id())

    command = command(game_id, "command-1", 1, %{"type" => "place_bid", "bid" => 1})
    result = LocalSession.command(first, command)
    assert result["status"] == "accepted"
    assert result["game_version"] == 2

    assert LocalSession.command(first, command) == result

    reused = command(game_id, "command-1", 2, %{"type" => "place_bid", "bid" => 2})
    assert LocalSession.command(first, reused)["error"]["code"] == "command_id_reused"

    stale = command(game_id, "stale-1", 1, %{"type" => "auction_pass"})
    stale_result = LocalSession.command(second, stale)
    assert stale_result["status"] == "rejected"
    assert stale_result["error"] == %{"code" => "stale_game_version", "current_version" => 2}
    assert LocalSession.command(second, stale) == stale_result

    assert_receive {:local_message, ^first, %{"kind" => "game_event", "sequence" => 2}}
    assert_receive {:local_message, ^first, %{"kind" => "snapshot", "sequence" => 2}}
  end

  test "new controller lease supersedes the old connection", %{game_id: game_id} do
    GameServer.deal(game_id, standard_deck(), first_id())
    old = start_session!(game_id, first_id(), first_id(), "old-session")
    assert_snapshot(old, 1, first_id())

    replacement = start_session!(game_id, first_id(), first_id(), "new-session")
    assert_snapshot(replacement, 1, first_id())

    payload = command(game_id, "command-1", 1, %{"type" => "place_bid", "bid" => 3})

    assert LocalSession.command(old, payload) == %{
             "protocol_version" => 1,
             "kind" => "protocol_error",
             "error" => %{"code" => "controller_lease_invalid"}
           }

    assert LocalSession.command(replacement, payload)["status"] == "accepted"
  end

  test "GameServer reloads the committed snapshot after termination", %{
    game_id: game_id,
    server: server
  } do
    GameServer.deal(game_id, standard_deck(), first_id())
    first = start_session!(game_id, first_id(), first_id(), "session-1")
    assert_snapshot(first, 1, first_id())

    result =
      LocalSession.command(
        first,
        command(game_id, "command-1", 1, %{"type" => "place_bid", "bid" => 3})
      )

    assert result["game_version"] == 2

    ref = Process.monitor(server)
    assert :ok = DynamicSupervisor.terminate_child(GameSupervisor, server)
    assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}

    assert {:ok, new_server} = GameSupervisor.start_game(game_id)
    assert new_server != server
    assert GameServer.game(game_id).version == 2
    assert GameServer.game(game_id).state.landlord == first_id()
  end

  test "private snapshots never contain an opponent's unplayed hand", %{game_id: game_id} do
    GameServer.deal(game_id, standard_deck(), first_id())
    first = start_session!(game_id, first_id(), first_id(), "session-1")

    assert_receive {:local_message, ^first, snapshot}
    game = GameServer.game(game_id)
    opponent_ids = game |> hand_cards(second_id()) |> Enum.map(&Card.to_id/1)
    encoded = Jason.encode!(snapshot)

    refute Enum.any?(opponent_ids, &String.contains?(encoded, ~s("#{&1}")))
  end

  defp start_session!(game_id, player_id, identity_id, session_id) do
    child =
      Supervisor.child_spec(
        {LocalSession,
         owner: self(),
         identity_id: identity_id,
         game_id: game_id,
         player_id: player_id,
         session_id: session_id},
        id: {LocalSession, session_id}
      )

    start_supervised!(child)
  end

  defp assert_snapshot(session, sequence, player_id) do
    assert_receive {:local_message, ^session,
                    %{
                      "kind" => "snapshot",
                      "sequence" => ^sequence,
                      "you" => %{"player_id" => ^player_id}
                    }}
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
