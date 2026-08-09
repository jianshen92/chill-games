defmodule DoudizhuWeb.UserSocket do
  use Phoenix.Socket

  alias DoudizhuWeb.SessionToken

  channel "game:*", DoudizhuWeb.GameChannel
  channel "room:*", DoudizhuWeb.RoomChannel
  channel "replay:*", DoudizhuWeb.ReplayChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, identity_id} <- SessionToken.verify(token) do
      {:ok,
       socket
       |> assign(:identity_id, identity_id)
       |> assign(:session_id, random_session_id())}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "identity:#{socket.assigns.identity_id}"

  defp random_session_id,
    do: "socket_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
