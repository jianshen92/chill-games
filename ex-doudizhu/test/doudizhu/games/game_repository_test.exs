defmodule Doudizhu.Games.GameRepositoryTest do
  use Doudizhu.DataCase, async: false

  alias Doudizhu.Domain.Game
  alias Doudizhu.Games.{GameRepository, OutboxMessage, OutboxPublisher}
  alias Doudizhu.Protocol.{CommandEnvelope, Message}
  import Doudizhu.DomainHelpers

  test "optimistic version check prevents a second writer" do
    game = new_game("repository-version-game")
    {:ok, ^game} = GameRepository.create(game)
    {:ok, next, events} = Game.execute(game, {:deal, standard_deck(), first_id()})

    envelope = envelope(game.id, "writer-1", 0)
    payload = %{"type" => "test-deal"}
    hash = hash(payload)
    result = Message.accepted(game.id, envelope.command_id, next.version)

    assert {:ok, _outbox} =
             GameRepository.commit(
               game,
               next,
               events,
               first_id(),
               envelope,
               payload,
               hash,
               result
             )

    second = envelope(game.id, "writer-2", 0)

    assert {:error, {:version_conflict, 0}} =
             GameRepository.commit(
               game,
               next,
               events,
               first_id(),
               second,
               payload,
               hash,
               Message.accepted(game.id, second.command_id, next.version)
             )
  end

  test "drain publishes and marks an outbox record left by a crash" do
    game = new_game("repository-outbox-game")
    {:ok, ^game} = GameRepository.create(game)
    :ok = Phoenix.PubSub.subscribe(Doudizhu.PubSub, OutboxPublisher.public_topic(game.id))

    payload = %{
      "protocol_version" => 1,
      "kind" => "game_event",
      "game_id" => game.id,
      "sequence" => 1,
      "event_index" => 0,
      "event" => %{"type" => "test_event"}
    }

    {:ok, message} =
      %OutboxMessage{}
      |> OutboxMessage.changeset(%{
        game_id: game.id,
        sequence: 1,
        audience_kind: "public",
        payload: payload,
        attempts: 0
      })
      |> Repo.insert()

    assert :ok = OutboxPublisher.drain()
    assert_receive {:game_message, ^payload}

    published = Repo.get!(OutboxMessage, message.id)
    assert published.attempts == 1
    assert published.published_at
  end

  defp envelope(game_id, command_id, expected_version) do
    %CommandEnvelope{
      protocol_version: 1,
      game_id: game_id,
      command_id: command_id,
      expected_version: expected_version,
      action: :system_deal
    }
  end

  defp hash(payload),
    do: :crypto.hash(:sha256, Jason.encode!(payload)) |> Base.encode16(case: :lower)
end
