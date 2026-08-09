defmodule Doudizhu.Games.GameRecord do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @derive {Phoenix.Param, key: :id}
  schema "games" do
    field :room_id, :string
    field :status, :string
    field :version, :integer
    field :snapshot_codec_version, :integer, default: 1
    field :rules, :map
    field :state, :map
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :room_id, :status, :version, :snapshot_codec_version, :rules, :state])
    |> validate_required([:id, :status, :version, :snapshot_codec_version, :rules, :state])
    |> unique_constraint(:id)
  end
end
