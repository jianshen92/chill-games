defmodule DoudizhuWeb.Presence do
  @moduledoc "Ephemeral online-controller presence; never a source of game or seat truth."

  use Phoenix.Presence,
    otp_app: :doudizhu,
    pubsub_server: Doudizhu.PubSub
end
