defmodule Doudizhu.Protocol.DomainCommand do
  @moduledoc "Shared mapping from validated protocol actions to domain commands."

  @spec from_action(Doudizhu.Protocol.CommandEnvelope.action(), String.t()) ::
          Doudizhu.Domain.Game.command()
  def from_action({:place_bid, bid}, player_id), do: {:bid, player_id, bid}
  def from_action(:auction_pass, player_id), do: {:bid, player_id, :pass}
  def from_action({:play_cards, cards}, player_id), do: {:play_cards, player_id, cards}
  def from_action(:play_pass, player_id), do: {:pass, player_id}
end
