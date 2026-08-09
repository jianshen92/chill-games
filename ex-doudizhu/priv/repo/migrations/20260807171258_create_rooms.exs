defmodule Doudizhu.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :string, primary_key: true
      add :owner_id, :string, null: false
      add :invite_code_hash, :string, null: false
      add :status, :string, null: false, default: "open"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rooms, [:invite_code_hash])

    create table(:room_seats) do
      add :room_id, references(:rooms, type: :string, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :player_id, :string, null: false
      add :player_name, :string, null: false
      add :ready, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:room_seats, :position_between_one_and_three,
             check: "position >= 1 AND position <= 3"
           )

    create unique_index(:room_seats, [:room_id, :position])
    create unique_index(:room_seats, [:room_id, :player_id])
    create index(:games, [:room_id])
  end
end
