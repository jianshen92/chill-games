defmodule Doudizhu.Repo.Migrations.AddControllerAuthorization do
  use Ecto.Migration

  def change do
    create table(:game_controller_grants) do
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :player_id, :string, null: false
      add :identity_id, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:game_controller_grants, [:game_id, :player_id, :identity_id])
    create index(:game_controller_grants, [:game_id, :identity_id])

    alter table(:controller_leases) do
      add :identity_id, :string, null: false
    end
  end
end
