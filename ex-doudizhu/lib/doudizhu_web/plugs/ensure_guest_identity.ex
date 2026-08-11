defmodule DoudizhuWeb.Plugs.EnsureGuestIdentity do
  @moduledoc "Ensures every browser session has a stable opaque guest identity."

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _options) do
    if get_session(conn, :identity_id) do
      conn
    else
      put_session(conn, :identity_id, random_identity_id())
    end
  end

  defp random_identity_id do
    "guest_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
