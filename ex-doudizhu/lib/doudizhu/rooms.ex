defmodule Doudizhu.Rooms do
  @moduledoc "Durable friend-room lifecycle and exactly-three-seat rules."

  import Ecto.Query

  alias Doudizhu.Domain.{Game, Player, Players, RuleSet}
  alias Doudizhu.Games.{DeckFactory, GameRepository, GameServer, GameSupervisor}
  alias Doudizhu.Repo
  alias Doudizhu.Rooms.{Room, RoomSeat}

  @spec create(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def create(owner_id, player_name) do
    room_id = random_id("room")
    invite_code = invite_code()

    Repo.transaction(fn ->
      room =
        %Room{}
        |> Room.create_changeset(%{
          id: room_id,
          owner_id: owner_id,
          invite_code_hash: hash_invite(invite_code),
          status: "open"
        })
        |> Repo.insert!()

      %RoomSeat{}
      |> RoomSeat.create_changeset(%{
        room_id: room_id,
        position: 1,
        player_id: owner_id,
        player_name: player_name,
        ready: false
      })
      |> Repo.insert!()

      %{room: room, invite_code: invite_code}
    end)
    |> tap_success(fn _result -> broadcast(room_id) end)
  end

  @spec join(String.t(), String.t() | nil, String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def join(room_id, invite_code, player_id, player_name) do
    Repo.transaction(fn ->
      room = lock_room!(room_id)
      existing = seat_for(room_id, player_id)

      cond do
        existing ->
          existing

        room.status != "open" ->
          Repo.rollback(:room_not_open)

        not valid_invite?(room, invite_code) ->
          Repo.rollback(:invalid_invite)

        true ->
          seats = seats(room_id)

          if length(seats) >= 3 do
            Repo.rollback(:room_full)
          else
            position =
              Enum.find(1..3, fn position -> Enum.all?(seats, &(&1.position != position)) end)

            %RoomSeat{}
            |> RoomSeat.create_changeset(%{
              room_id: room_id,
              position: position,
              player_id: player_id,
              player_name: player_name,
              ready: false
            })
            |> Repo.insert!()
          end
      end
    end)
    |> tap_success(fn _seat -> broadcast(room_id) end)
  end

  @spec set_ready(String.t(), String.t(), boolean()) :: {:ok, map()} | {:error, term()}
  def set_ready(room_id, player_id, ready) when is_boolean(ready) do
    Repo.transaction(fn ->
      room = lock_room!(room_id)
      if room.status != "open", do: Repo.rollback(:room_not_open)

      case seat_for(room_id, player_id) do
        nil -> Repo.rollback(:not_in_room)
        seat -> seat |> Ecto.Changeset.change(ready: ready) |> Repo.update!()
      end
    end)
    |> tap_success(fn _seat -> broadcast(room_id) end)
  end

  @spec start_game(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def start_game(room_id, requester_id) do
    transaction_result =
      Repo.transaction(fn ->
        room = lock_room!(room_id)

        cond do
          room.owner_id != requester_id -> Repo.rollback(:not_room_owner)
          room.status != "open" -> Repo.rollback(:room_not_open)
          true -> :ok
        end

        seats = seats(room_id)

        if length(seats) != 3 or not Enum.all?(seats, & &1.ready) do
          Repo.rollback(:players_not_ready)
        end

        players = domain_players!(seats)
        game_id = random_id("game")
        {:ok, game} = Game.new(game_id, players, RuleSet.standard_three_player())

        case GameRepository.create(game, room_id) do
          {:ok, _game} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        room =
          room |> Ecto.Changeset.change(status: "started", game_id: game_id) |> Repo.update!()

        %{room: room, game: game, auction_starter: hd(seats).player_id}
      end)

    with {:ok, %{game: game, auction_starter: starter}} <- transaction_result,
         {:ok, _server} <- GameSupervisor.start_game(game.id) do
      result = GameServer.deal(game.id, DeckFactory.random(), starter)

      if result["status"] == "accepted" do
        broadcast(room_id)
        {:ok, snapshot(room_id)}
      else
        {:error, {:deal_failed, result}}
      end
    end
  end

  @spec snapshot(String.t()) :: map() | nil
  def snapshot(room_id) do
    case Repo.get(Room, room_id) do
      nil -> nil
      room -> encode_room(room, seats(room_id))
    end
  end

  @spec room_topic(String.t()) :: String.t()
  def room_topic(room_id), do: "room:#{room_id}"

  defp lock_room!(room_id) do
    case Repo.one(from room in Room, where: room.id == ^room_id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(:room_not_found)
      room -> room
    end
  end

  defp seats(room_id) do
    Repo.all(
      from seat in RoomSeat, where: seat.room_id == ^room_id, order_by: [asc: seat.position]
    )
  end

  defp seat_for(room_id, player_id) do
    Repo.one(
      from seat in RoomSeat, where: seat.room_id == ^room_id and seat.player_id == ^player_id
    )
  end

  defp valid_invite?(_room, invite_code) when not is_binary(invite_code), do: false

  defp valid_invite?(room, invite_code) do
    Plug.Crypto.secure_compare(room.invite_code_hash, hash_invite(invite_code))
  end

  defp domain_players!([first, second, third]) do
    {:ok, first} = Player.new(first.player_id, first.player_name)
    {:ok, second} = Player.new(second.player_id, second.player_name)
    {:ok, third} = Player.new(third.player_id, third.player_name)
    {:ok, players} = Players.new(first, second, third)
    players
  end

  defp encode_room(room, seats) do
    %{
      "protocol_version" => 1,
      "kind" => "room_snapshot",
      "room_id" => room.id,
      "owner_id" => room.owner_id,
      "status" => room.status,
      "game_id" => room.game_id,
      "seats" =>
        Enum.map(seats, fn seat ->
          %{
            "position" => seat.position,
            "player_id" => seat.player_id,
            "player_name" => seat.player_name,
            "ready" => seat.ready
          }
        end)
    }
  end

  defp broadcast(room_id) do
    if snapshot = snapshot(room_id) do
      Phoenix.PubSub.broadcast(Doudizhu.PubSub, room_topic(room_id), {:room_message, snapshot})
    end

    :ok
  end

  defp tap_success({:ok, value} = result, callback) do
    callback.(value)
    result
  end

  defp tap_success(result, _callback), do: result

  defp invite_code do
    :crypto.strong_rand_bytes(6)
    |> Base.encode32(case: :upper, padding: false)
    |> binary_part(0, 8)
  end

  defp hash_invite(code) do
    normalized = code |> String.trim() |> String.upcase()
    :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
  end

  defp random_id(prefix),
    do: prefix <> "_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
