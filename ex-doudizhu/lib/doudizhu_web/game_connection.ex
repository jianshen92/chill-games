defmodule DoudizhuWeb.GameConnection do
  @moduledoc "Shared game connection boundary for Channel and LiveView browser adapters."

  alias Doudizhu.Games.{GameServer, GameSupervisor, OutboxPublisher}
  alias Doudizhu.Sessions.{ActorContext, LeaseManager}

  @spec connect_player(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, ActorContext.t(), map()} | {:error, term()}
  def connect_player(identity_id, game_id, player_id, session_id) do
    with {:ok, _server} <- GameSupervisor.start_game(game_id),
         {:ok, actor} <- LeaseManager.claim(identity_id, game_id, player_id, session_id),
         :ok <- subscribe(actor),
         {:ok, snapshot} <- snapshot(actor) do
      {:ok, actor, snapshot}
    end
  end

  @spec connect_spectator(String.t(), String.t(), String.t()) ::
          {:ok, ActorContext.t(), map()} | {:error, term()}
  def connect_spectator(identity_id, game_id, session_id) do
    with {:ok, _server} <- GameSupervisor.start_game(game_id) do
      actor = LeaseManager.spectator(identity_id, game_id, session_id)

      with :ok <- subscribe(actor),
           {:ok, snapshot} <- snapshot(actor) do
        {:ok, actor, snapshot}
      end
    end
  end

  @spec snapshot(ActorContext.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(%ActorContext{game_id: game_id, role: :spectator}),
    do: GameServer.snapshot(game_id, :spectator)

  def snapshot(%ActorContext{game_id: game_id, player_id: player_id, role: :player}),
    do: GameServer.snapshot(game_id, {:player, player_id})

  @spec disconnect(ActorContext.t()) :: :ok
  def disconnect(%ActorContext{game_id: game_id, role: :spectator}) do
    Phoenix.PubSub.unsubscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game_id))
  end

  def disconnect(%ActorContext{game_id: game_id, player_id: player_id, role: :player}) do
    :ok = Phoenix.PubSub.unsubscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game_id))
    Phoenix.PubSub.unsubscribe(Doudizhu.PubSub, OutboxPublisher.player_topic(game_id, player_id))
  end

  defp subscribe(%ActorContext{game_id: game_id, role: :spectator}) do
    Phoenix.PubSub.subscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game_id))
  end

  defp subscribe(%ActorContext{game_id: game_id, player_id: player_id, role: :player}) do
    with :ok <- Phoenix.PubSub.subscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game_id)) do
      Phoenix.PubSub.subscribe(Doudizhu.PubSub, OutboxPublisher.player_topic(game_id, player_id))
    end
  end
end
