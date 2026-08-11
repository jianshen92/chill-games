defmodule DoudizhuWeb.GameLiveHTML do
  @moduledoc false

  use DoudizhuWeb, :html

  embed_templates "game_live_html/*"

  attr :card_id, :string, required: true
  attr :selected, :boolean, default: false
  attr :disabled, :boolean, default: false

  def card(assigns) do
    assigns = assign(assigns, :card, parse_card(assigns.card_id))

    ~H"""
    <button
      type="button"
      class={[
        "card",
        @card.red && "red",
        @card.joker && "joker",
        @selected && "selected"
      ]}
      aria-label={@card.label}
      aria-pressed={to_string(@selected)}
      disabled={@disabled}
      phx-click="toggle-card"
      phx-value-card={@card_id}
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
      "awaiting_deal" => "Waiting for deal",
      "bidding" => "Call the landlord",
      "playing" => "Play",
      "finished" => "Settlement"
    }
    |> Map.get(phase, phase)
  end

  def combination_name(nil), do: ""

  def combination_name(combination) do
    %{
      "single" => "Single",
      "pair" => "Pair",
      "triple" => "Triple",
      "triple_with_single" => "Triple with single",
      "triple_with_pair" => "Triple with pair",
      "straight" => "Straight",
      "consecutive_pairs" => "Consecutive pairs",
      "airplane" => "Airplane",
      "airplane_with_singles" => "Airplane with singles",
      "airplane_with_pairs" => "Airplane with pairs",
      "four_with_singles" => "Four with singles",
      "four_with_pairs" => "Four with pairs",
      "bomb" => "Bomb",
      "rocket" => "Rocket"
    }
    |> Map.get(combination["type"], combination["type"])
  end

  def turn_message(game, players, identity_id, replaying?) do
    current = current_player(game, players)
    current_id = current_player_id(game)

    cond do
      game["phase"] == "finished" -> "Game complete"
      replaying? && current -> "Recorded turn: #{current["name"]}"
      replaying? -> "Recorded state"
      current_id == identity_id -> "Your turn"
      current -> "#{current["name"]} is thinking"
      true -> "Waiting"
    end
  end

  def event_description(event, players) do
    player = fn id ->
      case Enum.find(players, &(&1["player_id"] == id)) do
        nil -> "A player"
        found -> found["name"]
      end
    end

    case event["type"] do
      "cards_dealt" ->
        "Cards dealt. #{player.(event["auction_starter"])} starts the auction."

      "auction_passed" ->
        "#{player.(event["player_id"])} passed in the auction."

      "bid_placed" ->
        "#{player.(event["player_id"])} bid #{event["bid"]}."

      "deal_voided" ->
        "Everyone passed. The deal was voided."

      "landlord_chosen" ->
        "#{player.(event["landlord"])} became landlord with bid #{event["bid"]}."

      "cards_played" ->
        "#{player.(event["player_id"])} played #{combination_name(event["combination"])}."

      "turn_passed" ->
        "#{player.(event["player_id"])} passed."

      "lead_cleared" ->
        "Lead cleared. #{player.(event["next_leader"])} leads again."

      "game_finished" ->
        "Game finished: #{event["settlement"]["winning_side"]} win."

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

  def replay_result(%{"winner" => %{"side" => side}}), do: "#{side} won"
  def replay_result(game), do: game["status"]

  def score(delta) when delta >= 0, do: "+#{delta}"
  def score(delta), do: to_string(delta)

  def error_message(%{"error" => error}), do: error_message(error)
  def error_message(%{"code" => code}), do: error_message(code)
  def error_message({:name_too_long, _maximum}), do: error_message("name_too_long")
  def error_message({:error, reason}), do: error_message(reason)

  def error_message(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> error_message()

  def error_message(code) when is_binary(code) do
    %{
      "name_required" => "Enter a name to continue.",
      "name_too_long" => "Names may contain at most 30 characters.",
      "invalid_invite" => "That invitation code is invalid.",
      "room_not_found" => "That private table does not exist.",
      "room_full" => "This table already has three players.",
      "room_not_open" => "This table is no longer open.",
      "not_in_room" => "You do not have a seat at this table.",
      "not_room_owner" => "Only the table owner can start the game.",
      "players_not_ready" => "All three players must be ready.",
      "not_authorized" => "You are not authorized for that seat.",
      "controller_lease_invalid" =>
        "This seat was opened in another connection. Reload to reclaim it.",
      "stale_game_version" => "Your view was stale. Resync and try again.",
      "not_players_turn" => "It is not your turn.",
      "bid_must_exceed" => "Your bid must exceed the current bid.",
      "invalid_combination" => "Those cards do not form a legal combination.",
      "cards_not_held" => "Your hand does not contain those cards.",
      "does_not_beat_current_lead" => "That play does not beat the current lead.",
      "cannot_pass_when_leading" => "You cannot pass when you have the lead.",
      "replay_not_finished" =>
        "Full-information replay becomes available after the game finishes.",
      "replay_frame_not_found" => "That replay position does not exist.",
      "replay_diverged" => "The recorded commands did not reproduce the saved result.",
      "replay_corrupt" => "This replay record could not be reconstructed.",
      "game_not_found" => "That game does not exist.",
      "internal_error" => "The server could not complete that request."
    }
    |> Map.get(code, humanize(code))
  end

  def error_message(_reason), do: "The server could not complete that request."

  defp parse_card("JOKER_SMALL") do
    %{rank: "小", suit: "", center: "JOKER", label: "Small joker", joker: true, red: false}
  end

  defp parse_card("JOKER_BIG") do
    %{rank: "大", suit: "", center: "JOKER", label: "Big joker", joker: true, red: true}
  end

  defp parse_card(<<suit_id::binary-size(1), rank::binary>>) do
    suit =
      %{
        "C" => %{symbol: "♣", name: "clubs", red: false},
        "D" => %{symbol: "♦", name: "diamonds", red: true},
        "H" => %{symbol: "♥", name: "hearts", red: true},
        "S" => %{symbol: "♠", name: "spades", red: false}
      }
      |> Map.fetch!(suit_id)

    %{
      rank: rank,
      suit: suit.symbol,
      center: suit.symbol,
      label: "#{rank} of #{suit.name}",
      joker: false,
      red: suit.red
    }
  end

  defp humanize(nil), do: "Unknown error"

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
