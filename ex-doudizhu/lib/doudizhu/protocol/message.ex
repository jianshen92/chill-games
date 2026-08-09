defmodule Doudizhu.Protocol.Message do
  @moduledoc "Constructors for protocol-v1 command result messages."

  alias Doudizhu.Protocol.ErrorCode

  @spec accepted(String.t(), String.t(), non_neg_integer()) :: map()
  def accepted(game_id, command_id, version) do
    %{
      "protocol_version" => 1,
      "kind" => "command_result",
      "game_id" => game_id,
      "command_id" => command_id,
      "status" => "accepted",
      "game_version" => version
    }
  end

  @spec protocol_error(map()) :: map()
  def protocol_error(error) do
    error = Map.new(error, fn {key, value} -> {to_string(key), value} end)

    %{
      "protocol_version" => 1,
      "kind" => "protocol_error",
      "error" => error
    }
  end

  @spec rejected(String.t(), String.t(), non_neg_integer(), term()) :: map()
  def rejected(game_id, command_id, version, reason) do
    %{
      "protocol_version" => 1,
      "kind" => "command_result",
      "game_id" => game_id,
      "command_id" => command_id,
      "status" => "rejected",
      "game_version" => version,
      "error" => ErrorCode.from_domain(reason)
    }
  end
end
