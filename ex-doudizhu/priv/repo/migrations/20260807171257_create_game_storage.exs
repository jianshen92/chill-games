defmodule Doudizhu.Repo.Migrations.CreateGameStorage do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :string, primary_key: true
      add :room_id, :string
      add :status, :string, null: false
      add :version, :bigint, null: false, default: 0
      add :snapshot_codec_version, :integer, null: false, default: 1
      add :rules, :map, null: false
      add :state, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:game_events) do
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :event_index, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:game_events, [:game_id, :sequence, :event_index])

    create table(:processed_commands) do
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :command_id, :string, null: false
      add :actor_id, :string, null: false
      add :payload_hash, :string, null: false
      add :command_payload, :map, null: false
      add :result, :map, null: false
      add :resulting_version, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:processed_commands, [:game_id, :command_id])

    create table(:outbox_messages) do
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :audience_kind, :string, null: false
      add :audience_id, :string
      add :payload, :map, null: false
      add :attempts, :integer, null: false, default: 0
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:outbox_messages, [:published_at])
    create index(:outbox_messages, [:game_id, :sequence])

    create table(:controller_leases) do
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :player_id, :string, null: false
      add :lease_id, :string, null: false
      add :session_id, :string, null: false
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:controller_leases, [:game_id, :player_id])
    create unique_index(:controller_leases, [:lease_id])
  end
end
