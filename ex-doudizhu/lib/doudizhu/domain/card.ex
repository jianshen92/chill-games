defmodule Doudizhu.Domain.Card do
  @moduledoc "A physical card in the standard 54-card deck."

  @standard_ranks [
    :three,
    :four,
    :five,
    :six,
    :seven,
    :eight,
    :nine,
    :ten,
    :jack,
    :queen,
    :king,
    :ace,
    :two
  ]
  @suits [:clubs, :diamonds, :hearts, :spades]

  @rank_ids %{
    three: "3",
    four: "4",
    five: "5",
    six: "6",
    seven: "7",
    eight: "8",
    nine: "9",
    ten: "10",
    jack: "J",
    queen: "Q",
    king: "K",
    ace: "A",
    two: "2"
  }
  @id_ranks Map.new(@rank_ids, fn {rank, id} -> {id, rank} end)
  @suit_ids %{clubs: "C", diamonds: "D", hearts: "H", spades: "S"}
  @id_suits Map.new(@suit_ids, fn {suit, id} -> {id, suit} end)

  @enforce_keys [:rank]
  defstruct [:suit, :rank]

  @type suit :: :clubs | :diamonds | :hearts | :spades
  @type standard_rank ::
          :three
          | :four
          | :five
          | :six
          | :seven
          | :eight
          | :nine
          | :ten
          | :jack
          | :queen
          | :king
          | :ace
          | :two
  @type rank :: standard_rank() | :small_joker | :big_joker
  @type t :: %__MODULE__{suit: suit() | nil, rank: rank()}

  @spec standard(suit(), standard_rank()) :: t()
  def standard(suit, rank) when suit in @suits and rank in @standard_ranks,
    do: %__MODULE__{suit: suit, rank: rank}

  @spec joker(:small | :big | :small_joker | :big_joker) :: t()
  def joker(:small), do: %__MODULE__{rank: :small_joker}
  def joker(:big), do: %__MODULE__{rank: :big_joker}
  def joker(:small_joker), do: joker(:small)
  def joker(:big_joker), do: joker(:big)

  @spec standard_ranks() :: [standard_rank()]
  def standard_ranks, do: @standard_ranks

  @spec suits() :: [suit()]
  def suits, do: @suits

  @spec standard_rank?(rank()) :: boolean()
  def standard_rank?(rank), do: rank in @standard_ranks

  @spec sequence_rank?(rank()) :: boolean()
  def sequence_rank?(rank), do: rank in @standard_ranks and rank != :two

  @spec strength(t() | rank()) :: 3..17
  def strength(%__MODULE__{rank: rank}), do: strength(rank)
  def strength(:small_joker), do: 16
  def strength(:big_joker), do: 17

  def strength(rank) when rank in @standard_ranks,
    do: Enum.find_index(@standard_ranks, &(&1 == rank)) + 3

  @spec standard_deck() :: [t()]
  def standard_deck do
    for(suit <- @suits, rank <- @standard_ranks, do: standard(suit, rank)) ++
      [joker(:small), joker(:big)]
  end

  @spec sort([t()]) :: [t()]
  def sort(cards), do: Enum.sort_by(cards, &sort_key/1)

  @spec to_id(t()) :: String.t()
  def to_id(%__MODULE__{suit: nil, rank: :small_joker}), do: "JOKER_SMALL"
  def to_id(%__MODULE__{suit: nil, rank: :big_joker}), do: "JOKER_BIG"

  def to_id(%__MODULE__{suit: suit, rank: rank}),
    do: Map.fetch!(@suit_ids, suit) <> Map.fetch!(@rank_ids, rank)

  @spec from_id(String.t()) :: {:ok, t()} | {:error, :invalid_card_id}
  def from_id("JOKER_SMALL"), do: {:ok, joker(:small)}
  def from_id("JOKER_BIG"), do: {:ok, joker(:big)}

  def from_id(<<suit_id::binary-size(1), rank_id::binary>>) do
    with {:ok, suit} <- Map.fetch(@id_suits, suit_id),
         {:ok, rank} <- Map.fetch(@id_ranks, rank_id) do
      {:ok, standard(suit, rank)}
    else
      :error -> {:error, :invalid_card_id}
    end
  end

  def from_id(_id), do: {:error, :invalid_card_id}

  defp sort_key(%__MODULE__{suit: suit, rank: rank}) do
    suit_index = if suit, do: Enum.find_index(@suits, &(&1 == suit)), else: 4
    {strength(rank), suit_index}
  end
end
