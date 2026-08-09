defmodule Doudizhu.Protocol.CommandEnvelope do
  @moduledoc "A validated protocol-v1 player command."

  @enforce_keys [:protocol_version, :game_id, :command_id, :expected_version, :action]
  defstruct @enforce_keys

  @type action ::
          {:place_bid, 1 | 2 | 3}
          | :auction_pass
          | {:play_cards, [Doudizhu.Domain.Card.t()]}
          | :play_pass

  @type t :: %__MODULE__{
          protocol_version: 1,
          game_id: String.t(),
          command_id: String.t(),
          expected_version: non_neg_integer(),
          action: action()
        }
end
