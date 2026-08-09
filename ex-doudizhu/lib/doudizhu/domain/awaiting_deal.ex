defmodule Doudizhu.Domain.AwaitingDeal do
  @moduledoc false
  @enforce_keys [:deal_number]
  defstruct [:deal_number]
  @type t :: %__MODULE__{deal_number: pos_integer()}
end
