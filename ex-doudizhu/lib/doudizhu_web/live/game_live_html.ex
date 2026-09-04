defmodule DoudizhuWeb.GameLiveHTML do
  @moduledoc false

  use DoudizhuWeb, :html

  embed_templates "game_live_html/*"

  attr :card_id, :string, required: true
  attr :disabled, :boolean, default: false

  def card(assigns) do
    assigns = assign(assigns, :card, parse_card(assigns.card_id))

    ~H"""
    <button
      id={"card-#{@card_id}"}
      type="button"
      class={[
        "card",
        @card.red && "red",
        @card.joker && "joker"
      ]}
      aria-label={@card.label}
      aria-pressed="false"
      disabled={@disabled}
      data-card-id={@card_id}
    >
      <span class="rank">{@card.rank}</span>
      <span class="suit">{@card.suit}</span>
      <span class="card-center">{@card.center}</span>
    </button>
    """
  end

  attr :card_id, :string, required: true

  def mini_card(assigns) do
    assigns = assign(assigns, :card, parse_card(assigns.card_id))

    ~H"""
    <span class={["mini-card", @card.red && "red"]} title={@card.label}>
      {if @card.joker, do: @card.rank, else: @card.rank <> @card.suit}
    </span>
    """
  end

  def own_seat(room, identity_id) do
    Enum.find(room["seats"], &(&1["player_id"] == identity_id))
  end

  def can_start?(room, identity_id) do
    room["owner_id"] == identity_id and length(room["seats"]) == 3 and
      Enum.all?(room["seats"], & &1["ready"])
  end

  def current_player(game, players) do
    current_id = game["current_player"] || game["current_bidder"]
    Enum.find(players, &(&1["player_id"] == current_id))
  end

  def current_player_id(game), do: game["current_player"] || game["current_bidder"]

  def opponent_players(players, nil), do: players
  def opponent_players(players, own_id), do: Enum.reject(players, &(&1["player_id"] == own_id))

  def phase_name(phase) do
    %{
      "awaiting_deal" => gettext("Waiting for deal"),
      "bidding" => gettext("Call the landlord"),
      "playing" => pgettext("game phase", "Play"),
      "finished" => gettext("Settlement")
    }
    |> Map.get(phase, humanize(phase))
  end

  def room_status_name("open"), do: gettext("Open")
  def room_status_name("started"), do: gettext("Started")
  def room_status_name("closed"), do: gettext("Closed")
  def room_status_name(status), do: humanize(status)

  def role_name("landlord"), do: gettext("Landlord")
  def role_name("farmer"), do: gettext("Farmer")
  def role_name(nil), do: gettext("Unassigned")
  def role_name(role), do: humanize(role)

  def combination_name(nil), do: ""

  def combination_name(combination) do
    %{
      "single" => gettext("Single"),
      "pair" => gettext("Pair"),
      "triple" => gettext("Triple"),
      "triple_with_single" => gettext("Triple with single"),
      "triple_with_pair" => gettext("Triple with pair"),
      "straight" => gettext("Straight"),
      "consecutive_pairs" => gettext("Consecutive pairs"),
      "airplane" => gettext("Airplane"),
      "airplane_with_singles" => gettext("Airplane with singles"),
      "airplane_with_pairs" => gettext("Airplane with pairs"),
      "four_with_singles" => gettext("Four with singles"),
      "four_with_pairs" => gettext("Four with pairs"),
      "bomb" => gettext("Bomb"),
      "rocket" => gettext("Rocket")
    }
    |> Map.get(combination["type"], humanize(combination["type"]))
  end

  def card_count(count), do: ngettext("%{count} card", "%{count} cards", count)
  def turn_count(count), do: ngettext("%{count} turn", "%{count} turns", count)
  def selected_count(count), do: ngettext("%{count} selected", "%{count} selected", count)

  def replay_step(index, count) do
    gettext("Step %{current} of %{count}", current: index + 1, count: count)
  end

  def bid_label(bid), do: gettext("Bid %{bid}", bid: bid)

  def turn_message(game, players, identity_id, replaying?) do
    current = current_player(game, players)
    current_id = current_player_id(game)

    cond do
      game["phase"] == "finished" -> gettext("Game complete")
      replaying? && current -> gettext("Recorded turn: %{player}", player: current["name"])
      replaying? -> gettext("Recorded state")
      current_id == identity_id -> gettext("Your turn")
      current -> gettext("%{player} is thinking", player: current["name"])
      true -> gettext("Waiting")
    end
  end

  def event_description(event, players) do
    player = fn id ->
      case Enum.find(players, &(&1["player_id"] == id)) do
        nil -> gettext("A player")
        found -> found["name"]
      end
    end

    case event["type"] do
      "cards_dealt" ->
        gettext("Cards dealt. %{player} starts the auction.",
          player: player.(event["auction_starter"])
        )

      "auction_passed" ->
        gettext("%{player} passed in the auction.", player: player.(event["player_id"]))

      "bid_placed" ->
        gettext("%{player} bid %{bid}.", player: player.(event["player_id"]), bid: event["bid"])

      "deal_voided" ->
        gettext("Everyone passed. The deal was voided.")

      "landlord_chosen" ->
        gettext("%{player} became landlord with bid %{bid}.",
          player: player.(event["landlord"]),
          bid: event["bid"]
        )

      "cards_played" ->
        gettext("%{player} played %{combination}.",
          player: player.(event["player_id"]),
          combination: combination_name(event["combination"])
        )

      "turn_passed" ->
        gettext("%{player} passed.", player: player.(event["player_id"]))

      "lead_cleared" ->
        gettext("Lead cleared. %{player} leads again.", player: player.(event["next_leader"]))

      "game_finished" ->
        gettext("Game finished: %{side} win.",
          side: role_name(event["settlement"]["winning_side"])
        )

      type ->
        humanize(type)
    end
  end

  def replay_date(played_at) do
    case DateTime.from_iso8601(played_at) do
      {:ok, date_time, _offset} -> Calendar.strftime(date_time, "%Y-%m-%d %H:%M UTC")
      _error -> played_at
    end
  end

  def replay_result(%{"winner" => %{"side" => side}}),
    do: gettext("%{side} won", side: role_name(side))

  def replay_result(game), do: phase_name(game["status"])

  def winner_title(winner_name, side) do
    gettext("%{player} wins for the %{side}", player: winner_name, side: role_name(side))
  end

  def score(delta) when delta >= 0, do: "+#{delta}"
  def score(delta), do: to_string(delta)

  def error_message(%{"error" => error}), do: error_message(error)
  def error_message(%{"code" => code}), do: error_message(code)
  def error_message({:name_too_long, _maximum}), do: error_message("name_too_long")
  def error_message({:error, reason}), do: error_message(reason)

  def error_message(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> error_message()

  def error_message(code) when is_binary(code) do
    case code do
      "name_required" ->
        gettext("Enter a name to continue.")

      "name_too_long" ->
        gettext("Names may contain at most 30 characters.")

      "invalid_invite" ->
        gettext("That invitation code is invalid.")

      "room_not_found" ->
        gettext("That private table does not exist.")

      "room_full" ->
        gettext("This table already has three players.")

      "room_not_open" ->
        gettext("This table is no longer open.")

      "not_in_room" ->
        gettext("You do not have a seat at this table.")

      "not_room_owner" ->
        gettext("Only the table owner can start the game.")

      "players_not_ready" ->
        gettext("All three players must be ready.")

      "not_authorized" ->
        gettext("You are not authorized for that seat.")

      "controller_lease_invalid" ->
        gettext("This seat was opened in another connection. Reload to reclaim it.")

      "stale_game_version" ->
        gettext("Your view was stale. Resync and try again.")

      "not_players_turn" ->
        gettext("It is not your turn.")

      "bid_must_exceed" ->
        gettext("Your bid must exceed the current bid.")

      "invalid_combination" ->
        gettext("Those cards do not form a legal combination.")

      "cards_not_held" ->
        gettext("Your hand does not contain those cards.")

      "does_not_beat_current_lead" ->
        gettext("That play does not beat the current lead.")

      "cannot_pass_when_leading" ->
        gettext("You cannot pass when you have the lead.")

      "replay_not_finished" ->
        gettext("Full-information replay becomes available after the game finishes.")

      "replay_frame_not_found" ->
        gettext("That replay position does not exist.")

      "replay_diverged" ->
        gettext("The recorded commands did not reproduce the saved result.")

      "replay_corrupt" ->
        gettext("This replay record could not be reconstructed.")

      "game_not_found" ->
        gettext("That game does not exist.")

      "internal_error" ->
        gettext("The server could not complete that request.")

      _unknown ->
        humanize(code)
    end
  end

  def error_message(_reason), do: gettext("The server could not complete that request.")

  defp parse_card("JOKER_SMALL") do
    %{
      rank: "小",
      suit: "",
      center: "JOKER",
      label: gettext("Small joker"),
      joker: true,
      red: false
    }
  end

  defp parse_card("JOKER_BIG") do
    %{
      rank: "大",
      suit: "",
      center: "JOKER",
      label: gettext("Big joker"),
      joker: true,
      red: true
    }
  end

  defp parse_card(<<suit_id::binary-size(1), rank::binary>>) do
    suit =
      %{
        "C" => %{symbol: "♣", red: false},
        "D" => %{symbol: "♦", red: true},
        "H" => %{symbol: "♥", red: true},
        "S" => %{symbol: "♠", red: false}
      }
      |> Map.fetch!(suit_id)

    %{
      rank: rank,
      suit: suit.symbol,
      center: suit.symbol,
      label: card_label(suit_id, rank),
      joker: false,
      red: suit.red
    }
  end

  defp card_label("C", rank), do: gettext("%{rank} of clubs", rank: rank)
  defp card_label("D", rank), do: gettext("%{rank} of diamonds", rank: rank)
  defp card_label("H", rank), do: gettext("%{rank} of hearts", rank: rank)
  defp card_label("S", rank), do: gettext("%{rank} of spades", rank: rank)

  defp humanize(nil), do: gettext("Unknown error")

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
