defmodule DoudizhuWeb.RoomChannel do
  @moduledoc "Phoenix transport for durable friend-room lifecycle operations."

  use DoudizhuWeb, :channel

  alias Doudizhu.Protocol.Message
  alias Doudizhu.Rooms

  @impl true
  def join("room:lobby", _payload, socket), do: {:ok, %{}, socket}

  def join("room:" <> room_id, payload, socket) do
    name = Map.get(payload, "player_name", socket.assigns.identity_id)
    invite_code = Map.get(payload, "invite_code")

    with {:ok, _seat} <- Rooms.join(room_id, invite_code, socket.assigns.identity_id, name) do
      socket = assign(socket, :room_id, room_id)
      send(self(), :track_presence)
      {:ok, %{"room" => Rooms.snapshot(room_id)}, socket}
    else
      {:error, reason} -> {:error, room_error(reason)}
    end
  end

  @impl true
  def handle_in("create", %{"player_name" => player_name}, %{topic: "room:lobby"} = socket) do
    case Rooms.create(socket.assigns.identity_id, player_name) do
      {:ok, %{room: room, invite_code: invite_code}} ->
        {:reply,
         {:ok,
          %{
            "room_id" => room.id,
            "invite_code" => invite_code,
            "room" => Rooms.snapshot(room.id)
          }}, socket}

      {:error, reason} ->
        {:reply, {:error, room_error(reason)}, socket}
    end
  end

  def handle_in("ready", %{"ready" => ready}, socket) when is_boolean(ready) do
    case Rooms.set_ready(socket.assigns.room_id, socket.assigns.identity_id, ready) do
      {:ok, _seat} -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, room_error(reason)}, socket}
    end
  end

  def handle_in("start", _payload, socket) do
    case Rooms.start_game(socket.assigns.room_id, socket.assigns.identity_id) do
      {:ok, snapshot} -> {:reply, {:ok, snapshot}, socket}
      {:error, reason} -> {:reply, {:error, room_error(reason)}, socket}
    end
  end

  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, Message.protocol_error(%{code: "unknown_channel_event"})}, socket}

  @impl true
  def handle_info(:track_presence, socket) do
    {:ok, _ref} =
      DoudizhuWeb.Presence.track(socket, socket.assigns.identity_id, %{
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", DoudizhuWeb.Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:room_message, message}, socket) do
    push(socket, "message", message)
    {:noreply, socket}
  end

  defp room_error(reason) do
    code =
      case reason do
        :room_not_found -> "room_not_found"
        :room_not_open -> "room_not_open"
        :room_full -> "room_full"
        :invalid_invite -> "invalid_invite"
        :not_in_room -> "not_in_room"
        :not_room_owner -> "not_room_owner"
        :players_not_ready -> "players_not_ready"
        _ -> "room_error"
      end

    Message.protocol_error(%{code: code})
  end
end
