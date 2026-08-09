defmodule Doudizhu.Protocol.Encoder do
  @moduledoc "JSON encoder for already-projected protocol messages."

  @spec encode(map()) :: {:ok, binary()} | {:error, Jason.EncodeError.t()}
  def encode(message) when is_map(message), do: Jason.encode(message)

  @spec encode!(map()) :: binary()
  def encode!(message) when is_map(message), do: Jason.encode!(message)

  @spec wire_round_trip(map()) :: map()
  def wire_round_trip(message) do
    message |> encode!() |> Jason.decode!()
  end
end
