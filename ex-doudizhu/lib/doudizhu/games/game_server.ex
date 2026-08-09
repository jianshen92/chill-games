defmodule Doudizhu.Games.GameServer do
  @moduledoc "Serializes commands for one game while delegating all rules to the pure domain."

  use GenServer, restart: :transient

  alias Doudizhu.Domain.{Card, DeckOrder, Game}
  alias Doudizhu.Games.{GameRepository, OutboxPublisher}
  alias Doudizhu.Projection.Snapshot
  alias Doudizhu.Protocol.{CommandEnvelope, DomainCommand, Message}
  alias Doudizhu.Sessions.ActorContext

  def start_link(game_id), do: GenServer.start_link(__MODULE__, game_id, name: via(game_id))

  def child_spec(game_id) do
    %{id: {__MODULE__, game_id}, start: {__MODULE__, :start_link, [game_id]}, restart: :transient}
  end

  @spec submit(String.t(), ActorContext.t(), CommandEnvelope.t(), map(), String.t()) :: map()
  def submit(game_id, actor, envelope, command_payload, payload_hash) do
    GenServer.call(via(game_id), {:submit, actor, envelope, command_payload, payload_hash})
  end

  @spec deal(String.t(), DeckOrder.t(), String.t()) :: map()
  def deal(game_id, deck, auction_starter) do
    GenServer.call(via(game_id), {:deal, deck, auction_starter})
  end

  @spec snapshot(String.t(), :spectator | {:player, String.t()}) ::
          {:ok, map()} | {:error, term()}
  def snapshot(game_id, audience), do: GenServer.call(via(game_id), {:snapshot, audience})

  @spec game(String.t()) :: Game.t()
  def game(game_id), do: GenServer.call(via(game_id), :game)

  @spec via(String.t()) :: {:via, Registry, {Doudizhu.Games.Registry, String.t()}}
  def via(game_id), do: {:via, Registry, {Doudizhu.Games.Registry, game_id}}

  @impl true
  def init(game_id) do
    case GameRepository.load(game_id) do
      {:ok, game} -> {:ok, %{game: game}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:game, _from, state), do: {:reply, state.game, state}

  def handle_call({:snapshot, audience}, _from, state) do
    {:reply, Snapshot.build(state.game, audience), state}
  end

  def handle_call({:submit, actor, envelope, command_payload, payload_hash}, _from, state) do
    case duplicate_result(state.game, actor, envelope, payload_hash) do
      {:duplicate, result} ->
        {:reply, result, state}

      {:conflict, result} ->
        {:reply, result, state}

      :new ->
        process_new_command(state, actor, envelope, command_payload, payload_hash)
    end
  end

  def handle_call({:deal, %DeckOrder{} = deck, auction_starter}, _from, state) do
    command_id = "system-deal-" <> random_id()

    envelope = %CommandEnvelope{
      protocol_version: 1,
      game_id: state.game.id,
      command_id: command_id,
      expected_version: state.game.version,
      action: :system_deal
    }

    payload = %{
      "type" => "system_deal",
      "auction_starter" => auction_starter,
      "cards" => Enum.map(DeckOrder.cards(deck), &Card.to_id/1)
    }

    hash = payload_hash(payload)

    case Game.execute(state.game, {:deal, deck, auction_starter}) do
      {:ok, next, events} ->
        result = Message.accepted(next.id, command_id, next.version)

        case GameRepository.commit(
               state.game,
               next,
               events,
               "system",
               envelope,
               payload,
               hash,
               result
             ) do
          {:ok, outbox} ->
            :ok = OutboxPublisher.publish(outbox)
            {:reply, result, %{state | game: next}}

          {:error, reason} ->
            {:reply, Message.rejected(state.game.id, command_id, state.game.version, reason),
             state}
        end

      {:error, reason} ->
        {:reply, Message.rejected(state.game.id, command_id, state.game.version, reason), state}
    end
  end

  defp process_new_command(state, actor, envelope, command_payload, payload_hash) do
    game = state.game

    cond do
      envelope.expected_version != game.version ->
        reject_and_record(state, actor, envelope, command_payload, payload_hash, {
          :stale_game_version,
          game.version
        })

      true ->
        command = DomainCommand.from_action(envelope.action, actor.player_id)

        case Game.execute(game, command) do
          {:ok, next, events} ->
            result = Message.accepted(game.id, envelope.command_id, next.version)

            case GameRepository.commit(
                   game,
                   next,
                   events,
                   actor.player_id,
                   envelope,
                   command_payload,
                   payload_hash,
                   result
                 ) do
              {:ok, outbox} ->
                :ok = OutboxPublisher.publish(outbox)
                {:reply, result, %{state | game: next}}

              {:error, reason} ->
                recover_after_commit_error(state, envelope, reason)
            end

          {:error, reason} ->
            reject_and_record(state, actor, envelope, command_payload, payload_hash, reason)
        end
    end
  end

  defp reject_and_record(state, actor, envelope, command_payload, payload_hash, reason) do
    result = Message.rejected(state.game.id, envelope.command_id, state.game.version, reason)

    case GameRepository.record_rejection(
           state.game,
           actor.player_id,
           envelope,
           command_payload,
           payload_hash,
           result
         ) do
      {:ok, _record} -> {:reply, result, state}
      {:error, _changeset} -> {:reply, result, state}
    end
  end

  defp recover_after_commit_error(state, envelope, reason) do
    case GameRepository.load(state.game.id) do
      {:ok, recovered} ->
        result = Message.rejected(recovered.id, envelope.command_id, recovered.version, reason)
        {:reply, result, %{state | game: recovered}}

      {:error, _load_error} ->
        result = Message.rejected(state.game.id, envelope.command_id, state.game.version, reason)
        {:reply, result, state}
    end
  end

  defp duplicate_result(game, actor, envelope, payload_hash) do
    case GameRepository.processed_command(game.id, envelope.command_id) do
      nil ->
        :new

      processed
      when processed.actor_id == actor.player_id and processed.payload_hash == payload_hash ->
        {:duplicate, processed.result}

      _processed ->
        {:conflict,
         Message.rejected(game.id, envelope.command_id, game.version, :command_id_reused)}
    end
  end

  defp payload_hash(payload) do
    :crypto.hash(:sha256, Jason.encode!(payload)) |> Base.encode16(case: :lower)
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
