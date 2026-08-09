defmodule Doudizhu.Rooms.Room do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @type t :: %__MODULE__{}

  schema "rooms" do
    field :owner_id, :string
    field :invite_code_hash, :string
    field :status, :string, default: "open"
    field :game_id, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:id, :owner_id, :invite_code_hash, :status, :game_id])
    |> validate_required([:id, :owner_id, :invite_code_hash, :status])
    |> validate_inclusion(:status, ["open", "started", "closed"])
    |> unique_constraint(:id)
    |> unique_constraint(:invite_code_hash)
    |> unique_constraint(:game_id)
  end
end
