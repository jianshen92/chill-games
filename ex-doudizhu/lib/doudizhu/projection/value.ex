defmodule Doudizhu.Projection.Value do
  @moduledoc false

  alias Doudizhu.Domain.{Card, Combination, Player, Settlement}

  @spec card(Card.t()) :: String.t()
  def card(card), do: Card.to_id(card)

  @spec cards([Card.t()]) :: [String.t()]
  def cards(cards), do: Enum.map(Card.sort(cards), &card/1)

  @spec player(Player.t()) :: map()
  def player(%Player{} = player), do: %{"player_id" => player.id, "name" => player.name}

  @spec combination(Combination.t()) :: map()
  def combination(%Combination{} = combination) do
    kind_fields =
      case combination.kind do
        {:straight, count} ->
          %{"type" => "straight", "card_count" => count}

        {:consecutive_pairs, count} ->
          %{"type" => "consecutive_pairs", "pair_count" => count}

        {:airplane, count} ->
          %{"type" => "airplane", "triple_count" => count}

        {:airplane_with_singles, count} ->
          %{"type" => "airplane_with_singles", "triple_count" => count}

        {:airplane_with_pairs, count} ->
          %{"type" => "airplane_with_pairs", "triple_count" => count}

        kind ->
          %{"type" => Atom.to_string(kind)}
      end

    Map.merge(kind_fields, %{
      "cards" => cards(combination.cards),
      "main_rank" => rank(combination.main_rank)
    })
  end

  @spec settlement(Settlement.t()) :: map()
  def settlement(%Settlement{} = settlement) do
    %{
      "winning_side" => Atom.to_string(settlement.winning_side),
      "winning_player" => settlement.winning_player,
      "per_farmer_stake" => settlement.per_farmer_stake,
      "bomb_count" => settlement.bomb_count,
      "rocket_count" => settlement.rocket_count,
      "spring" => Atom.to_string(settlement.spring),
      "deltas" => settlement.deltas
    }
  end

  @spec rank(Card.rank()) :: String.t()
  def rank(:small_joker), do: "small_joker"
  def rank(:big_joker), do: "big_joker"

  def rank(rank) do
    :clubs |> Card.standard(rank) |> card() |> String.trim_leading("C")
  end
end
