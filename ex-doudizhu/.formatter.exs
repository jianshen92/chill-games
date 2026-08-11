[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  subdirectories: ["priv/*/migrations"],
  inputs: [
    "*.{ex,exs}",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/*/seeds.exs",
    "lib/doudizhu_web/**/*.{heex}"
  ]
]
