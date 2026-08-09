defmodule Doudizhu.Domain.Finished do
  @moduledoc false

  alias Doudizhu.Domain.{Card, Hand, Settlement}

  @enforce_keys [:deal_number, :hands, :played_cards, :landlord, :settlement]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          deal_number: pos_integer(),
          hands: %{String.t() => Hand.t()},
          played_cards: MapSet.t(Card.t()),
          landlord: String.t(),
          settlement: Settlement.t()
        }
end
