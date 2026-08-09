defmodule DoudizhuWeb.UiControllerTest do
  use DoudizhuWeb.ConnCase, async: true

  alias DoudizhuWeb.SessionToken

  test "GET / serves the Channel-based game UI", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "斗地主"
    assert html_response(conn, 200) =~ "Replay a game"
    assert html_response(conn, 200) =~ ~s(src="/assets/doudizhu.js")
    assert get_resp_header(conn, "content-security-policy") != []
  end

  test "browser assets are served", %{conn: conn} do
    conn = get(conn, "/assets/doudizhu.js")
    assert response(conn, 200) =~ "class ChannelSocket"
  end

  test "POST /api/guest-session returns a signed opaque identity", %{conn: conn} do
    conn = post(conn, ~p"/api/guest-session", %{name: " Alice "})
    payload = json_response(conn, 200)

    assert payload["name"] == "Alice"
    assert String.starts_with?(payload["identity_id"], "guest_")
    assert {:ok, identity_id} = SessionToken.verify(payload["token"])
    assert identity_id == payload["identity_id"]
  end

  test "guest names are validated", %{conn: conn} do
    conn = post(conn, ~p"/api/guest-session", %{name: "   "})
    assert json_response(conn, 422) == %{"error" => %{"code" => "name_required"}}
  end
end
