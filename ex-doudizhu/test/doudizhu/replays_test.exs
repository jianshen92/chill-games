defmodule Doudizhu.ReplaysTest do
  use Doudizhu.DataCase, async: false

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor, OutboxMessage}
  alias Doudizhu.Replays
  alias Doudizhu.Sessions.LocalSession
  import Doudizhu.DomainHelpers

  setup do
    game_id = "replay-game-#{System.unique_integer([:positive])}"

    winning_hand =
      triple(:three) ++
        triple(:four) ++
        triple(:five) ++
        triple(:six) ++ pair(:seven) ++ pair(:eight) ++ pair(:nine) ++ pair(:ten)

    game = new_game(game_id)
    {:ok, ^game} = GameRepository.create(game)
    {:ok, server} = GameSupervisor.start_game(game_id)
    GameServer.deal(game_id, deck_with_first_landlord_hand(winning_hand), first_id())

    session =
      start_supervised!(
        {LocalSession,
         owner: self(),
         identity_id: first_id(),
         game_id: game_id,
         player_id: first_id(),
         session_id: "replay-test-session"}
      )

    assert_receive {:local_message, ^session, %{"kind" => "snapshot", "sequence" => 1}}

    assert LocalSession.command(
             session,
             command(game_id, "bid-three", 1, %{"type" => "place_bid", "bid" => 3})
           )[
             "status"
           ] == "accepted"

    play = %{"type" => "play_cards", "cards" => Enum.map(winning_hand, &Card.to_id/1)}

    assert LocalSession.command(session, command(game_id, "winning-play", 2, play))["status"] ==
             "accepted"

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
        [] -> :ok
      end
    end)

    %{game_id: game_id, server: server}
  end

  test "re-executes the private deal and accepted commands to the persisted final state", %{
    game_id: game_id
  } do
    assert {:ok, replay} = Replays.open(game_id)
    assert replay.metadata["status"] == "finished"
    assert replay.metadata["frame_count"] == 4
    assert replay.final_game == GameServer.game(game_id)

    assert {:ok, first_frame} = Replays.frame(replay, 0)
    assert first_frame["snapshot"]["game"]["phase"] == "awaiting_deal"
    assert Enum.all?(first_frame["snapshot"]["hands"], fn {_player_id, hand} -> hand == [] end)

    assert {:ok, deal_frame} = Replays.frame(replay, 1)

    opponent_cards =
      game_id
      |> GameServer.game()
      |> hand_cards(second_id())
      |> Enum.map(&Card.to_id/1)

    assert map_size(deal_frame["snapshot"]["hands"]) == 3
    assert length(deal_frame["snapshot"]["bottom_cards"]) == 3
    assert Enum.all?(opponent_cards, &String.contains?(Jason.encode!(deal_frame), ~s("#{&1}")))

    assert {:ok, final_frame} = Replays.frame(replay, 3)
    assert final_frame["snapshot"]["game"]["phase"] == "finished"
    assert final_frame["snapshot"]["hands"][first_id()] == []
    assert length(final_frame["history"]) == 5
  end

  test "live and replay paths produce the same semantic state at every accepted version", %{
    game_id: game_id
  } do
    {:ok, replay} = Replays.open(game_id)
    player_id = first_id()

    live_snapshots =
      Repo.all(
        from message in OutboxMessage,
          where:
            message.game_id == ^game_id and message.audience_kind == "player" and
              message.audience_id == ^player_id,
          order_by: [asc: message.sequence],
          select: message.payload
      )

    replay_frames = Enum.drop(replay.frames, 1)
    assert length(live_snapshots) == length(replay_frames)

    Enum.zip(live_snapshots, replay_frames)
    |> Enum.each(fn {live, replay_frame} ->
      replay_snapshot = replay_frame["snapshot"]
      assert replay_snapshot["sequence"] == live["sequence"]
      assert replay_snapshot["game"] == live["game"]
      assert replay_snapshot["hands"][player_id] == live["you"]["hand"]
    end)
  end

  test "lists a participant's games but permits direct public access by game ID", %{
    game_id: game_id
  } do
    assert Enum.any?(Replays.list_for_identity(first_id()), &(&1["game_id"] == game_id))
    refute Enum.any?(Replays.list_for_identity("intruder"), &(&1["game_id"] == game_id))
    assert {:ok, replay} = Replays.open(game_id)
    assert replay.metadata["public_replay_id"] == game_id
  end

  test "in-progress games cannot expose their hands" do
    game = new_game("unfinished-replay-game")
    assert {:ok, ^game} = GameRepository.create(game)
    assert Replays.open(game.id) == {:error, :replay_not_finished}
  end

  test "invalid frame indexes are rejected", %{game_id: game_id} do
    {:ok, replay} = Replays.open(game_id)
    assert Replays.frame(replay, -1) == {:error, :frame_not_found}
    assert Replays.frame(replay, 99) == {:error, :frame_not_found}
  end

  defp command(game_id, command_id, expected_version, action) do
    %{
      "protocol_version" => 1,
      "kind" => "command",
      "game_id" => game_id,
      "command_id" => command_id,
      "expected_version" => expected_version,
      "action" => action
    }
  end
end
