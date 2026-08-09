defmodule Doudizhu.Games.OutboxPublisher do
  @moduledoc "Publishes committed outbox messages and retries records left by crashes."

  use GenServer

  alias Doudizhu.Games.{GameRepository, OutboxMessage}

  @interval :timer.seconds(1)

  def start_link(options \\ []), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @spec publish([OutboxMessage.t()]) :: :ok
  def publish(messages) when is_list(messages) do
    Enum.each(messages, &publish_one/1)
    :ok
  end

  @spec drain() :: :ok
  def drain, do: GenServer.call(__MODULE__, :drain)

  @spec public_topic(String.t()) :: String.t()
  def public_topic(game_id), do: "game:#{game_id}:public"

  @spec player_topic(String.t(), String.t()) :: String.t()
  def player_topic(game_id, player_id), do: "game:#{game_id}:player:#{player_id}"

  @impl true
  def init(_options) do
    if Application.get_env(:doudizhu, :outbox_polling, true), do: send(self(), :drain)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:drain, _from, state) do
    do_drain()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:drain, state) do
    do_drain()

    if Application.get_env(:doudizhu, :outbox_polling, true),
      do: Process.send_after(self(), :drain, @interval)

    {:noreply, state}
  end

  defp do_drain do
    GameRepository.unpublished()
    |> Enum.each(&publish_one/1)
  end

  defp publish_one(%OutboxMessage{} = message) do
    topic =
      case message.audience_kind do
        "public" -> public_topic(message.game_id)
        "player" -> player_topic(message.game_id, message.audience_id)
      end

    :ok = Phoenix.PubSub.broadcast(Doudizhu.PubSub, topic, {:game_message, message.payload})
    {:ok, _message} = GameRepository.mark_published(message)
    :ok
  end
end
