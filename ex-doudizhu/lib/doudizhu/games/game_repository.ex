defmodule Doudizhu.Games.GameRepository do
  @moduledoc "Transactional persistence boundary for games, commands, events, and outbox messages."

  import Ecto.Query

  alias Doudizhu.Domain.{Game, Players}

  alias Doudizhu.Games.{
    GameEventRecord,
    GameRecord,
    OutboxMessage,
    ProcessedCommand,
    SnapshotCodec
  }

  alias Doudizhu.Projection.{Event, Snapshot}
  alias Doudizhu.Protocol.CommandEnvelope
  alias Doudizhu.Repo
  alias Doudizhu.Sessions.ControllerGrant

  @spec create(Game.t(), String.t() | nil) :: {:ok, Game.t()} | {:error, term()}
  def create(%Game{} = game, room_id \\ nil) do
    attrs = %{
      id: game.id,
      room_id: room_id,
      status: Atom.to_string(Game.phase(game)),
      version: game.version,
      snapshot_codec_version: SnapshotCodec.version(),
      rules: SnapshotCodec.encode_rules(game.rules),
      state: SnapshotCodec.encode(game)
    }

    Repo.transaction(fn ->
      case %GameRecord{} |> GameRecord.create_changeset(attrs) |> Repo.insert() do
        {:ok, _record} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end

      game.players
      |> Players.ids()
      |> Enum.each(fn player_id ->
        %ControllerGrant{}
        |> ControllerGrant.changeset(%{
          game_id: game.id,
          player_id: player_id,
          identity_id: player_id,
          active: true
        })
        |> Repo.insert!()
      end)

      game
    end)
  end

  @spec load(String.t()) :: {:ok, Game.t()} | {:error, :game_not_found | term()}
  def load(game_id) do
    case Repo.get(GameRecord, game_id) do
      nil -> {:error, :game_not_found}
      record -> SnapshotCodec.decode(record.state)
    end
  end

  @spec processed_command(String.t(), String.t()) :: ProcessedCommand.t() | nil
  def processed_command(game_id, command_id) do
    Repo.one(
      from command in ProcessedCommand,
        where: command.game_id == ^game_id and command.command_id == ^command_id
    )
  end

  @spec commit(
          Game.t(),
          Game.t(),
          [map()],
          String.t(),
          CommandEnvelope.t(),
          map(),
          String.t(),
          map()
        ) :: {:ok, [OutboxMessage.t()]} | {:error, term()}
  def commit(
        %Game{} = previous,
        %Game{} = next,
        events,
        actor_id,
        %CommandEnvelope{} = envelope,
        command_payload,
        payload_hash,
        result
      ) do
    Repo.transaction(fn ->
      assert_version_and_update!(previous, next)
      insert_events!(next, events)
      insert_processed_command!(next, actor_id, envelope, command_payload, payload_hash, result)
      insert_outbox!(next, events)
    end)
  end

  @spec record_rejection(Game.t(), String.t(), CommandEnvelope.t(), map(), String.t(), map()) ::
          {:ok, ProcessedCommand.t()} | {:error, term()}
  def record_rejection(game, actor_id, envelope, command_payload, payload_hash, result) do
    %ProcessedCommand{}
    |> ProcessedCommand.changeset(%{
      game_id: game.id,
      command_id: envelope.command_id,
      actor_id: actor_id,
      payload_hash: payload_hash,
      command_payload: command_payload,
      result: result,
      resulting_version: game.version
    })
    |> Repo.insert()
  end

  @spec unpublished(non_neg_integer()) :: [OutboxMessage.t()]
  def unpublished(limit \\ 100) do
    Repo.all(
      from message in OutboxMessage,
        where: is_nil(message.published_at),
        order_by: [asc: message.id],
        limit: ^limit
    )
  end

  @spec mark_published(OutboxMessage.t()) ::
          {:ok, OutboxMessage.t()} | {:error, Ecto.Changeset.t()}
  def mark_published(%OutboxMessage{} = message) do
    message
    |> Ecto.Changeset.change(published_at: DateTime.utc_now(), attempts: message.attempts + 1)
    |> Repo.update()
  end

  defp assert_version_and_update!(previous, next) do
    query =
      from game in GameRecord,
        where: game.id == ^previous.id and game.version == ^previous.version

    {count, _rows} =
      Repo.update_all(query,
        set: [
          status: Atom.to_string(Game.phase(next)),
          version: next.version,
          snapshot_codec_version: SnapshotCodec.version(),
          rules: SnapshotCodec.encode_rules(next.rules),
          state: SnapshotCodec.encode(next),
          updated_at: DateTime.utc_now()
        ]
      )

    if count != 1, do: Repo.rollback({:version_conflict, previous.version})
  end

  defp insert_events!(game, events) do
    public_events = Event.public(game, events)

    public_events
    |> Enum.each(fn message ->
      event = message["event"]

      %GameEventRecord{}
      |> GameEventRecord.changeset(%{
        game_id: game.id,
        sequence: game.version,
        event_index: message["event_index"],
        event_type: event["type"],
        payload: event
      })
      |> Repo.insert!()
    end)
  end

  defp insert_processed_command!(game, actor_id, envelope, command_payload, payload_hash, result) do
    %ProcessedCommand{}
    |> ProcessedCommand.changeset(%{
      game_id: game.id,
      command_id: envelope.command_id,
      actor_id: actor_id,
      payload_hash: payload_hash,
      command_payload: command_payload,
      result: result,
      resulting_version: game.version
    })
    |> Repo.insert!()
  end

  defp insert_outbox!(game, events) do
    public = Enum.map(Event.public(game, events), &{:public, nil, &1})

    private =
      game.players
      |> Players.ids()
      |> Enum.map(fn player_id ->
        {:ok, snapshot} = Snapshot.build(game, {:player, player_id})
        {:player, player_id, snapshot}
      end)

    Enum.map(public ++ private, fn {audience, audience_id, payload} ->
      %OutboxMessage{}
      |> OutboxMessage.changeset(%{
        game_id: game.id,
        sequence: game.version,
        audience_kind: Atom.to_string(audience),
        audience_id: audience_id,
        payload: payload,
        attempts: 0
      })
      |> Repo.insert!()
    end)
  end
end
