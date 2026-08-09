defmodule Doudizhu.Sessions.ControllerGrant do
  @moduledoc "Explicit authorization for an identity to control one stable game player."

  use Ecto.Schema
  import Ecto.Changeset

  schema "game_controller_grants" do
    field :game_id, :string
    field :player_id, :string
    field :identity_id, :string
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:game_id, :player_id, :identity_id, :active])
    |> validate_required([:game_id, :player_id, :identity_id, :active])
    |> unique_constraint([:game_id, :player_id, :identity_id])
    |> foreign_key_constraint(:game_id)
  end
end
