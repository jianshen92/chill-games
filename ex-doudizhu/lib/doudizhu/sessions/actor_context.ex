defmodule Doudizhu.Sessions.ActorContext do
  @moduledoc "Server-derived identity of a controller connection."

  @enforce_keys [:identity_id, :player_id, :game_id, :session_id, :lease_id, :role]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity_id: String.t(),
          player_id: String.t() | nil,
          game_id: String.t(),
          session_id: String.t(),
          lease_id: String.t() | nil,
          role: :player | :spectator
        }
end
