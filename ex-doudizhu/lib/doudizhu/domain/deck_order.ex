defmodule Doudizhu.Domain.DeckOrder do
  @moduledoc "A validated caller-supplied ordering of every card in a standard deck."

  alias Doudizhu.Domain.Card

  @enforce_keys [:cards]
  defstruct [:cards]

  @opaque t :: %__MODULE__{cards: [Card.t()]}
  @type error ::
          {:wrong_card_count, 54, non_neg_integer()}
          | {:duplicate_cards, [Card.t()]}
          | {:missing_cards, [Card.t()]}

  @spec new([Card.t()]) :: {:ok, t()} | {:error, error()}
  def new(cards) when is_list(cards) do
    duplicates = duplicates(cards)

    cond do
      length(cards) != 54 -> {:error, {:wrong_card_count, 54, length(cards)}}
      duplicates != [] -> {:error, {:duplicate_cards, Card.sort(duplicates)}}
      true -> validate_complete(cards)
    end
  end

  @spec cards(t()) :: [Card.t()]
  def cards(%__MODULE__{cards: cards}), do: cards

  defp validate_complete(cards) do
    missing =
      MapSet.difference(MapSet.new(Card.standard_deck()), MapSet.new(cards)) |> MapSet.to_list()

    if missing == [] do
      {:ok, %__MODULE__{cards: cards}}
    else
      {:error, {:missing_cards, Card.sort(missing)}}
    end
  end

  defp duplicates(cards) do
    cards
    |> Enum.frequencies()
    |> Enum.filter(fn {_card, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end
end
