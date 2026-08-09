defmodule Doudizhu.DomainHelpers do
  alias Doudizhu.Domain.{Card, Combination, DeckOrder, Game, Hand, Player, Players, RuleSet}

  def card(suit, rank), do: Card.standard(suit, rank)
  def small_joker, do: Card.joker(:small)
  def big_joker, do: Card.joker(:big)

  def cards_of(rank, count) do
    Card.suits() |> Enum.take(count) |> Enum.map(&card(&1, rank))
  end

  def one(rank), do: cards_of(rank, 1)
  def pair(rank), do: cards_of(rank, 2)
  def triple(rank), do: cards_of(rank, 3)
  def quad(rank), do: cards_of(rank, 4)

  def classify!(cards) do
    {:ok, combination} = Combination.classify(RuleSet.standard_three_player(), cards)
    combination
  end

  def players do
    {:ok, first} = Player.new("00000000-0000-0000-0000-000000000001", "Alice")
    {:ok, second} = Player.new("00000000-0000-0000-0000-000000000002", "Bob")
    {:ok, third} = Player.new("00000000-0000-0000-0000-000000000003", "Chen")
    {:ok, players} = Players.new(first, second, third)
    players
  end

  def first_id, do: "00000000-0000-0000-0000-000000000001"
  def second_id, do: "00000000-0000-0000-0000-000000000002"
  def third_id, do: "00000000-0000-0000-0000-000000000003"

  def new_game(id \\ "game-1") do
    {:ok, game} = Game.new(id, players(), RuleSet.standard_three_player())
    game
  end

  def standard_deck do
    {:ok, deck} = DeckOrder.new(Card.standard_deck())
    deck
  end

  def execute!(game, command) do
    {:ok, next, events} = Game.execute(game, command)
    {next, events}
  end

  def deal(game, deck \\ standard_deck()) do
    {game, _events} = execute!(game, {:deal, deck, first_id()})
    game
  end

  def bid_three(game, player_id \\ first_id()) do
    {game, _events} = execute!(game, {:bid, player_id, 3})
    game
  end

  def hand_cards(game, player_id) do
    {:ok, hand} = Game.hand(game, player_id)
    Hand.cards(hand)
  end

  def deck_with_first_landlord_hand(landlord_cards) do
    true = length(landlord_cards) == 20
    true = MapSet.size(MapSet.new(landlord_cards)) == 20

    dealt_to_first = Enum.take(landlord_cards, 17)
    bottom = Enum.drop(landlord_cards, 17)
    others = without(Card.standard_deck(), landlord_cards)
    dealt_to_second = Enum.take(others, 17)
    dealt_to_third = Enum.drop(others, 17)

    first_51 =
      Enum.flat_map(0..16, fn index ->
        [
          Enum.at(dealt_to_first, index),
          Enum.at(dealt_to_second, index),
          Enum.at(dealt_to_third, index)
        ]
      end)

    {:ok, deck} = DeckOrder.new(first_51 ++ bottom)
    deck
  end

  def deck_with_hands(first_hand, second_hand, third_hand, bottom) do
    true = Enum.all?([first_hand, second_hand, third_hand], &(length(&1) == 17))
    true = length(bottom) == 3
    all = first_hand ++ second_hand ++ third_hand ++ bottom
    true = MapSet.new(Card.standard_deck()) == MapSet.new(all)

    first_51 =
      Enum.flat_map(0..16, fn index ->
        [Enum.at(first_hand, index), Enum.at(second_hand, index), Enum.at(third_hand, index)]
      end)

    {:ok, deck} = DeckOrder.new(first_51 ++ bottom)
    deck
  end

  defp without(all, selected), do: Enum.reject(all, &MapSet.member?(MapSet.new(selected), &1))
end
