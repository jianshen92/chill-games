defmodule Doudizhu.Repo.Migrations.AddGameIdToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :game_id, references(:games, type: :string, on_delete: :nilify_all)
    end

    create unique_index(:rooms, [:game_id])
  end
end
