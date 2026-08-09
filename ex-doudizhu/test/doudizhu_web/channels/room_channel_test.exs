defmodule DoudizhuWeb.RoomChannelTest do
  use Doudizhu.DataCase, async: false
  import Phoenix.ChannelTest

  @endpoint DoudizhuWeb.Endpoint

  alias Doudizhu.Games.{GameServer, GameSupervisor}
  alias DoudizhuWeb.{RoomChannel, SessionToken, UserSocket}
  import Doudizhu.DomainHelpers

  test "three friends create, join, ready, and start a durable game" do
    alice_lobby = connect_identity(first_id()) |> join_lobby()
    create_ref = push(alice_lobby, "create", %{"player_name" => "Alice"})

    assert_reply create_ref, :ok, %{"room_id" => room_id, "invite_code" => invite_code}

    alice = join_room(alice_lobby, room_id, nil, "Alice")
    bob = connect_identity(second_id()) |> join_room(room_id, invite_code, "Bob")
    chen = connect_identity(third_id()) |> join_room(room_id, invite_code, "Chen")

    for socket <- [alice, bob, chen] do
      ref = push(socket, "ready", %{"ready" => true})
      assert_reply ref, :ok
    end

    start_ref = push(alice, "start", %{})

    assert_reply start_ref, :ok, %{
      "kind" => "room_snapshot",
      "status" => "started",
      "game_id" => game_id,
      "seats" => seats
    }

    assert length(seats) == 3
    assert GameServer.game(game_id).version == 1
    assert GameServer.game(game_id).state.current_bidder == first_id()

    [{server, _}] = Registry.lookup(Doudizhu.Games.Registry, game_id)
    ref = Process.monitor(server)
    assert :ok = DynamicSupervisor.terminate_child(GameSupervisor, server)
    assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}
  end

  test "invalid invite cannot claim a room seat" do
    alice_lobby = connect_identity(first_id()) |> join_lobby()
    ref = push(alice_lobby, "create", %{"player_name" => "Alice"})
    assert_reply ref, :ok, %{"room_id" => room_id}

    bob_socket = connect_identity(second_id())

    assert {:error, %{"error" => %{"code" => "invalid_invite"}}} =
             subscribe_and_join(bob_socket, RoomChannel, "room:#{room_id}", %{
               "invite_code" => "WRONG",
               "player_name" => "Bob"
             })
  end

  defp connect_identity(identity_id) do
    {:ok, socket} = connect(UserSocket, %{"token" => SessionToken.sign(identity_id)})
    socket
  end

  defp join_lobby(socket) do
    {:ok, _reply, socket} = subscribe_and_join(socket, RoomChannel, "room:lobby", %{})
    socket
  end

  defp join_room(socket, room_id, invite_code, player_name) do
    payload =
      %{"player_name" => player_name}
      |> then(fn payload ->
        if invite_code, do: Map.put(payload, "invite_code", invite_code), else: payload
      end)

    {:ok, %{"room" => _room}, socket} =
      subscribe_and_join(socket, RoomChannel, "room:#{room_id}", payload)

    socket
  end
end
