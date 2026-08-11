defmodule DoudizhuWeb.GameChannel do
  @moduledoc "Thin Phoenix transport adapter over the shared game session boundary."

  use DoudizhuWeb, :channel

  alias Doudizhu.Protocol.Message
  alias Doudizhu.Sessions.CommandGateway
  alias DoudizhuWeb.GameConnection

  @impl true
  def join("game:" <> game_id, payload, socket) do
    with {:ok, actor, snapshot} <- connect(socket, game_id, payload) do
      {:ok, %{"snapshot" => snapshot}, assign(socket, :actor, actor)}
    else
      {:error, reason} -> {:error, Message.protocol_error(%{code: error_code(reason)})}
    end
  end

  @impl true
  def handle_in("command", payload, socket) do
    result = CommandGateway.dispatch(socket.assigns.actor, payload)
    {:reply, {:ok, result}, socket}
  end

  def handle_in("resync", _payload, socket) do
    case GameConnection.snapshot(socket.assigns.actor) do
      {:ok, snapshot} ->
        {:reply, {:ok, snapshot}, socket}

      {:error, reason} ->
        {:reply, {:error, Message.protocol_error(%{code: error_code(reason)})}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, Message.protocol_error(%{code: "unknown_channel_event"})}, socket}
  end

  @impl true
  def handle_info({:game_message, message}, socket) do
    push(socket, "message", message)
    {:noreply, socket}
  end

  defp connect(socket, game_id, %{"player_id" => player_id}) do
    GameConnection.connect_player(
      socket.assigns.identity_id,
      game_id,
      player_id,
      socket.assigns.session_id
    )
  end

  defp connect(socket, game_id, %{"role" => "spectator"}) do
    GameConnection.connect_spectator(
      socket.assigns.identity_id,
      game_id,
      socket.assigns.session_id
    )
  end

  defp connect(_socket, _game_id, _payload), do: {:error, :not_authorized}

  defp error_code(:game_not_found), do: "game_not_found"
  defp error_code(:not_authorized), do: "not_authorized"
  defp error_code(_reason), do: "internal_error"
end
