defmodule Doudizhu.Projection.Snapshot do
  @moduledoc "Audience-specific protocol snapshots."

  alias Doudizhu.Domain.{Game, Hand, Players}
  alias Doudizhu.Projection.Value

  @spec build(Game.t(), :spectator | {:player, String.t()}) ::
          {:ok, map()} | {:error, :not_authorized}
  def build(%Game{} = game, :spectator), do: {:ok, envelope(game, nil)}

  def build(%Game{} = game, {:player, player_id}) do
    if Players.contains?(game.players, player_id) do
      {:ok, envelope(game, player_id)}
    else
      {:error, :not_authorized}
    end
  end

  defp envelope(game, player_id) do
    %{
      "protocol_version" => 1,
      "kind" => "snapshot",
      "game_id" => game.id,
      "sequence" => game.version,
      "you" => player_view(game, player_id),
      "game" => game_view(game),
      "players" => Enum.map(Players.all(game.players), &Value.player/1)
    }
  end

  defp player_view(_game, nil), do: nil

  defp player_view(game, player_id) do
    hand =
      case Game.hand(game, player_id) do
        {:ok, hand} -> hand |> Hand.cards() |> Value.cards()
        :error -> []
      end

    role =
      case Game.role(game, player_id) do
        {:ok, role} -> Atom.to_string(role)
        :error -> nil
      end

    %{"player_id" => player_id, "role" => role, "hand" => hand}
  end

  defp game_view(game) do
    game
    |> Game.status()
    |> encode_status()
  end

  defp encode_status(%{phase: :awaiting_deal, deal_number: deal_number}) do
    %{"phase" => "awaiting_deal", "deal_number" => deal_number}
  end

  defp encode_status(%{phase: :bidding} = status) do
    %{
      "phase" => "bidding",
      "deal_number" => status.deal_number,
      "current_bidder" => status.current_bidder,
      "highest_bid" => encode_highest_bid(status.highest_bid),
      "consecutive_passes" => status.consecutive_passes,
      "hand_counts" => status.hand_counts
    }
  end

  defp encode_status(%{phase: :playing} = status) do
    %{
      "phase" => "playing",
      "deal_number" => status.deal_number,
      "landlord" => status.landlord,
      "winning_bid" => status.winning_bid,
      "current_player" => status.current_player,
      "current_lead" => encode_lead(status.current_lead),
      "consecutive_passes" => status.consecutive_passes,
      "hand_counts" => status.hand_counts,
      "bombs_played" => status.bombs_played,
      "rockets_played" => status.rockets_played
    }
  end

  defp encode_status(%{phase: :finished} = status) do
    %{
      "phase" => "finished",
      "deal_number" => status.deal_number,
      "landlord" => status.landlord,
      "hand_counts" => status.hand_counts,
      "settlement" => Value.settlement(status.settlement)
    }
  end

  defp encode_highest_bid(nil), do: nil

  defp encode_highest_bid(highest),
    do: %{"player_id" => highest.bidder, "bid" => highest.bid}

  defp encode_lead(nil), do: nil

  defp encode_lead(lead),
    do: %{"player_id" => lead.player, "combination" => Value.combination(lead.combination)}
end
