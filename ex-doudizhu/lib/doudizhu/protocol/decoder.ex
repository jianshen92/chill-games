defmodule Doudizhu.Protocol.Decoder do
  @moduledoc "Strict, atom-safe decoder for untrusted protocol-v1 commands."

  alias Doudizhu.Domain.Card
  alias Doudizhu.Protocol.CommandEnvelope

  @type error :: %{
          optional(:field) => String.t(),
          optional(:details) => term(),
          required(:code) => String.t()
        }

  @spec decode_command(binary() | map()) :: {:ok, CommandEnvelope.t()} | {:error, error()}
  def decode_command(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, payload} -> decode_command(payload)
      {:error, _} -> error("malformed_json")
    end
  end

  def decode_command(%{
        "protocol_version" => 1,
        "kind" => "command",
        "game_id" => game_id,
        "command_id" => command_id,
        "expected_version" => expected_version,
        "action" => action
      })
      when is_binary(game_id) and game_id != "" and is_binary(command_id) and command_id != "" and
             is_integer(expected_version) and expected_version >= 0 do
    with {:ok, decoded_action} <- decode_action(action) do
      {:ok,
       %CommandEnvelope{
         protocol_version: 1,
         game_id: game_id,
         command_id: command_id,
         expected_version: expected_version,
         action: decoded_action
       }}
    end
  end

  def decode_command(%{"protocol_version" => version}) when version != 1,
    do: error("unsupported_protocol_version", "protocol_version")

  def decode_command(payload) when is_map(payload), do: error("invalid_command_envelope")
  def decode_command(_payload), do: error("invalid_command_envelope")

  defp decode_action(%{"type" => "place_bid", "bid" => bid}) when bid in 1..3,
    do: {:ok, {:place_bid, bid}}

  defp decode_action(%{"type" => "place_bid"}), do: error("invalid_bid", "action.bid")
  defp decode_action(%{"type" => "auction_pass"}), do: {:ok, :auction_pass}

  defp decode_action(%{"type" => "play_cards", "cards" => card_ids}) when is_list(card_ids) do
    decode_cards(card_ids)
  end

  defp decode_action(%{"type" => "play_cards"}), do: error("invalid_cards", "action.cards")
  defp decode_action(%{"type" => "play_pass"}), do: {:ok, :play_pass}
  defp decode_action(%{"type" => _type}), do: error("unknown_action_type", "action.type")
  defp decode_action(_action), do: error("invalid_action", "action")

  defp decode_cards(card_ids) do
    card_ids
    |> Enum.reduce_while({:ok, []}, fn
      card_id, {:ok, cards} when is_binary(card_id) ->
        case Card.from_id(card_id) do
          {:ok, card} -> {:cont, {:ok, [card | cards]}}
          {:error, _} -> {:halt, error("invalid_card_id", "action.cards", card_id)}
        end

      value, _acc ->
        {:halt, error("invalid_card_id", "action.cards", value)}
    end)
    |> case do
      {:ok, cards} -> {:ok, {:play_cards, Enum.reverse(cards)}}
      {:error, _} = error -> error
    end
  end

  defp error(code), do: {:error, %{code: code}}
  defp error(code, field), do: {:error, %{code: code, field: field}}
  defp error(code, field, details), do: {:error, %{code: code, field: field, details: details}}
end
