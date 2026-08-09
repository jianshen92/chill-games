defmodule Doudizhu.Domain.Playing do
  @moduledoc false

  alias Doudizhu.Domain.{Card, Combination, Hand}

  @enforce_keys [
    :deal_number,
    :hands,
    :played_cards,
    :landlord,
    :winning_bid,
    :current_player,
    :current_lead,
    :consecutive_passes,
    :bombs_played,
    :rockets_played,
    :plays_by_player
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          deal_number: pos_integer(),
          hands: %{String.t() => Hand.t()},
          played_cards: MapSet.t(Card.t()),
          landlord: String.t(),
          winning_bid: 1 | 2 | 3,
          current_player: String.t(),
          current_lead: nil | %{player: String.t(), combination: Combination.t()},
          consecutive_passes: 0..1,
          bombs_played: non_neg_integer(),
          rockets_played: non_neg_integer(),
          plays_by_player: %{String.t() => non_neg_integer()}
        }
end
