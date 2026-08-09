defmodule Mix.Tasks.Doudizhu.Demo do
  use Mix.Task

  alias Doudizhu.Domain.{Game, Player, Players, RuleSet}
  alias Doudizhu.Games.{DeckFactory, GameRepository, GameServer, GameSupervisor}
  alias DoudizhuWeb.SessionToken

  @shortdoc "Creates a dealt three-player development game and prints CLI commands"

  @impl Mix.Task
  def run(_args) do
    Logger.configure(level: :warning)
    Mix.Task.run("app.start")

    game_id = "game_demo_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    players = players!()
    {:ok, game} = Game.new(game_id, players, RuleSet.standard_three_player())
    {:ok, _game} = GameRepository.create(game)
    {:ok, _server} = GameSupervisor.start_game(game_id)

    result = GameServer.deal(game_id, DeckFactory.random(), "alice")

    if result["status"] != "accepted" do
      Mix.raise("could not deal demo game: #{inspect(result)}")
    end

    Mix.shell().info("""

    Demo game created and dealt.

    GAME_ID=#{game_id}

    Open three terminals from ex-doudizhu/ and run one command in each:

    Alice:
    #{client_command(game_id, "alice")}

    Bob:
    #{client_command(game_id, "bob")}

    Chen:
    #{client_command(game_id, "chen")}

    Auction starts with Alice. CLI commands are:
      bid 1|2|3
      auction-pass
      play CARD...
      pass
      snapshot
      quit
    """)
  end

  defp players! do
    {:ok, alice} = Player.new("alice", "Alice")
    {:ok, bob} = Player.new("bob", "Bob")
    {:ok, chen} = Player.new("chen", "Chen")
    {:ok, players} = Players.new(alice, bob, chen)
    players
  end

  defp client_command(game_id, player_id) do
    token = SessionToken.sign(player_id)

    "DOUDIZHU_TOKEN='#{token}' node clients/channel_cli.mjs " <>
      "--game '#{game_id}' --player '#{player_id}'"
  end
end
