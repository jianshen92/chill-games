defmodule Doudizhu.Games.OutboxMessage do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "outbox_messages" do
    field :game_id, :string
    field :sequence, :integer
    field :audience_kind, :string
    field :audience_id, :string
    field :payload, :map
    field :attempts, :integer, default: 0
    field :published_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :game_id,
      :sequence,
      :audience_kind,
      :audience_id,
      :payload,
      :attempts,
      :published_at
    ])
    |> validate_required([:game_id, :sequence, :audience_kind, :payload, :attempts])
    |> validate_inclusion(:audience_kind, ["public", "player"])
    |> foreign_key_constraint(:game_id)
  end
end
