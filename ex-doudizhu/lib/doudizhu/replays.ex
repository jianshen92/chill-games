defmodule Doudizhu.Replays do
  @moduledoc "Deterministic full-information reconstruction of completed games by public game ID."

  import Ecto.Query

  alias Doudizhu.Domain.{AwaitingDeal, Card, DeckOrder, Game, Players}
  alias Doudizhu.Games.{GameRecord, ProcessedCommand, SnapshotCodec}
  alias Doudizhu.Projection.{Event, ReplaySnapshot}
  alias Doudizhu.Protocol.{Decoder, DomainCommand}
  alias Doudizhu.Replays.Replay
  alias Doudizhu.Repo
  alias Doudizhu.Sessions.ControllerGrant

  @spec list_for_identity(String.t()) :: [map()]
  def list_for_identity(identity_id) do
    Repo.all(
      from grant in ControllerGrant,
        join: game in GameRecord,
        on: game.id == grant.game_id,
        where: grant.identity_id == ^identity_id and grant.active and game.status == "finished",
        order_by: [desc: game.updated_at],
        select: {grant.player_id, game}
    )
    |> Enum.uniq_by(fn {_player_id, game} -> game.id end)
    |> Enum.flat_map(fn {player_id, record} ->
      case SnapshotCodec.decode(record.state) do
        {:ok, game} -> [Map.put(metadata(game, record), "viewer_player_id", player_id)]
        {:error, _reason} -> []
      end
    end)
  end

  @spec open(String.t()) :: {:ok, Replay.t()} | {:error, term()}
  def open(game_id) do
    with %GameRecord{} = record <- Repo.get(GameRecord, game_id) || {:error, :game_not_found},
         {:ok, persisted_game} <- SnapshotCodec.decode(record.state),
         :ok <- verify_completed(persisted_game),
         {:ok, initial_game} <-
           Game.new(persisted_game.id, persisted_game.players, persisted_game.rules),
         {:ok, final_game, frames} <- replay_commands(initial_game, accepted_commands(game_id)),
         :ok <- verify_final_state(final_game, persisted_game) do
      {:ok,
       %Replay{
         game_id: game_id,
         metadata: metadata(persisted_game, record, length(frames)),
         frames: frames,
         final_game: final_game
       }}
    else
      nil -> {:error, :game_not_found}
      {:error, _reason} = error -> error
    end
  end

  @spec frame(Replay.t(), non_neg_integer()) :: {:ok, map()} | {:error, :frame_not_found}
  def frame(%Replay{} = replay, index) when is_integer(index) and index >= 0 do
    case Enum.at(replay.frames, index) do
      nil ->
        {:error, :frame_not_found}

      frame ->
        history =
          replay.frames
          |> Enum.take(index + 1)
          |> Enum.flat_map(& &1["events"])
          |> Enum.map(& &1["event"])

        {:ok, Map.put(frame, "history", history)}
    end
  end

  def frame(%Replay{}, _index), do: {:error, :frame_not_found}

  defp accepted_commands(game_id) do
    Repo.all(
      from command in ProcessedCommand,
        where: command.game_id == ^game_id,
        order_by: [asc: command.resulting_version, asc: command.id]
    )
    |> Enum.filter(&(&1.result["status"] == "accepted"))
  end

  defp replay_commands(initial_game, commands) do
    initial_frame = frame_payload(0, initial_game.version, [], ReplaySnapshot.build(initial_game))

    commands
    |> Enum.reduce_while(
      {:ok, initial_game, [], [initial_frame]},
      fn recorded, {:ok, game, bottom_cards, frames} ->
        with {:ok, command} <- decode_recorded_command(recorded),
             {:ok, next, events} <- Game.execute(game, command),
             :ok <- verify_recorded_version(next, recorded.resulting_version) do
          next_bottom_cards = next_bottom_cards(command, next, bottom_cards)
          snapshot = ReplaySnapshot.build(next, next_bottom_cards)

          frame =
            frame_payload(length(frames), next.version, Event.public(next, events), snapshot)

          {:cont, {:ok, next, next_bottom_cards, [frame | frames]}}
        else
          {:error, reason} -> {:halt, {:error, {:replay_failed, recorded.command_id, reason}}}
        end
      end
    )
    |> case do
      {:ok, game, _bottom_cards, reversed_frames} -> {:ok, game, Enum.reverse(reversed_frames)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_recorded_command(%ProcessedCommand{
         actor_id: "system",
         command_payload: %{
           "type" => "system_deal",
           "auction_starter" => starter,
           "cards" => card_ids
         }
       }) do
    with {:ok, cards} <- decode_cards(card_ids),
         {:ok, deck} <- DeckOrder.new(cards) do
      {:ok, {:deal, deck, starter}}
    end
  end

  defp decode_recorded_command(%ProcessedCommand{} = recorded) do
    with {:ok, envelope} <- Decoder.decode_command(recorded.command_payload) do
      {:ok, DomainCommand.from_action(envelope.action, recorded.actor_id)}
    end
  end

  defp decode_cards(card_ids) when is_list(card_ids) do
    Enum.reduce_while(card_ids, {:ok, []}, fn card_id, {:ok, cards} ->
      case Card.from_id(card_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_cards(_cards), do: {:error, :invalid_recorded_cards}

  defp next_bottom_cards({:deal, %DeckOrder{} = deck, _starter}, _next, _current),
    do: deck |> DeckOrder.cards() |> Enum.drop(51)

  defp next_bottom_cards(_command, %Game{state: %AwaitingDeal{}}, _current), do: []

  defp next_bottom_cards(_command, _next, current), do: current

  defp verify_completed(%Game{} = game) do
    if Game.phase(game) == :finished, do: :ok, else: {:error, :replay_not_finished}
  end

  defp verify_recorded_version(%Game{version: version}, version), do: :ok

  defp verify_recorded_version(_game, expected),
    do: {:error, {:recorded_version_mismatch, expected}}

  defp verify_final_state(replayed, persisted) do
    if SnapshotCodec.encode(replayed) == SnapshotCodec.encode(persisted),
      do: :ok,
      else: {:error, :replay_diverged}
  end

  defp frame_payload(index, sequence, events, snapshot) do
    %{
      "index" => index,
      "sequence" => sequence,
      "events" => events,
      "snapshot" => snapshot
    }
  end

  defp metadata(game, record, frame_count \\ nil) do
    status = Game.status(game)

    %{
      "game_id" => game.id,
      "public_replay_id" => game.id,
      "status" => Atom.to_string(Game.phase(game)),
      "final_version" => game.version,
      "frame_count" => frame_count,
      "played_at" => DateTime.to_iso8601(record.inserted_at),
      "players" =>
        Enum.map(Players.all(game.players), fn player ->
          %{"player_id" => player.id, "name" => player.name}
        end),
      "winner" => winner(status)
    }
  end

  defp winner(%{phase: :finished, settlement: settlement}) do
    %{
      "player_id" => settlement.winning_player,
      "side" => Atom.to_string(settlement.winning_side)
    }
  end

  defp winner(_status), do: nil
end
