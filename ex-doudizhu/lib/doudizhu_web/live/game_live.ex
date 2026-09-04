defmodule DoudizhuWeb.GameLive do
  @moduledoc "Reactive browser adapter over the shared Doudizhu command and projection boundaries."

  use DoudizhuWeb, :live_view

  alias Doudizhu.Domain.Player
  alias Doudizhu.Replays
  alias Doudizhu.Rooms
  alias Doudizhu.Sessions.CommandGateway
  alias DoudizhuWeb.Gettext, as: GettextBackend
  alias DoudizhuWeb.{GameConnection, GameLiveHTML, Locale, Presence}

  @impl true
  def render(assigns), do: GameLiveHTML.index(assigns)

  @impl true
  def mount(params, %{"identity_id" => identity_id} = session, socket) do
    locale = Locale.negotiate([params["locale"], session["locale"]])
    Gettext.put_locale(GettextBackend, locale)

    socket =
      socket
      |> assign(
        page_title: nil,
        connected: connected?(socket),
        locale: locale,
        language_tag: Locale.language_tag(locale),
        identity_id: identity_id,
        connection_session_id: random_id("live"),
        mode: :welcome,
        player_name: "",
        room_id: nil,
        invite_code: nil,
        room: nil,
        subscribed_room_id: nil,
        game_id: nil,
        actor: nil,
        snapshot: nil,
        pending_version: nil,
        replay_games: [],
        replay: nil,
        replay_frame: nil,
        replay_playing: false,
        replay_token: nil,
        welcome_error: nil,
        room_error: nil,
        game_error: nil,
        replay_error: nil
      )
      |> stream(:events, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"replay" => game_id}, uri, socket) do
    {:noreply, socket |> assign(:current_uri, uri) |> open_replay(game_id)}
  end

  def handle_params(%{"history" => _value}, uri, socket) do
    {:noreply, socket |> assign(:current_uri, uri) |> open_replay_library()}
  end

  def handle_params(%{"room" => room_id} = params, uri, socket) do
    {:noreply, socket |> assign(:current_uri, uri) |> open_room(room_id, params["invite"])}
  end

  def handle_params(_params, uri, socket) do
    {:noreply, socket |> assign(:current_uri, uri) |> show_welcome()}
  end

  @impl true
  def handle_event("change-locale", %{"locale" => requested_locale}, socket) do
    locale = Locale.negotiate([requested_locale])

    {:noreply,
     socket
     |> push_event("store-locale", %{locale: locale, language_tag: Locale.language_tag(locale)})
     |> push_navigate(to: locale_path(socket.assigns.current_uri, locale))}
  end

  def handle_event("enter-room", %{"name" => name}, socket) do
    with {:ok, player} <- Player.new(socket.assigns.identity_id, name) do
      if socket.assigns.room_id do
        join_room(socket, player)
      else
        create_room(socket, player)
      end
    else
      {:error, reason} ->
        {:noreply, assign(socket, :welcome_error, GameLiveHTML.error_message(reason))}
    end
  end

  def handle_event("open-replay-library", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/?history=1")}
  end

  def handle_event("close-replay-library", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  def handle_event("open-replay", %{"game-id" => game_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?replay=#{game_id}")}
  end

  def handle_event("open-replay", %{"game_id" => game_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?replay=#{String.trim(game_id)}")}
  end

  def handle_event("ready", _params, socket) do
    own_seat = own_seat(socket.assigns.room, socket.assigns.identity_id)
    ready = not (own_seat && own_seat["ready"])

    case Rooms.set_ready(socket.assigns.room_id, socket.assigns.identity_id, ready) do
      {:ok, _seat} -> {:noreply, assign(socket, :room_error, nil)}
      {:error, reason} -> {:noreply, put_room_error(socket, reason)}
    end
  end

  def handle_event("start-game", _params, socket) do
    case Rooms.start_game(socket.assigns.room_id, socket.assigns.identity_id) do
      {:ok, room} -> {:noreply, room_started(socket, room)}
      {:error, reason} -> {:noreply, put_room_error(socket, reason)}
    end
  end

  def handle_event("place-bid", %{"bid" => bid}, socket) when bid in ~w(1 2 3) do
    dispatch_action(socket, %{"type" => "place_bid", "bid" => String.to_integer(bid)})
  end

  def handle_event("place-bid", _params, socket) do
    {:noreply, put_game_error(socket, "invalid_bid")}
  end

  def handle_event("auction-pass", _params, socket) do
    dispatch_action(socket, %{"type" => "auction_pass"})
  end

  def handle_event("play-selected", %{"cards" => cards}, socket) when is_list(cards) do
    dispatch_action(socket, %{"type" => "play_cards", "cards" => cards})
  end

  def handle_event("play-selected", _params, socket) do
    {:noreply, put_game_error(socket, "invalid_combination")}
  end

  def handle_event("play-pass", _params, socket) do
    dispatch_action(socket, %{"type" => "play_pass"})
  end

  def handle_event("resync", _params, socket) do
    case GameConnection.snapshot(socket.assigns.actor) do
      {:ok, snapshot} -> {:noreply, put_snapshot(socket, snapshot)}
      {:error, reason} -> {:noreply, put_game_error(socket, reason)}
    end
  end

  def handle_event("previous-replay-frame", _params, socket) do
    {:noreply,
     socket |> stop_replay() |> put_replay_frame(socket.assigns.replay_frame["index"] - 1)}
  end

  def handle_event("next-replay-frame", _params, socket) do
    {:noreply,
     socket |> stop_replay() |> put_replay_frame(socket.assigns.replay_frame["index"] + 1)}
  end

  def handle_event("seek-replay", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {parsed, ""} -> {:noreply, socket |> stop_replay() |> put_replay_frame(parsed)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle-replay", _params, %{assigns: %{replay_playing: true}} = socket) do
    {:noreply, stop_replay(socket)}
  end

  def handle_event("toggle-replay", _params, socket) do
    token = make_ref()
    send(self(), {:advance_replay, token})
    {:noreply, assign(socket, replay_playing: true, replay_token: token)}
  end

  def handle_event("exit-replay", _params, socket) do
    {:noreply, push_patch(stop_replay(socket), to: ~p"/?history=1")}
  end

  @impl true
  def handle_info({:room_message, room}, socket) do
    if room["room_id"] == socket.assigns.room_id and socket.assigns.mode == :room do
      {:noreply, room_started(socket, room)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:game_message, %{"kind" => "snapshot"} = snapshot}, socket) do
    if socket.assigns.mode == :game do
      {:noreply, put_snapshot(socket, snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:game_message, %{"kind" => "game_event"} = message}, socket) do
    if socket.assigns.mode == :game do
      event = message["event"]

      entry = %{
        id: "event-#{message["sequence"]}-#{System.unique_integer([:positive])}",
        event: event
      }

      {:noreply,
       socket
       |> stream_insert(:events, entry, at: -1, limit: -80)
       |> push_event("game-audio", %{event: event})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:advance_replay, token}, %{assigns: %{replay_token: token}} = socket) do
    next_index = socket.assigns.replay_frame["index"] + 1
    frame_count = socket.assigns.replay.metadata["frame_count"]

    if next_index >= frame_count do
      {:noreply, stop_replay(socket)}
    else
      socket = put_replay_frame(socket, next_index)
      Process.send_after(self(), {:advance_replay, token}, 1_100)
      {:noreply, socket}
    end
  end

  def handle_info({:advance_replay, _stale_token}, socket), do: {:noreply, socket}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp create_room(socket, player) do
    case Rooms.create(socket.assigns.identity_id, player.name) do
      {:ok, %{room: room, invite_code: invite_code}} ->
        socket = assign(socket, player_name: player.name, welcome_error: nil)
        path = ~p"/?room=#{room.id}&invite=#{invite_code}"
        {:noreply, push_patch(socket, to: path)}

      {:error, reason} ->
        {:noreply, assign(socket, :welcome_error, GameLiveHTML.error_message(reason))}
    end
  end

  defp join_room(socket, player) do
    case Rooms.join(
           socket.assigns.room_id,
           socket.assigns.invite_code,
           socket.assigns.identity_id,
           player.name
         ) do
      {:ok, _seat} ->
        socket =
          socket
          |> assign(player_name: player.name, welcome_error: nil)
          |> open_room(socket.assigns.room_id, socket.assigns.invite_code)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :welcome_error, GameLiveHTML.error_message(reason))}
    end
  end

  defp open_room(socket, room_id, invite_code) do
    case Rooms.snapshot(room_id) do
      nil ->
        socket
        |> show_welcome()
        |> assign(
          room_id: room_id,
          invite_code: invite_code,
          welcome_error: GameLiveHTML.error_message(:room_not_found)
        )

      room ->
        case own_seat(room, socket.assigns.identity_id) do
          nil ->
            socket
            |> leave_game()
            |> leave_room()
            |> assign(
              page_title: gettext("Join table"),
              mode: :welcome,
              room_id: room_id,
              invite_code: invite_code,
              room: room,
              welcome_error: nil
            )

          seat ->
            socket =
              socket
              |> subscribe_room(room_id)
              |> assign(
                page_title: gettext("Private table"),
                mode: :room,
                player_name: seat["player_name"],
                room_id: room_id,
                invite_code: invite_code,
                room: room,
                room_error: nil,
                welcome_error: nil
              )

            room_started(socket, room)
        end
    end
  end

  defp room_started(socket, %{"game_id" => game_id} = room) when is_binary(game_id) do
    socket = assign(socket, :room, room)

    if connected?(socket) do
      connect_game(socket, game_id)
    else
      socket
    end
  end

  defp room_started(socket, room), do: assign(socket, room: room, room_error: nil)

  defp connect_game(socket, game_id) do
    socket = leave_game(socket)

    case GameConnection.connect_player(
           socket.assigns.identity_id,
           game_id,
           socket.assigns.identity_id,
           socket.assigns.connection_session_id
         ) do
      {:ok, actor, snapshot} ->
        socket
        |> assign(
          page_title: gettext("Game in progress"),
          mode: :game,
          game_id: game_id,
          actor: actor,
          snapshot: snapshot,
          pending_version: nil,
          game_error: nil
        )
        |> reset_events([])

      {:error, reason} ->
        socket
        |> assign(mode: :room, game_error: GameLiveHTML.error_message(reason))
        |> put_room_error(reason)
    end
  end

  defp dispatch_action(%{assigns: %{actor: nil}} = socket, _action) do
    {:noreply, put_game_error(socket, :not_authorized)}
  end

  defp dispatch_action(%{assigns: %{pending_version: pending}} = socket, _action)
       when not is_nil(pending) do
    {:noreply, socket}
  end

  defp dispatch_action(socket, action) do
    expected_version = socket.assigns.snapshot["sequence"]

    envelope = %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => socket.assigns.game_id,
      "command_id" => random_id("live_command"),
      "expected_version" => expected_version,
      "action" => action
    }

    case CommandGateway.dispatch(socket.assigns.actor, envelope) do
      %{"status" => "accepted"} ->
        {:noreply,
         assign(socket,
           pending_version: expected_version + 1,
           game_error: nil
         )}

      result ->
        {:noreply,
         assign(socket,
           pending_version: nil,
           game_error: GameLiveHTML.error_message(result)
         )}
    end
  end

  defp put_snapshot(socket, snapshot) do
    current_sequence = get_in(socket.assigns.snapshot || %{}, ["sequence"])

    if is_nil(current_sequence) or snapshot["sequence"] >= current_sequence do
      assign(socket,
        snapshot: snapshot,
        pending_version: nil,
        game_error: nil
      )
    else
      socket
    end
  end

  defp open_replay_library(socket) do
    socket
    |> stop_replay()
    |> leave_game()
    |> leave_room()
    |> assign(
      page_title: gettext("Recorded games"),
      mode: :replay_library,
      replay_games: Replays.list_for_identity(socket.assigns.identity_id),
      replay: nil,
      replay_frame: nil,
      replay_error: nil,
      snapshot: nil
    )
    |> reset_events([])
  end

  defp open_replay(socket, game_id) do
    socket =
      socket
      |> stop_replay()
      |> leave_game()
      |> leave_room()

    with {:ok, replay} <- Replays.open(game_id),
         {:ok, frame} <- Replays.frame(replay, 0) do
      socket
      |> assign(
        page_title: gettext("Replay"),
        mode: :replay,
        game_id: game_id,
        replay: replay,
        replay_frame: frame,
        replay_error: nil,
        snapshot: frame["snapshot"]
      )
      |> reset_events(frame["history"])
    else
      {:error, reason} ->
        socket
        |> assign(
          page_title: gettext("Recorded games"),
          mode: :replay_library,
          replay_games: Replays.list_for_identity(socket.assigns.identity_id),
          replay_error: GameLiveHTML.error_message(reason),
          snapshot: nil
        )
        |> reset_events([])
    end
  end

  defp put_replay_frame(%{assigns: %{replay: nil}} = socket, _index), do: socket

  defp put_replay_frame(socket, index) do
    case Replays.frame(socket.assigns.replay, index) do
      {:ok, frame} ->
        socket
        |> assign(
          replay_frame: frame,
          snapshot: frame["snapshot"],
          replay_error: nil,
          game_error: nil
        )
        |> reset_events(frame["history"])

      {:error, :frame_not_found} ->
        socket
    end
  end

  defp show_welcome(socket) do
    socket
    |> stop_replay()
    |> leave_game()
    |> leave_room()
    |> assign(
      page_title: nil,
      mode: :welcome,
      room_id: nil,
      invite_code: nil,
      room: nil,
      game_id: nil,
      snapshot: nil,
      pending_version: nil,
      replay: nil,
      replay_frame: nil,
      replay_error: nil,
      welcome_error: nil
    )
    |> reset_events([])
  end

  defp subscribe_room(socket, room_id) do
    cond do
      not connected?(socket) ->
        socket

      socket.assigns.subscribed_room_id == room_id ->
        socket

      true ->
        socket = leave_room(socket)
        topic = Rooms.room_topic(room_id)
        :ok = Phoenix.PubSub.subscribe(Doudizhu.PubSub, topic)

        {:ok, _ref} =
          Presence.track(self(), topic, socket.assigns.identity_id, %{
            online_at: System.system_time(:second)
          })

        assign(socket, :subscribed_room_id, room_id)
    end
  end

  defp leave_room(%{assigns: %{subscribed_room_id: nil}} = socket), do: socket

  defp leave_room(socket) do
    topic = Rooms.room_topic(socket.assigns.subscribed_room_id)
    :ok = Presence.untrack(self(), topic, socket.assigns.identity_id)
    :ok = Phoenix.PubSub.unsubscribe(Doudizhu.PubSub, topic)
    assign(socket, :subscribed_room_id, nil)
  end

  defp leave_game(%{assigns: %{actor: nil}} = socket), do: socket

  defp leave_game(socket) do
    :ok = GameConnection.disconnect(socket.assigns.actor)
    assign(socket, actor: nil, game_id: nil, pending_version: nil)
  end

  defp reset_events(socket, events) do
    entries =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} -> %{id: "history-#{index}", event: event} end)

    stream(socket, :events, entries, reset: true)
  end

  defp stop_replay(socket) do
    assign(socket, replay_playing: false, replay_token: nil)
  end

  defp put_room_error(socket, reason),
    do: assign(socket, :room_error, GameLiveHTML.error_message(reason))

  defp put_game_error(socket, reason),
    do: assign(socket, :game_error, GameLiveHTML.error_message(reason))

  defp locale_path(uri, locale) do
    parsed = URI.parse(uri)

    query =
      parsed.query
      |> then(&if(&1, do: URI.decode_query(&1), else: %{}))
      |> Map.put("locale", locale)
      |> URI.encode_query()

    URI.to_string(%URI{path: parsed.path || "/", query: query})
  end

  defp own_seat(nil, _identity_id), do: nil

  defp own_seat(room, identity_id) do
    Enum.find(room["seats"], &(&1["player_id"] == identity_id))
  end

  defp random_id(prefix) do
    prefix <> "_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end
end
