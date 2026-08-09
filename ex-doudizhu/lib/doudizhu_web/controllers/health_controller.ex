defmodule DoudizhuWeb.HealthController do
  use DoudizhuWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", protocol_version: 1})
  end
end
