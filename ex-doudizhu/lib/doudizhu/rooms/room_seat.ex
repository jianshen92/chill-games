defmodule Doudizhu.Rooms.RoomSeat do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "room_seats" do
    field :room_id, :string
    field :position, :integer
    field :player_id, :string
    field :player_name, :string
    field :ready, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(seat, attrs) do
    seat
    |> cast(attrs, [:room_id, :position, :player_id, :player_name, :ready])
    |> validate_required([:room_id, :position, :player_id, :player_name, :ready])
    |> validate_number(:position, greater_than_or_equal_to: 1, less_than_or_equal_to: 3)
    |> validate_length(:player_name, min: 1, max: 30)
    |> unique_constraint([:room_id, :position])
    |> unique_constraint([:room_id, :player_id])
    |> foreign_key_constraint(:room_id)
  end
end
