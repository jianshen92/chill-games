defmodule DoudizhuWeb.ReplayChannel do
  @moduledoc "Public-by-game-ID Channel adapter for deterministic completed-game replays."

  use DoudizhuWeb, :channel

  alias Doudizhu.Protocol.Message
  alias Doudizhu.Replays

  @impl true
  def join("replay:lobby", _payload, socket) do
    {:ok, %{"games" => Replays.list_for_identity(socket.assigns.identity_id)}, socket}
  end

  def join("replay:" <> game_id, _payload, socket) do
    with {:ok, replay} <- Replays.open(game_id),
         {:ok, first_frame} <- Replays.frame(replay, 0) do
      {:ok, %{"replay" => replay.metadata, "frame" => first_frame},
       assign(socket, :replay, replay)}
    else
      {:error, reason} -> {:error, replay_error(reason)}
    end
  end

  @impl true
  def handle_in("frame", %{"index" => index}, socket) do
    case Replays.frame(socket.assigns.replay, index) do
      {:ok, frame} -> {:reply, {:ok, frame}, socket}
      {:error, reason} -> {:reply, {:error, replay_error(reason)}, socket}
    end
  end

  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, Message.protocol_error(%{code: "unknown_channel_event"})}, socket}

  defp replay_error(reason) do
    code =
      case reason do
        :replay_not_finished -> "replay_not_finished"
        :game_not_found -> "game_not_found"
        :frame_not_found -> "replay_frame_not_found"
        :replay_diverged -> "replay_diverged"
        {:replay_failed, _command_id, _failure} -> "replay_corrupt"
        _reason -> "replay_error"
      end

    Message.protocol_error(%{code: code})
  end
end
