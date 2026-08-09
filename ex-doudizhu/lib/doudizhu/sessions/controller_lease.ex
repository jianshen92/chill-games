defmodule Doudizhu.Sessions.ControllerLease do
  @moduledoc "A persisted single-controller lease for one player seat."
  use Ecto.Schema
  import Ecto.Changeset

  schema "controller_leases" do
    field :game_id, :string
    field :player_id, :string
    field :identity_id, :string
    field :lease_id, :string
    field :session_id, :string
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:game_id, :player_id, :identity_id, :lease_id, :session_id, :expires_at])
    |> validate_required([:game_id, :player_id, :identity_id, :lease_id, :session_id])
    |> unique_constraint([:game_id, :player_id])
    |> unique_constraint(:lease_id)
    |> foreign_key_constraint(:game_id)
  end
end
