defmodule Doudizhu.Domain.CombinationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Doudizhu.Domain.{Combination, RuleSet}
  import Doudizhu.DomainHelpers

  @rules RuleSet.standard_three_player()

  test "all basic combination families classify" do
    cases = [
      {[big_joker()], :single},
      {pair(:three), :pair},
      {triple(:four), :triple},
      {triple(:five) ++ one(:king), :triple_with_single},
      {triple(:six) ++ pair(:ace), :triple_with_pair},
      {Enum.flat_map([:three, :four, :five, :six, :seven], &one/1), {:straight, 5}},
      {Enum.flat_map([:eight, :nine, :ten], &pair/1), {:consecutive_pairs, 3}},
      {triple(:four) ++ triple(:five), {:airplane, 2}},
      {triple(:six) ++ triple(:seven) ++ one(:nine) ++ one(:ten), {:airplane_with_singles, 2}},
      {triple(:eight) ++ triple(:nine) ++ pair(:jack) ++ pair(:queen), {:airplane_with_pairs, 2}},
      {quad(:three), :bomb},
      {[small_joker(), big_joker()], :rocket},
      {quad(:six) ++ one(:eight) ++ one(:nine), :four_with_singles},
      {quad(:jack) ++ pair(:nine) ++ pair(:queen), :four_with_pairs}
    ]

    for {cards, expected_kind} <- cases do
      assert classify!(cards).kind == expected_kind
    end
  end

  test "sequences exclude two and jokers" do
    with_two = Enum.flat_map([:ten, :jack, :queen, :king, :ace, :two], &one/1)

    assert Combination.classify(@rules, with_two) == {:error, :pattern_not_recognized}

    with_joker = [
      card(:clubs, :jack),
      card(:clubs, :queen),
      card(:clubs, :king),
      card(:clubs, :ace),
      small_joker()
    ]

    assert Combination.classify(@rules, with_joker) == {:error, :pattern_not_recognized}
  end

  test "airplane single wings may form a pair under standard rules" do
    cards = triple(:three) ++ triple(:four) ++ pair(:nine)
    assert classify!(cards).kind == {:airplane_with_singles, 2}
  end

  test "airplane bodies cannot include two" do
    cards = triple(:ace) ++ triple(:two)
    assert Combination.classify(@rules, cards) == {:error, :pattern_not_recognized}
  end

  test "airplane wings cannot use a body rank" do
    cards = quad(:three) ++ triple(:four) ++ one(:nine)
    assert Combination.classify(@rules, cards) == {:error, :pattern_not_recognized}
  end

  test "both jokers cannot be attachments under standard rules" do
    airplane = triple(:three) ++ triple(:four) ++ [small_joker(), big_joker()]
    quadplex = quad(:five) ++ [small_joker(), big_joker()]

    assert Combination.classify(@rules, airplane) == {:error, :pattern_not_recognized}
    assert Combination.classify(@rules, quadplex) == {:error, :pattern_not_recognized}
  end

  test "quadplex singles must have distinct ranks under standard rules" do
    assert Combination.classify(@rules, quad(:five) ++ pair(:nine)) ==
             {:error, :pattern_not_recognized}
  end

  test "duplicate physical cards are rejected" do
    duplicate = card(:clubs, :three)

    assert Combination.classify(@rules, [duplicate, duplicate]) ==
             {:error, {:duplicate_physical_cards, [duplicate]}}
  end

  test "higher matching shape beats lower matching shape" do
    lower = Enum.flat_map([:three, :four, :five, :six, :seven], &one/1) |> classify!()
    higher = Enum.flat_map([:four, :five, :six, :seven, :eight], &one/1) |> classify!()

    assert Combination.beats?(lower, higher)
    refute Combination.beats?(higher, lower)
  end

  test "different sequence lengths do not beat one another" do
    five = Enum.flat_map([:three, :four, :five, :six, :seven], &one/1) |> classify!()
    six = Enum.flat_map([:four, :five, :six, :seven, :eight, :nine], &one/1) |> classify!()

    refute Combination.beats?(five, six)
    refute Combination.beats?(six, five)
  end

  test "bomb and rocket precedence is explicit" do
    high_straight = Enum.flat_map([:ten, :jack, :queen, :king, :ace], &one/1) |> classify!()
    low_bomb = quad(:three) |> classify!()
    high_bomb = quad(:ace) |> classify!()
    rocket = [small_joker(), big_joker()] |> classify!()

    assert Combination.beats?(high_straight, low_bomb)
    assert Combination.beats?(low_bomb, high_bomb)
    assert Combination.beats?(high_bomb, rocket)
    refute Combination.beats?(rocket, high_bomb)
  end

  test "quadplex is not a bomb" do
    quadplex = (quad(:ace) ++ one(:three) ++ one(:four)) |> classify!()
    bomb = quad(:three) |> classify!()

    assert Combination.beats?(quadplex, bomb)
    refute Combination.beats?(bomb, quadplex)
  end

  property "classification is invariant under card permutation" do
    check all(
            cards <-
              StreamData.member_of([
                pair(:three),
                triple(:four) ++ one(:king),
                Enum.flat_map([:three, :four, :five, :six, :seven], &one/1),
                quad(:ace),
                [small_joker(), big_joker()]
              ]),
            seed <- StreamData.integer()
          ) do
      expected = classify!(cards)
      shuffled = Enum.sort_by(cards, &:erlang.phash2({&1, seed}))
      actual = classify!(shuffled)
      assert actual.kind == expected.kind
      assert actual.main_rank == expected.main_rank
      assert actual.cards == expected.cards
    end
  end
end
