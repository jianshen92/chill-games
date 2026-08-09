defmodule Doudizhu.Games.GameSupervisor do
  @moduledoc "Starts and discovers one GameServer per active game."

  use DynamicSupervisor

  alias Doudizhu.Games.GameServer

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(options \\ []) do
    DynamicSupervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec start_game(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_game(game_id) do
    case DynamicSupervisor.start_child(__MODULE__, {GameServer, game_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(_options), do: DynamicSupervisor.init(strategy: :one_for_one)
end
