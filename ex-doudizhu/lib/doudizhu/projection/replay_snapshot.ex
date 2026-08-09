defmodule Doudizhu.Projection.ReplaySnapshot do
  @moduledoc "Full-information projection used only for completed public game reviews."

  alias Doudizhu.Domain.{Game, Hand, Players}
  alias Doudizhu.Projection.{Snapshot, Value}

  @spec build(Game.t(), [Doudizhu.Domain.Card.t()]) :: map()
  def build(%Game{} = game, bottom_cards \\ []) do
    {:ok, public} = Snapshot.build(game, :spectator)

    hands =
      Map.new(Players.ids(game.players), fn player_id ->
        cards =
          case Game.hand(game, player_id) do
            {:ok, hand} -> hand |> Hand.cards() |> Value.cards()
            :error -> []
          end

        {player_id, cards}
      end)

    roles =
      Map.new(Players.ids(game.players), fn player_id ->
        role =
          case Game.role(game, player_id) do
            {:ok, role} -> Atom.to_string(role)
            :error -> nil
          end

        {player_id, role}
      end)

    public
    |> Map.put("kind", "replay_snapshot")
    |> Map.put("hands", hands)
    |> Map.put("roles", roles)
    |> Map.put("bottom_cards", Value.cards(bottom_cards))
  end
end
