defmodule Doudizhu.Domain.RuleSet do
  @moduledoc "Explicit variant-sensitive rules for a three-player game."

  @enforce_keys [:attachments, :scoring, :reveal_bottom_cards]
  defstruct [:attachments, :scoring, :reveal_bottom_cards]

  @type wing_policy :: :distinct_ranks | :pairs_allowed | :any_cards
  @type attachments :: %{
          airplane_single_wings: wing_policy(),
          four_single_wings_must_have_distinct_ranks: boolean(),
          both_jokers_may_be_attachments: boolean()
        }
  @type scoring :: %{
          bomb_multiplier: pos_integer(),
          rocket_multiplier: pos_integer(),
          spring_multiplier: pos_integer()
        }
  @type t :: %__MODULE__{
          attachments: attachments(),
          scoring: scoring(),
          reveal_bottom_cards: boolean()
        }

  @spec standard_three_player() :: t()
  def standard_three_player do
    %__MODULE__{
      attachments: %{
        airplane_single_wings: :pairs_allowed,
        four_single_wings_must_have_distinct_ranks: true,
        both_jokers_may_be_attachments: false
      },
      scoring: %{bomb_multiplier: 2, rocket_multiplier: 2, spring_multiplier: 2},
      reveal_bottom_cards: true
    }
  end

  @spec validate(t()) :: {:ok, t()} | {:error, {:invalid_scoring_multiplier, atom(), integer()}}
  def validate(%__MODULE__{} = rules) do
    Enum.find_value(
      [:bomb_multiplier, :rocket_multiplier, :spring_multiplier],
      {:ok, rules},
      fn name ->
        value = Map.fetch!(rules.scoring, name)

        if is_integer(value) and value >= 1,
          do: false,
          else: {:error, {:invalid_scoring_multiplier, name, value}}
      end
    )
  end
end
