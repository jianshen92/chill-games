defmodule DoudizhuWeb.SessionToken do
  @moduledoc "Signs and verifies guest/account identity for socket connections."

  @salt "socket-identity-v1"
  @max_age 30 * 24 * 60 * 60

  @spec sign(String.t()) :: String.t()
  def sign(identity_id) when is_binary(identity_id) and identity_id != "" do
    Phoenix.Token.sign(secret_key_base(), @salt, identity_id)
  end

  @spec verify(String.t()) :: {:ok, String.t()} | {:error, term()}
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(secret_key_base(), @salt, token, max_age: @max_age)
  end

  def verify(_token), do: {:error, :missing_token}

  defp secret_key_base do
    :doudizhu
    |> Application.fetch_env!(DoudizhuWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
