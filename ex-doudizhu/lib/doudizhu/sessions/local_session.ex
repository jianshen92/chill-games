defmodule Doudizhu.Sessions.LocalSession do
  @moduledoc "Wire-faithful in-memory transport for local controllers and adapter tests."

  use GenServer

  alias Doudizhu.Games.{GameServer, GameSupervisor, OutboxPublisher}
  alias Doudizhu.Protocol.Encoder
  alias Doudizhu.Sessions.{CommandGateway, LeaseManager}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @spec command(pid(), map() | binary()) :: map()
  def command(session, payload), do: GenServer.call(session, {:command, payload})

  @spec actor(pid()) :: Doudizhu.Sessions.ActorContext.t()
  def actor(session), do: GenServer.call(session, :actor)

  @impl true
  def init(options) do
    owner = Keyword.get(options, :owner, self())
    identity_id = Keyword.fetch!(options, :identity_id)
    game_id = Keyword.fetch!(options, :game_id)
    player_id = Keyword.fetch!(options, :player_id)
    session_id = Keyword.get_lazy(options, :session_id, &random_session_id/0)

    with {:ok, _server} <- GameSupervisor.start_game(game_id),
         {:ok, actor} <- LeaseManager.claim(identity_id, game_id, player_id, session_id),
         :ok <- Phoenix.PubSub.subscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game_id)),
         :ok <-
           Phoenix.PubSub.subscribe(
             Doudizhu.PubSub,
             OutboxPublisher.player_topic(game_id, player_id)
           ),
         {:ok, snapshot} <- GameServer.snapshot(game_id, {:player, player_id}) do
      send(owner, {:local_message, self(), Encoder.wire_round_trip(snapshot)})
      {:ok, %{owner: owner, actor: actor}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:actor, _from, state), do: {:reply, state.actor, state}

  def handle_call({:command, payload}, _from, state) do
    wire_payload = if is_binary(payload), do: payload, else: Jason.encode!(payload)
    result = CommandGateway.dispatch(state.actor, wire_payload) |> Encoder.wire_round_trip()
    {:reply, result, state}
  end

  @impl true
  def handle_info({:game_message, message}, state) do
    send(state.owner, {:local_message, self(), Encoder.wire_round_trip(message)})
    {:noreply, state}
  end

  defp random_session_id,
    do: "session_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
