defmodule DoudizhuWeb.GuestSessionController do
  use DoudizhuWeb, :controller

  alias Doudizhu.Domain.Player
  alias DoudizhuWeb.SessionToken

  def create(conn, %{"name" => name}) do
    identity_id = "guest_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    case Player.new(identity_id, name) do
      {:ok, player} ->
        json(conn, %{
          protocol_version: 1,
          identity_id: player.id,
          name: player.name,
          token: SessionToken.sign(player.id)
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: player_error(reason)}})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "name_required"}})
  end

  defp player_error(:name_required), do: "name_required"
  defp player_error({:name_too_long, _maximum}), do: "name_too_long"
  defp player_error(_reason), do: "invalid_guest"
end
