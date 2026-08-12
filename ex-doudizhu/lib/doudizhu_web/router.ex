defmodule DoudizhuWeb.Router do
  use DoudizhuWeb, :router

  @content_security_policy "default-src 'self'; connect-src 'self' ws: wss:; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DoudizhuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
    plug DoudizhuWeb.Plugs.EnsureGuestIdentity
    plug DoudizhuWeb.Plugs.SetLocale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DoudizhuWeb do
    pipe_through :browser

    live "/", GameLive, :index
  end

  scope "/api", DoudizhuWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/guest-session", GuestSessionController, :create
  end
end
