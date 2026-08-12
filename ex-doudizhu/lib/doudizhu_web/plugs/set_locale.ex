defmodule DoudizhuWeb.Plugs.SetLocale do
  @moduledoc "Selects a supported Gettext locale for each browser request."

  import Plug.Conn

  alias DoudizhuWeb.Gettext, as: GettextBackend
  alias DoudizhuWeb.Locale

  @cookie "doudizhu_locale"

  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _options) do
    conn = conn |> fetch_query_params() |> fetch_cookies()

    locale =
      Locale.negotiate([
        conn.query_params["locale"],
        conn.cookies[@cookie],
        get_session(conn, :locale),
        accept_language(conn)
      ])

    Gettext.put_locale(GettextBackend, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp accept_language(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> Locale.from_accept_language()
  end
end
