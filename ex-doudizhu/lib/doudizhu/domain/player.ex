defmodule Doudizhu.Domain.Player do
  @moduledoc "A player with stable identity and a validated display name."

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: String.t(), name: String.t()}
  @type error :: :id_required | :name_required | {:name_too_long, pos_integer()}

  @spec new(String.t(), String.t()) :: {:ok, t()} | {:error, error()}
  def new(id, name) when is_binary(id) and is_binary(name) do
    normalized = String.trim(name)

    cond do
      id == "" -> {:error, :id_required}
      normalized == "" -> {:error, :name_required}
      String.length(normalized) > 30 -> {:error, {:name_too_long, 30}}
      true -> {:ok, %__MODULE__{id: id, name: normalized}}
    end
  end

  def new(id, _name) when not is_binary(id), do: {:error, :id_required}
  def new(_id, _name), do: {:error, :name_required}
end
