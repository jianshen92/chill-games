defmodule DoudizhuWeb.GameLiveTest do
  use DoudizhuWeb.ConnCase, async: false

  alias Doudizhu.Domain.Card
  alias Doudizhu.Games.{GameRepository, GameServer, GameSupervisor}
  alias Doudizhu.Repo
  alias Doudizhu.Rooms.Room
  alias Doudizhu.Sessions.LocalSession
  alias DoudizhuWeb.Gettext, as: GettextBackend
  alias DoudizhuWeb.{GameLiveHTML, Locale, SessionToken}

  import Doudizhu.DomainHelpers

  test "GET / serves the LiveView game UI and establishes a browser identity", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "斗地主"
    assert html =~ "Replay a game"
    assert html =~ ~s(data-phx-main)
    assert html =~ ~s(src="/assets/doudizhu_live.js")
    assert String.starts_with?(get_session(conn, :identity_id), "guest_")
    assert get_resp_header(conn, "content-security-policy") != []
  end

  test "browser locale is negotiated from the request and stored in the session", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept-language", "zh-CN,zh;q=0.9,en;q=0.8")
      |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ ~s(<html lang="zh-Hans">)
    assert html =~ "创建私人牌桌"
    assert html =~ "回放牌局"
    assert get_session(conn, :locale) == "zh_Hans"
  end

  test "LiveView changes locale reactively", %{conn: conn} do
    conn = init_test_session(conn, %{identity_id: "guest-live-locale", locale: "en"})
    {:ok, view, _html} = live(conn, ~p"/")

    redirect =
      view
      |> form("#locale-form", %{locale: "zh_Hans"})
      |> render_change()

    assert {:error, {:live_redirect, %{to: "/?locale=zh_Hans"}}} = redirect
    assert_push_event view, "store-locale", %{locale: "zh_Hans", language_tag: "zh-Hans"}
    {:ok, view, _html} = follow_redirect(redirect, conn)

    assert has_element?(view, "#welcome-panel", "创建私人牌桌")
    assert has_element?(view, "#locale-select option[value='zh_Hans'][selected]")

    view
    |> form("#welcome-form", %{name: "   "})
    |> render_submit()

    assert has_element?(view, "#welcome-error", "请输入名字以继续。")
  end

  test "Simplified Chinese translations preserve interpolation and plurals" do
    Gettext.with_locale(GettextBackend, "zh_Hans", fn ->
      assert GameLiveHTML.card_count(3) == "3 张牌"

      assert GameLiveHTML.event_description(
               %{"type" => "bid_placed", "player_id" => "alice", "bid" => 2},
               [
                 %{"player_id" => "alice", "name" => "小明"}
               ]
             ) == "小明 叫了 2 分。"

      assert Gettext.pgettext(GettextBackend, "readiness status", "Not ready") == "未准备"
      assert Gettext.pgettext(GettextBackend, "readiness action", "Not ready") == "取消准备"
      assert Gettext.pgettext(GettextBackend, "replay control", "Play") == "播放"
      assert Locale.normalize("zh-CN") == "zh_Hans"
    end)
  end

  test "LiveView reactively creates a room and updates readiness", %{conn: conn} do
    identity_id = "guest-live-alice"
    conn = init_test_session(conn, %{identity_id: identity_id})
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#welcome-form", %{name: " Alice "})
    |> render_submit()

    room = Repo.one!(Room)
    assert has_element?(view, "#room-panel")
    assert has_element?(view, "#seat-list", "Alice")
    assert has_element?(view, "#invite-code")

    assert has_element?(
             view,
             "#copy-invite-button[data-copy-success][data-copy-failure]"
           )

    view |> element("#ready-button") |> render_click()
    _html = render(view)

    assert has_element?(view, "#ready-button", "Not ready")

    assert Enum.find(Doudizhu.Rooms.snapshot(room.id)["seats"], &(&1["player_id"] == identity_id))[
             "ready"
           ]
  end

  test "LiveView renders projections and sends protocol commands through the shared gateway", %{
    conn: conn
  } do
    {:ok, %{room: room, invite_code: invite_code}} = Doudizhu.Rooms.create(first_id(), "Alice")
    {:ok, _seat} = Doudizhu.Rooms.join(room.id, invite_code, second_id(), "Bob")
    {:ok, _seat} = Doudizhu.Rooms.join(room.id, invite_code, third_id(), "Chen")

    for identity_id <- [first_id(), second_id(), third_id()] do
      {:ok, _seat} = Doudizhu.Rooms.set_ready(room.id, identity_id, true)
    end

    {:ok, started_room} = Doudizhu.Rooms.start_game(room.id, first_id())
    game_id = started_room["game_id"]

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
        [] -> :ok
      end
    end)

    conn = init_test_session(conn, %{identity_id: first_id()})
    {:ok, view, _html} = live(conn, ~p"/?room=#{room.id}&invite=#{invite_code}")

    assert has_element?(view, "#game-panel")
    assert has_element?(view, "#game-panel[data-audio-player-ids]")
    assert has_element?(view, "#phase-title", "Call the landlord")
    assert has_element?(view, "#table-panel[phx-hook='CardSelection']")
    assert has_element?(view, "#hand .card[data-card-id]")
    refute has_element?(view, "#hand .card[phx-click]")

    view
    |> element("#bid-controls button[phx-value-bid='3']")
    |> render_click()

    _html = render(view)
    assert GameServer.game(game_id).version == 2
    assert has_element?(view, "#version-label", "Turn 2")
    assert has_element?(view, "#event-log", "Alice bid 3.")
    assert_push_event view, "game-audio", %{event: %{"type" => "bid_placed", "bid" => 3}}

    card_id =
      game_id
      |> GameServer.game()
      |> hand_cards(first_id())
      |> List.first()
      |> Card.to_id()

    view
    |> element("#table-panel")
    |> render_hook("play-selected", %{"cards" => [card_id]})

    _html = render(view)
    assert GameServer.game(game_id).version == 3
    assert has_element?(view, "#version-label", "Turn 3")

    assert_push_event view, "game-audio", %{
      event: %{"type" => "cards_played", "combination" => %{"type" => "single"}}
    }
  end

  test "LiveView provides reactive completed-game replay controls", %{conn: conn} do
    game_id = "live-replay-#{System.unique_integer([:positive])}"

    winning_hand =
      triple(:three) ++
        triple(:four) ++
        triple(:five) ++
        triple(:six) ++ pair(:seven) ++ pair(:eight) ++ pair(:nine) ++ pair(:ten)

    game = new_game(game_id)
    {:ok, ^game} = GameRepository.create(game)
    {:ok, _server} = GameSupervisor.start_game(game_id)
    GameServer.deal(game_id, deck_with_first_landlord_hand(winning_hand), first_id())

    session =
      start_supervised!(
        {LocalSession,
         owner: self(),
         identity_id: first_id(),
         game_id: game_id,
         player_id: first_id(),
         session_id: "live-replay-session"}
      )

    assert_receive {:local_message, ^session, %{"kind" => "snapshot", "sequence" => 1}}

    assert LocalSession.command(
             session,
             command(game_id, "live-replay-bid", 1, %{"type" => "place_bid", "bid" => 3})
           )["status"] == "accepted"

    assert LocalSession.command(
             session,
             command(game_id, "live-replay-win", 2, %{
               "type" => "play_cards",
               "cards" => Enum.map(winning_hand, &Card.to_id/1)
             })
           )["status"] == "accepted"

    on_exit(fn ->
      case Registry.lookup(Doudizhu.Games.Registry, game_id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(GameSupervisor, pid)
        [] -> :ok
      end
    end)

    conn = init_test_session(conn, %{identity_id: first_id()})
    {:ok, view, _html} = live(conn, ~p"/?replay=#{game_id}")

    assert has_element?(view, "#replay-controls")
    assert has_element?(view, "#replay-hands .replay-hand")
    assert has_element?(view, "#replay-position", "Step 1 of 4")
    assert has_element?(view, "#replay-seek-form[phx-hook='ReplaySeek']")
    refute has_element?(view, "#replay-seek-form[phx-change]")

    view |> element("button[phx-click='next-replay-frame']") |> render_click()
    assert has_element?(view, "#replay-position", "Step 2 of 4")
  end

  test "LiveView validates player names", %{conn: conn} do
    conn = init_test_session(conn, %{identity_id: "guest-live-validation"})
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#welcome-form", %{name: "   "})
    |> render_submit()

    assert has_element?(view, "#welcome-error", "Enter a name to continue.")
  end

  test "browser assets are served", %{conn: conn} do
    conn = get(conn, "/assets/doudizhu_live.js")
    assert response(conn, 200) =~ "LiveSocket"

    conn =
      Phoenix.ConnTest.build_conn() |> get("/vendor/phoenix_live_view/phoenix_live_view.min.js")

    assert response(conn, 200) =~ "LiveView"
  end

  test "gameplay audio manifest and clips are served", %{conn: conn} do
    conn = get(conn, "/audio/gameplay/manifest.json")
    manifest = json_response(conn, 200)

    assert manifest["pack"]["id"] == "mandarin-qwen3-three-personas"
    assert manifest["player_voice_assignment"]["personas"] == ~w(serena ethan xiaowan)
    assert manifest["events"]["cards_played"]["variants"]["rocket"]["text"] == "王炸！"

    conn =
      Phoenix.ConnTest.build_conn()
      |> get("/audio/gameplay/personas/serena/rocket.mp3")

    assert byte_size(response(conn, 200)) > 100
    assert get_resp_header(conn, "content-type") == ["audio/mpeg"]
  end

  test "POST /api/guest-session returns a signed opaque identity", %{conn: conn} do
    conn = post(conn, ~p"/api/guest-session", %{name: " Alice "})
    payload = json_response(conn, 200)

    assert payload["name"] == "Alice"
    assert String.starts_with?(payload["identity_id"], "guest_")
    assert {:ok, identity_id} = SessionToken.verify(payload["token"])
    assert identity_id == payload["identity_id"]
  end

  test "guest names are validated", %{conn: conn} do
    conn = post(conn, ~p"/api/guest-session", %{name: "   "})
    assert json_response(conn, 422) == %{"error" => %{"code" => "name_required"}}
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
