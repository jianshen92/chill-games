defmodule Doudizhu.Games.ProcessedCommand do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "processed_commands" do
    field :game_id, :string
    field :command_id, :string
    field :actor_id, :string
    field :payload_hash, :string
    field :command_payload, :map
    field :result, :map
    field :resulting_version, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :game_id,
      :command_id,
      :actor_id,
      :payload_hash,
      :command_payload,
      :result,
      :resulting_version
    ])
    |> validate_required([
      :game_id,
      :command_id,
      :actor_id,
      :payload_hash,
      :command_payload,
      :result,
      :resulting_version
    ])
    |> unique_constraint([:game_id, :command_id])
    |> foreign_key_constraint(:game_id)
  end
end
