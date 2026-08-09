defmodule Doudizhu.Domain.Settlement do
  @moduledoc "Final zero-sum score changes for all three players."

  @enforce_keys [
    :winning_side,
    :winning_player,
    :per_farmer_stake,
    :bomb_count,
    :rocket_count,
    :spring,
    :deltas
  ]
  defstruct @enforce_keys

  @type winning_side :: :landlord | :farmers
  @type spring :: :none | :landlord_spring | :farmer_spring
  @type t :: %__MODULE__{
          winning_side: winning_side(),
          winning_player: String.t(),
          per_farmer_stake: pos_integer(),
          bomb_count: non_neg_integer(),
          rocket_count: non_neg_integer(),
          spring: spring(),
          deltas: %{String.t() => integer()}
        }
end
