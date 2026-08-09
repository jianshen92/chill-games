defmodule Doudizhu.Sessions.LeaseManager do
  @moduledoc "Claims and validates one active controller lease per player seat."

  import Ecto.Query

  alias Doudizhu.Domain.Players
  alias Doudizhu.Games.GameRepository
  alias Doudizhu.Repo
  alias Doudizhu.Sessions.{ActorContext, ControllerGrant, ControllerLease}

  @spec claim(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, ActorContext.t()} | {:error, term()}
  def claim(identity_id, game_id, player_id, session_id) do
    with {:ok, game} <- GameRepository.load(game_id),
         true <- Players.contains?(game.players, player_id) || {:error, :not_authorized},
         true <- authorized?(identity_id, game_id, player_id) || {:error, :not_authorized} do
      lease_id = generate_id()

      Repo.transaction(fn ->
        query =
          from lease in ControllerLease,
            where: lease.game_id == ^game_id and lease.player_id == ^player_id,
            lock: "FOR UPDATE"

        attrs = %{
          game_id: game_id,
          player_id: player_id,
          identity_id: identity_id,
          lease_id: lease_id,
          session_id: session_id,
          expires_at: nil
        }

        case Repo.one(query) do
          nil ->
            %ControllerLease{}
            |> ControllerLease.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> ControllerLease.changeset(attrs)
            |> Repo.update!()
        end
      end)
      |> case do
        {:ok, _lease} ->
          {:ok,
           %ActorContext{
             identity_id: identity_id,
             player_id: player_id,
             game_id: game_id,
             session_id: session_id,
             lease_id: lease_id,
             role: :player
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec spectator(String.t(), String.t(), String.t()) :: ActorContext.t()
  def spectator(identity_id, game_id, session_id) do
    %ActorContext{
      identity_id: identity_id,
      player_id: nil,
      game_id: game_id,
      session_id: session_id,
      lease_id: nil,
      role: :spectator
    }
  end

  @spec validate(ActorContext.t()) :: :ok | {:error, :controller_lease_invalid | :not_authorized}
  def validate(%ActorContext{role: :spectator}), do: {:error, :not_authorized}

  def validate(%ActorContext{} = actor) do
    query =
      from lease in ControllerLease,
        where:
          lease.game_id == ^actor.game_id and lease.player_id == ^actor.player_id and
            lease.identity_id == ^actor.identity_id and lease.lease_id == ^actor.lease_id and
            lease.session_id == ^actor.session_id

    if Repo.exists?(query), do: :ok, else: {:error, :controller_lease_invalid}
  end

  defp authorized?(identity_id, game_id, player_id) do
    Repo.exists?(
      from grant in ControllerGrant,
        where:
          grant.game_id == ^game_id and grant.player_id == ^player_id and
            grant.identity_id == ^identity_id and grant.active
    )
  end

  defp generate_id,
    do: "lease_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
