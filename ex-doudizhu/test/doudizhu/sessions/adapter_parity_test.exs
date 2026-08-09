defmodule Doudizhu.Sessions.AdapterParityTest do
  use Doudizhu.DataCase, async: false
  import Phoenix.ChannelTest

  @endpoint DoudizhuWeb.Endpoint

  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor}
  alias Doudizhu.Sessions.LocalSession
  alias DoudizhuWeb.{GameChannel, SessionToken, UserSocket}
  import Doudizhu.DomainHelpers

  test "local and Channel adapters produce identical semantic transcripts" do
    suffix = System.unique_integer([:positive])
    local_game_id = "local-parity-#{suffix}"
    channel_game_id = "channel-parity-#{suffix}"

    for game_id <- [local_game_id, channel_game_id] do
      {:ok, _game} = game_id |> new_game() |> GameRepository.create()
      {:ok, _server} = GameSupervisor.start_game(game_id)
      GameServer.deal(game_id, standard_deck(), first_id())
    end

    on_exit(fn ->
      for game_id <- [local_game_id, channel_game_id],
          {server, _} <- Registry.lookup(Doudizhu.Games.Registry, game_id) do
        DynamicSupervisor.terminate_child(GameSupervisor, server)
      end
    end)

    local =
      start_supervised!(
        {LocalSession,
         owner: self(),
         identity_id: first_id(),
         game_id: local_game_id,
         player_id: first_id(),
         session_id: "local-parity-session"}
      )

    assert_receive {:local_message, ^local, local_initial}

    {:ok, channel_socket} = connect(UserSocket, %{"token" => SessionToken.sign(first_id())})

    {:ok, %{"snapshot" => channel_initial}, channel_socket} =
      subscribe_and_join(channel_socket, GameChannel, "game:#{channel_game_id}", %{
        "player_id" => first_id()
      })

    local_command = command(local_game_id)
    channel_command = command(channel_game_id)
    local_result = LocalSession.command(local, local_command)
    ref = push(channel_socket, "command", channel_command)
    assert_reply ref, :ok, channel_result

    local_messages = receive_local_messages(local, 3)
    assert_push "message", channel_event_1
    assert_push "message", channel_event_2
    assert_push "message", channel_snapshot
    channel_messages = [channel_event_1, channel_event_2, channel_snapshot]

    assert normalize(local_initial, local_game_id) == normalize(channel_initial, channel_game_id)
    assert normalize(local_result, local_game_id) == normalize(channel_result, channel_game_id)

    assert Enum.map(local_messages, &normalize(&1, local_game_id)) ==
             Enum.map(channel_messages, &normalize(&1, channel_game_id))
  end

  defp receive_local_messages(session, count) do
    Enum.map(1..count, fn _index ->
      receive do
        {:local_message, ^session, message} -> message
      after
        1_000 -> flunk("timed out waiting for local transcript")
      end
    end)
  end

  defp command(game_id) do
    %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => game_id,
      "command_id" => "parity-command",
      "expected_version" => 1,
      "action" => %{"type" => "place_bid", "bid" => 3}
    }
  end

  defp normalize(value, game_id) when is_map(value) do
    Map.new(value, fn {key, child} -> {key, normalize(child, game_id)} end)
  end

  defp normalize(value, game_id) when is_list(value), do: Enum.map(value, &normalize(&1, game_id))
  defp normalize(value, game_id) when value == game_id, do: "GAME"
  defp normalize(value, _game_id), do: value
end
