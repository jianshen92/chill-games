defmodule Mix.Tasks.Doudizhu.Token do
  use Mix.Task

  @shortdoc "Prints a signed socket token for a guest identity"

  @impl Mix.Task
  def run([identity_id]) do
    Mix.Task.run("app.config")
    {:ok, _applications} = Application.ensure_all_started(:plug_crypto)
    Mix.shell().info(DoudizhuWeb.SessionToken.sign(identity_id))
  end

  def run(_args) do
    Mix.raise("usage: mix doudizhu.token IDENTITY_ID")
  end
end
