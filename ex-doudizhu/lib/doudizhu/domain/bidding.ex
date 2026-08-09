defmodule Doudizhu.Domain.Bidding do
  @moduledoc false

  alias Doudizhu.Domain.{Card, Hand}

  @enforce_keys [
    :deal_number,
    :hands,
    :bottom_cards,
    :current_bidder,
    :highest_bid,
    :consecutive_passes
  ]
  defstruct [
    :deal_number,
    :hands,
    :bottom_cards,
    :current_bidder,
    :highest_bid,
    :consecutive_passes
  ]

  @type bid :: 1 | 2 | 3
  @type t :: %__MODULE__{
          deal_number: pos_integer(),
          hands: %{String.t() => Hand.t()},
          bottom_cards: [Card.t()],
          current_bidder: String.t(),
          highest_bid: nil | %{bidder: String.t(), bid: bid()},
          consecutive_passes: 0..2
        }
end
