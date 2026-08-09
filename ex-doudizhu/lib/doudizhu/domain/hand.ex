defmodule Doudizhu.Domain.Hand do
  @moduledoc "An immutable set of physical cards."

  alias Doudizhu.Domain.Card

  @enforce_keys [:cards]
  defstruct [:cards]

  @opaque t :: %__MODULE__{cards: MapSet.t(Card.t())}
  @type error :: {:duplicate_cards, [Card.t()]} | {:cards_not_held, [Card.t()]}

  @spec new([Card.t()]) :: {:ok, t()} | {:error, error()}
  def new(cards) when is_list(cards) do
    case duplicates(cards) do
      [] -> {:ok, %__MODULE__{cards: MapSet.new(cards)}}
      duplicates -> {:error, {:duplicate_cards, Card.sort(duplicates)}}
    end
  end

  @spec empty() :: t()
  def empty, do: %__MODULE__{cards: MapSet.new()}

  @spec cards(t()) :: [Card.t()]
  def cards(%__MODULE__{cards: cards}), do: cards |> MapSet.to_list() |> Card.sort()

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{cards: cards}), do: MapSet.size(cards)

  @spec empty?(t()) :: boolean()
  def empty?(hand), do: count(hand) == 0

  @spec contains?(t(), Card.t()) :: boolean()
  def contains?(%__MODULE__{cards: cards}, card), do: MapSet.member?(cards, card)

  @spec add(t(), [Card.t()]) :: {:ok, t()} | {:error, error()}
  def add(%__MODULE__{cards: cards}, added_cards) do
    duplicate_input = duplicates(added_cards)
    already_held = Enum.filter(added_cards, &MapSet.member?(cards, &1))
    duplicates = Enum.uniq(duplicate_input ++ already_held)

    if duplicates == [] do
      {:ok, %__MODULE__{cards: MapSet.union(cards, MapSet.new(added_cards))}}
    else
      {:error, {:duplicate_cards, Card.sort(duplicates)}}
    end
  end

  @spec remove(t(), [Card.t()]) :: {:ok, t()} | {:error, error()}
  def remove(%__MODULE__{cards: cards}, selected_cards) do
    case duplicates(selected_cards) do
      [_ | _] = duplicates ->
        {:error, {:duplicate_cards, Card.sort(duplicates)}}

      [] ->
        selected = MapSet.new(selected_cards)
        missing = MapSet.difference(selected, cards) |> MapSet.to_list()

        if missing == [] do
          {:ok, %__MODULE__{cards: MapSet.difference(cards, selected)}}
        else
          {:error, {:cards_not_held, Card.sort(missing)}}
        end
    end
  end

  defp duplicates(cards) do
    cards
    |> Enum.frequencies()
    |> Enum.filter(fn {_card, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end
end
