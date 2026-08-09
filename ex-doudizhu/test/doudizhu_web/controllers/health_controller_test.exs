defmodule DoudizhuWeb.HealthControllerTest do
  use DoudizhuWeb.ConnCase, async: true

  test "GET /api/health", %{conn: conn} do
    conn = get(conn, ~p"/api/health")
    assert json_response(conn, 200) == %{"status" => "ok", "protocol_version" => 1}
  end
end
