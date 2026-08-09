defmodule DoudizhuWeb.GameChannelTest do
  use Doudizhu.DataCase, async: false
  import Phoenix.ChannelTest

  @endpoint DoudizhuWeb.Endpoint

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor}
  alias DoudizhuWeb.{GameChannel, SessionToken, UserSocket}
  import Doudizhu.DomainHelpers

  setup do
    game_id = "game-channel-#{System.unique_integer([:positive])}"
    game = new_game(game_id)
    {:ok, ^game} = GameRepository.create(game)
    {:ok, server} = GameSupervisor.start_game(game_id)
    GameServer.deal(game_id, standard_deck(), first_id())

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
        [] -> :ok
      end
    end)

    %{game_id: game_id, server: server}
  end

  test "authenticated player joins, receives redacted snapshot, and commands through shared gateway",
       %{
         game_id: game_id
       } do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign(first_id())})

    assert {:ok, %{"snapshot" => snapshot}, socket} =
             subscribe_and_join(socket, GameChannel, "game:#{game_id}", %{
               "player_id" => first_id()
             })

    assert snapshot["sequence"] == 1
    assert snapshot["you"]["player_id"] == first_id()
    assert length(snapshot["you"]["hand"]) == 17

    opponent_ids =
      game_id
      |> GameServer.game()
      |> hand_cards(second_id())
      |> Enum.map(&Card.to_id/1)

    refute Enum.any?(opponent_ids, &String.contains?(Jason.encode!(snapshot), ~s("#{&1}")))

    ref =
      push(
        socket,
        "command",
        command(game_id, "channel-command-1", 1, %{"type" => "place_bid", "bid" => 3})
      )

    assert_reply ref, :ok, %{"status" => "accepted", "game_version" => 2}
    assert_push "message", %{"kind" => "game_event", "sequence" => 2}
    assert_push "message", %{"kind" => "game_event", "sequence" => 2}
    assert_push "message", %{"kind" => "snapshot", "sequence" => 2}

    resync = push(socket, "resync", %{})
    assert_reply resync, :ok, %{"kind" => "snapshot", "sequence" => 2}
  end

  test "spectator gets public view and cannot command", %{game_id: game_id} do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign("spectator")})

    assert {:ok, %{"snapshot" => %{"you" => nil}}, socket} =
             subscribe_and_join(socket, GameChannel, "game:#{game_id}", %{"role" => "spectator"})

    ref =
      push(
        socket,
        "command",
        command(game_id, "spectator-command", 1, %{"type" => "auction_pass"})
      )

    assert_reply ref, :ok, %{
      "kind" => "protocol_error",
      "error" => %{"code" => "not_authorized"}
    }
  end

  test "an authenticated identity cannot claim another player's seat", %{game_id: game_id} do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign("intruder")})

    assert {:error, %{"error" => %{"code" => "not_authorized"}}} =
             subscribe_and_join(socket, GameChannel, "game:#{game_id}", %{
               "player_id" => first_id()
             })
  end

  test "socket rejects invalid authentication token" do
    assert {:error, :invalid} = connect(UserSocket, %{"token" => "invalid"})
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
