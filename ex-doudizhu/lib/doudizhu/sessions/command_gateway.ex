defmodule Doudizhu.Sessions.CommandGateway do
  @moduledoc "Shared authorization, decoding, versioning, and dispatch path for every transport."

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameServer, GameSupervisor}
  alias Doudizhu.Protocol.{CommandEnvelope, Decoder, Message}
  alias Doudizhu.Sessions.{ActorContext, LeaseManager}

  @spec dispatch(ActorContext.t(), binary() | map()) :: map()
  def dispatch(%ActorContext{} = actor, payload) do
    metadata = %{game_id: actor.game_id, player_id: actor.player_id, transport_role: actor.role}

    :telemetry.span([:doudizhu, :command, :dispatch], metadata, fn ->
      result = do_dispatch(actor, payload)
      {result, Map.put(metadata, :outcome, outcome(result))}
    end)
  end

  defp do_dispatch(actor, payload) do
    with {:ok, envelope} <- Decoder.decode_command(payload),
         :ok <- validate_game(actor, envelope),
         :ok <- LeaseManager.validate(actor),
         {:ok, _pid} <- GameSupervisor.start_game(envelope.game_id) do
      canonical = canonical_payload(envelope)
      hash = hash(canonical)
      GameServer.submit(envelope.game_id, actor, envelope, canonical, hash)
    else
      {:error, %{code: _code} = protocol_error} -> Message.protocol_error(protocol_error)
      {:error, reason} -> Message.protocol_error(%{code: error_code(reason)})
    end
  end

  @spec canonical_payload(CommandEnvelope.t()) :: map()
  def canonical_payload(%CommandEnvelope{} = envelope) do
    %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => envelope.game_id,
      "command_id" => envelope.command_id,
      "expected_version" => envelope.expected_version,
      "action" => encode_action(envelope.action)
    }
  end

  defp validate_game(%ActorContext{game_id: game_id, role: :player}, %CommandEnvelope{
         game_id: game_id
       }),
       do: :ok

  defp validate_game(_actor, _envelope), do: {:error, :not_authorized}

  defp encode_action({:place_bid, bid}), do: %{"type" => "place_bid", "bid" => bid}
  defp encode_action(:auction_pass), do: %{"type" => "auction_pass"}

  defp encode_action({:play_cards, cards}),
    do: %{"type" => "play_cards", "cards" => Enum.map(cards, &Card.to_id/1)}

  defp encode_action(:play_pass), do: %{"type" => "play_pass"}

  defp hash(payload),
    do: :crypto.hash(:sha256, Jason.encode!(payload)) |> Base.encode16(case: :lower)

  defp outcome(%{"status" => status}), do: status
  defp outcome(%{"kind" => "protocol_error"}), do: "protocol_error"
  defp outcome(_result), do: "unknown"

  defp error_code(:not_authorized), do: "not_authorized"
  defp error_code(:controller_lease_invalid), do: "controller_lease_invalid"
  defp error_code(:game_not_found), do: "game_not_found"
  defp error_code(_reason), do: "internal_error"
end
