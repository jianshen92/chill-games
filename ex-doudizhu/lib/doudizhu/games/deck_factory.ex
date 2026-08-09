defmodule Doudizhu.Games.DeckFactory do
  @moduledoc "Trusted application-shell source of cryptographically shuffled deck orders."

  alias Doudizhu.Domain.{Card, DeckOrder}

  @spec random() :: DeckOrder.t()
  def random do
    cards =
      Card.standard_deck()
      |> Enum.map(&{:crypto.strong_rand_bytes(24), &1})
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    {:ok, deck} = DeckOrder.new(cards)
    deck
  end
end
