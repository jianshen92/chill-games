defmodule DoudizhuWeb.UiController do
  use DoudizhuWeb, :controller

  @csp "default-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"

  def index(conn, _params) do
    html =
      :doudizhu
      |> Application.app_dir("priv/static/ui.html")
      |> File.read!()

    conn
    |> put_resp_header("content-security-policy", @csp)
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
