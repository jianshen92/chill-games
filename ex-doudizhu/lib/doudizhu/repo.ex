defmodule Doudizhu.Repo do
  use Ecto.Repo,
    otp_app: :doudizhu,
    adapter: Ecto.Adapters.Postgres
end
