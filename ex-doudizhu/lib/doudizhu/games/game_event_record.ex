defmodule Doudizhu.Games.GameEventRecord do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_events" do
    field :game_id, :string
    field :sequence, :integer
    field :event_index, :integer
    field :event_type, :string
    field :payload, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:game_id, :sequence, :event_index, :event_type, :payload])
    |> validate_required([:game_id, :sequence, :event_index, :event_type, :payload])
    |> unique_constraint([:game_id, :sequence, :event_index])
    |> foreign_key_constraint(:game_id)
  end
end
