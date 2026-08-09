defmodule Doudizhu.Domain.Combination do
  @moduledoc "Classification and comparison of legal 斗地主 card combinations."

  alias Doudizhu.Domain.{Card, RuleSet}

  @enforce_keys [:cards, :kind, :main_rank]
  defstruct [:cards, :kind, :main_rank]

  @type kind ::
          :single
          | :pair
          | :triple
          | :triple_with_single
          | :triple_with_pair
          | {:straight, pos_integer()}
          | {:consecutive_pairs, pos_integer()}
          | {:airplane, pos_integer()}
          | {:airplane_with_singles, pos_integer()}
          | {:airplane_with_pairs, pos_integer()}
          | :four_with_singles
          | :four_with_pairs
          | :bomb
          | :rocket
  @type t :: %__MODULE__{cards: [Card.t()], kind: kind(), main_rank: Card.rank()}
  @type error ::
          :empty_selection | {:duplicate_physical_cards, [Card.t()]} | :pattern_not_recognized

  @spec classify(RuleSet.t(), [Card.t()]) :: {:ok, t()} | {:error, error()}
  def classify(%RuleSet{} = rules, cards) when is_list(cards) do
    cond do
      cards == [] ->
        {:error, :empty_selection}

      duplicates(cards) != [] ->
        {:error, {:duplicate_physical_cards, Card.sort(duplicates(cards))}}

      true ->
        case classify_recognized(rules, cards) do
          {kind, rank} -> {:ok, %__MODULE__{cards: Card.sort(cards), kind: kind, main_rank: rank}}
          nil -> {:error, :pattern_not_recognized}
        end
    end
  end

  @spec beats?(t(), t()) :: boolean()
  def beats?(%__MODULE__{} = current, %__MODULE__{} = challenger) do
    case {current.kind, challenger.kind} do
      {:rocket, _} -> false
      {_, :rocket} -> true
      {:bomb, :bomb} -> higher?(challenger, current)
      {:bomb, _} -> false
      {_, :bomb} -> true
      {kind, kind} -> higher?(challenger, current)
      _ -> false
    end
  end

  @spec bomb_or_rocket?(t()) :: boolean()
  def bomb_or_rocket?(%__MODULE__{kind: kind}), do: kind in [:bomb, :rocket]

  @spec card_count(t()) :: non_neg_integer()
  def card_count(%__MODULE__{cards: cards}), do: length(cards)

  defp classify_recognized(rules, cards) do
    counts = rank_counts(cards)
    count = length(cards)

    [
      exact_single(counts, count),
      exact_pair_or_rocket(counts, count),
      exact_triple(counts, count),
      exact_four(counts, count),
      triple_with_pair(counts, count),
      uniform_sequence(counts, 1, 5, &{:straight, &1}),
      uniform_sequence(counts, 2, 3, &{:consecutive_pairs, &1}),
      uniform_sequence(counts, 3, 2, &{:airplane, &1}),
      airplane_with_singles(rules, cards, counts),
      airplane_with_pairs(cards, counts),
      four_with_singles(rules, counts, count),
      four_with_pairs(counts, count)
    ]
    |> Enum.find(& &1)
  end

  defp exact_single([{rank, 1}], 1), do: {:single, rank}
  defp exact_single(_, _), do: nil

  defp exact_pair_or_rocket(counts, 2) do
    case counts do
      [{:small_joker, 1}, {:big_joker, 1}] -> {:rocket, :big_joker}
      [{rank, 2}] -> if Card.standard_rank?(rank), do: {:pair, rank}
      _ -> nil
    end
  end

  defp exact_pair_or_rocket(_, _), do: nil

  defp exact_triple([{rank, 3}], 3) do
    if Card.standard_rank?(rank), do: {:triple, rank}
  end

  defp exact_triple(_, _), do: nil

  defp exact_four(counts, 4) do
    case counts do
      [{rank, 4}] -> if Card.standard_rank?(rank), do: {:bomb, rank}
      _ -> triple_with_single(counts)
    end
  end

  defp exact_four(_, _), do: nil

  defp triple_with_single(counts) do
    case Enum.find(counts, fn {rank, count} -> Card.standard_rank?(rank) and count == 3 end) do
      {rank, 3} when length(counts) == 2 ->
        if Enum.any?(counts, fn {_other, count} -> count == 1 end),
          do: {:triple_with_single, rank}

      _ ->
        nil
    end
  end

  defp triple_with_pair(counts, 5) do
    triple = Enum.find(counts, fn {rank, count} -> Card.standard_rank?(rank) and count == 3 end)
    pair = Enum.find(counts, fn {rank, count} -> Card.standard_rank?(rank) and count == 2 end)

    case {triple, pair, length(counts)} do
      {{rank, 3}, {_pair_rank, 2}, 2} -> {:triple_with_pair, rank}
      _ -> nil
    end
  end

  defp triple_with_pair(_, _), do: nil

  defp uniform_sequence(counts, multiplicity, minimum_ranks, kind_factory) do
    ranks =
      Enum.flat_map(counts, fn {rank, count} ->
        if Card.standard_rank?(rank) and count == multiplicity, do: [rank], else: []
      end)

    if length(ranks) == length(counts) and length(ranks) >= minimum_ranks and
         Enum.all?(ranks, &Card.sequence_rank?/1) and consecutive?(ranks) do
      high_rank = Enum.max_by(ranks, &Card.strength/1)
      {kind_factory.(length(ranks)), high_rank}
    end
  end

  defp airplane_with_singles(rules, cards, counts) do
    if rem(length(cards), 4) == 0 do
      triple_count = div(length(cards), 4)

      if triple_count >= 2 do
        airplane_bodies(triple_count, counts)
        |> Enum.find_value(fn body ->
          remaining = remove_airplane_body(body, counts)

          multiplicity_allowed =
            case rules.attachments.airplane_single_wings do
              :distinct_ranks -> Enum.all?(remaining, fn {_rank, count} -> count == 1 end)
              :pairs_allowed -> Enum.all?(remaining, fn {_rank, count} -> count <= 2 end)
              :any_cards -> true
            end

          jokers_allowed =
            rules.attachments.both_jokers_may_be_attachments or
              not contains_both_jokers?(remaining)

          if Enum.sum(Enum.map(remaining, &elem(&1, 1))) == triple_count and
               wings_avoid_body?(body, remaining) and multiplicity_allowed and jokers_allowed do
            {{:airplane_with_singles, triple_count}, Enum.max_by(body, &Card.strength/1)}
          end
        end)
      end
    end
  end

  defp airplane_with_pairs(cards, counts) do
    if rem(length(cards), 5) == 0 do
      triple_count = div(length(cards), 5)

      if triple_count >= 2 do
        airplane_bodies(triple_count, counts)
        |> Enum.find_value(fn body ->
          remaining = remove_airplane_body(body, counts)

          valid_pairs =
            length(remaining) == triple_count and
              Enum.all?(remaining, fn {rank, count} ->
                Card.standard_rank?(rank) and count == 2
              end)

          if wings_avoid_body?(body, remaining) and valid_pairs do
            {{:airplane_with_pairs, triple_count}, Enum.max_by(body, &Card.strength/1)}
          end
        end)
      end
    end
  end

  defp four_with_singles(rules, counts, 6) do
    case Enum.find(counts, fn {rank, count} -> Card.standard_rank?(rank) and count == 4 end) do
      {quad_rank, 4} ->
        remaining = Enum.reject(counts, fn {rank, _count} -> rank == quad_rank end)

        distinct_allowed =
          not rules.attachments.four_single_wings_must_have_distinct_ranks or
            Enum.all?(remaining, fn {_rank, count} -> count == 1 end)

        jokers_allowed =
          rules.attachments.both_jokers_may_be_attachments or not contains_both_jokers?(remaining)

        if Enum.sum(Enum.map(remaining, &elem(&1, 1))) == 2 and distinct_allowed and
             jokers_allowed,
           do: {:four_with_singles, quad_rank}

      nil ->
        nil
    end
  end

  defp four_with_singles(_, _, _), do: nil

  defp four_with_pairs(counts, 8) do
    case Enum.find(counts, fn {rank, count} -> Card.standard_rank?(rank) and count == 4 end) do
      {quad_rank, 4} ->
        remaining = Enum.reject(counts, fn {rank, _count} -> rank == quad_rank end)

        if length(remaining) == 2 and
             Enum.all?(remaining, fn {rank, count} -> Card.standard_rank?(rank) and count == 2 end),
           do: {:four_with_pairs, quad_rank}

      nil ->
        nil
    end
  end

  defp four_with_pairs(_, _), do: nil

  defp rank_counts(cards) do
    cards
    |> Enum.map(& &1.rank)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {rank, _count} -> Card.strength(rank) end)
  end

  defp airplane_bodies(triple_count, counts) do
    counts
    |> Enum.flat_map(fn {rank, count} ->
      if Card.standard_rank?(rank) and Card.sequence_rank?(rank) and count >= 3,
        do: [rank],
        else: []
    end)
    |> Enum.sort_by(&Card.strength/1)
    |> Enum.chunk_every(triple_count, 1, :discard)
    |> Enum.filter(&consecutive?/1)
  end

  defp remove_airplane_body(body, counts) do
    body_set = MapSet.new(body)

    Enum.flat_map(counts, fn {rank, count} ->
      if MapSet.member?(body_set, rank) do
        case count - 3 do
          0 -> []
          remainder -> [{rank, remainder}]
        end
      else
        [{rank, count}]
      end
    end)
  end

  defp wings_avoid_body?(body, remaining) do
    body_set = MapSet.new(body)
    Enum.all?(remaining, fn {rank, _count} -> not MapSet.member?(body_set, rank) end)
  end

  defp contains_both_jokers?(counts) do
    ranks = counts |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    MapSet.member?(ranks, :small_joker) and MapSet.member?(ranks, :big_joker)
  end

  defp consecutive?(ranks) do
    ranks
    |> Enum.map(&Card.strength/1)
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [lower, higher] -> higher == lower + 1 end)
  end

  defp higher?(challenger, current),
    do: Card.strength(challenger.main_rank) > Card.strength(current.main_rank)

  defp duplicates(cards) do
    cards
    |> Enum.frequencies()
    |> Enum.filter(fn {_card, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end
end
