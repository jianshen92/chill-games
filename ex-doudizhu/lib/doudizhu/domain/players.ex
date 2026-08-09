defmodule Doudizhu.Domain.Players do
  @moduledoc "Exactly three distinct players in table order."

  alias Doudizhu.Domain.Player

  @enforce_keys [:first, :second, :third]
  defstruct [:first, :second, :third]

  @type seat :: :first | :second | :third
  @type t :: %__MODULE__{first: Player.t(), second: Player.t(), third: Player.t()}

  @spec new(Player.t(), Player.t(), Player.t()) ::
          {:ok, t()} | {:error, {:duplicate_player_id, String.t()}}
  def new(%Player{} = first, %Player{} = second, %Player{} = third) do
    case [first.id, second.id, third.id]
         |> Enum.frequencies()
         |> Enum.find(fn {_id, count} -> count > 1 end) do
      {id, _count} -> {:error, {:duplicate_player_id, id}}
      nil -> {:ok, %__MODULE__{first: first, second: second, third: third}}
    end
  end

  @spec all(t()) :: [Player.t()]
  def all(%__MODULE__{} = players), do: [players.first, players.second, players.third]

  @spec ids(t()) :: [String.t()]
  def ids(players), do: Enum.map(all(players), & &1.id)

  @spec contains?(t(), String.t()) :: boolean()
  def contains?(players, player_id), do: player_id in ids(players)

  @spec at(t(), seat()) :: Player.t()
  def at(players, :first), do: players.first
  def at(players, :second), do: players.second
  def at(players, :third), do: players.third

  @spec seat_of(t(), String.t()) :: {:ok, seat()} | :error
  def seat_of(players, player_id) do
    cond do
      players.first.id == player_id -> {:ok, :first}
      players.second.id == player_id -> {:ok, :second}
      players.third.id == player_id -> {:ok, :third}
      true -> :error
    end
  end

  @spec next_seat(seat()) :: seat()
  def next_seat(:first), do: :second
  def next_seat(:second), do: :third
  def next_seat(:third), do: :first

  @spec next_id(t(), String.t()) :: {:ok, String.t()} | :error
  def next_id(players, player_id) do
    with {:ok, seat} <- seat_of(players, player_id) do
      {:ok, at(players, next_seat(seat)).id}
    end
  end
end
