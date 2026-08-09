defmodule DoudizhuWeb.Router do
  use DoudizhuWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DoudizhuWeb do
    get "/", UiController, :index
  end

  scope "/api", DoudizhuWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/guest-session", GuestSessionController, :create
  end
end
