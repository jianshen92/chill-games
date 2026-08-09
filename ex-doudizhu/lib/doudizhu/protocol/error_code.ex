defmodule Doudizhu.Protocol.ErrorCode do
  @moduledoc "Maps internal errors to stable public protocol codes without leaking private state."

  alias Doudizhu.Domain.Card

  @spec from_domain(term()) :: map()
  def from_domain({:command_not_allowed, command, phase}) do
    %{
      "code" => "command_not_allowed",
      "command" => Atom.to_string(command),
      "phase" => Atom.to_string(phase)
    }
  end

  def from_domain({:unknown_player, _player}), do: %{"code" => "unknown_player"}

  def from_domain({:not_players_turn, expected, _actual}),
    do: %{"code" => "not_players_turn", "expected_player" => expected}

  def from_domain({:bid_must_exceed, current}),
    do: %{"code" => "bid_must_exceed", "current_bid" => current}

  def from_domain({:invalid_combination, reason}),
    do: %{"code" => "invalid_combination", "reason" => combination_reason(reason)}

  def from_domain({:duplicate_cards_selected, cards}),
    do: %{"code" => "duplicate_cards_selected", "cards" => Enum.map(cards, &Card.to_id/1)}

  def from_domain({:cards_not_held, cards}),
    do: %{"code" => "cards_not_held", "cards" => Enum.map(cards, &Card.to_id/1)}

  def from_domain(:play_does_not_beat_current_lead), do: %{"code" => "does_not_beat_current_lead"}
  def from_domain(:cannot_pass_when_leading), do: %{"code" => "cannot_pass_when_leading"}

  def from_domain({:stale_game_version, current}),
    do: %{"code" => "stale_game_version", "current_version" => current}

  def from_domain(:controller_lease_invalid), do: %{"code" => "controller_lease_invalid"}
  def from_domain(:game_not_found), do: %{"code" => "game_not_found"}
  def from_domain(:not_authorized), do: %{"code" => "not_authorized"}
  def from_domain(:command_id_reused), do: %{"code" => "command_id_reused"}
  def from_domain(_error), do: %{"code" => "internal_error"}

  defp combination_reason(:empty_selection), do: "empty_selection"
  defp combination_reason(:pattern_not_recognized), do: "pattern_not_recognized"
  defp combination_reason({:duplicate_physical_cards, _cards}), do: "duplicate_physical_cards"
  defp combination_reason(_reason), do: "invalid_combination"
end
