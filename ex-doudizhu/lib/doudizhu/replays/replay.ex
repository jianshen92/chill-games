defmodule Doudizhu.Replays.Replay do
  @moduledoc false

  alias Doudizhu.Domain.Game

  @enforce_keys [:game_id, :metadata, :frames, :final_game]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          game_id: String.t(),
          metadata: map(),
          frames: [map()],
          final_game: Game.t()
        }
end
