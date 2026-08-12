# Doudizhu

Authoritative three-player 斗地主 server built with Elixir, OTP, Phoenix Channels, and PostgreSQL.

The game is headless: humans, CLIs, bots, local sessions, and WebSocket clients all submit the same protocol-v1 commands through the same command gateway. Phoenix adapters contain no card-game rules.

## Implemented

- Complete Pagat/F# three-player domain model
- All standard combination families and configurable attachment/scoring rules
- Deterministic pure transition API
- Versioned JSON command, result, event, snapshot, and room messages
- Audience-specific projections that redact hidden cards server-side
- Wire-faithful in-memory sessions
- Phoenix socket authentication and Game/Room Channels
- One supervised `GameServer` per active game
- PostgreSQL snapshots, events, processed commands, controller leases, and outbox
- Optimistic game versions and durable command idempotency
- Process restart, reconnect, resynchronization, and controller replacement
- Friend rooms with three seats, invite codes, ready state, and secure shuffle
- Responsive browser UI for rooms, bidding, card play, reconnect, and settlement
- Headless Channel CLI
- Domain parity, property, schema, persistence, redaction, Channel, room, UI, and adapter-transcript tests

## Requirements

- Elixir 1.17 or newer
- PostgreSQL

Database settings use `PGUSER`, `PGPASSWORD`, `PGHOST`, and `PGPORT`. Defaults use the current OS user on `localhost:5432`.

## Setup

```sh
mix setup
mix test
mix phx.server
```

Health check:

```sh
curl http://localhost:4000/api/health
```

## Browser UI

Open [`http://localhost:4000`](http://localhost:4000), enter your name, and create a private table. Copy the generated invitation link to two friends. After all three players mark themselves ready, the room owner can start the game.

For local testing on one computer, use separate browser profiles/private contexts so each player has separate guest identity storage.

The browser is a Phoenix LiveView adapter over the same application boundary as the Channel and local clients. It constructs the same protocol-v1 command envelopes, dispatches through `CommandGateway`, subscribes to the same audience-specific projections, and does not classify cards or decide whether moves are legal. LiveView owns transient presentation state such as selected cards and replay playback; the durable game remains authoritative.

Use the language selector in the header to switch between English and Simplified Chinese. The preference is saved in a browser cookie, while an explicit `?locale=zh_Hans` query or the browser's `Accept-Language` header can select the initial locale. UI translations use Phoenix Gettext and live under `priv/gettext/`; after changing translatable source strings, run `mix gettext.extract --merge` and update the locale PO files.

### Replaying a recorded game

From the home screen, click **Replay a game**. Games associated with the guest identity stored in that browser are listed newest first, and any completed game can be opened directly with its public game ID. Replay links use `/?replay=<game_id>`.

A replay includes step backward/forward, a timeline slider, autoplay, all three historical hands, bottom cards, public events, and final settlement. Full-information replay is available only after completion, preventing it from leaking cards during a live game.

The server reconstructs the game from its original shuffled deck and accepted command history and checks that replay reaches the persisted final state. Completed replays are public to anyone possessing the high-entropy game ID; game IDs should therefore be shared intentionally.

## Quick three-terminal demo

Keep `mix phx.server` running. In another terminal, create and deal a development game:

```sh
mix doudizhu.demo
```

The task prints three complete commands—one each for Alice, Bob, and Chen. Open three terminals in `ex-doudizhu/`, paste one command into each, and bid/play with the CLI commands shown by the task. Alice starts the auction.

## Architecture

```text
protocol-v1 command envelope
  -> Protocol.Decoder
  -> Sessions.CommandGateway
  -> controller lease + authorization
  -> expected-version + command-id checks
  -> Games.GameServer
  -> Domain.Game.execute/2
  -> PostgreSQL transaction
  -> public/private projection outbox
  -> PubSub
  -> LocalSession, Phoenix Channel, or LiveView delivery
```

The domain core under `lib/doudizhu/domain/` performs no I/O, random generation, clock access, process messaging, database access, or Phoenix calls.

Production randomness lives in `Doudizhu.Games.DeckFactory`; tests inject a complete `DeckOrder`.

### Shared command semantics

Headless clients, local wire-faithful sessions, and the LiveView browser adapter all use the same application path:

```text
protocol-v1 command envelope
  -> Protocol.Decoder
  -> Sessions.CommandGateway
  -> Games.GameServer
  -> Protocol.DomainCommand
  -> Domain.Game.execute/2
```

The UI may show or disable controls based on server-projected phase and turn data, but it never classifies cards or decides whether an action succeeds. The server remains authoritative.

Replay re-executes the recorded accepted commands without mutating the original game:

```text
recorded protocol-v1 JSON
  -> Protocol.Decoder
  -> Protocol.DomainCommand
  -> Domain.Game.execute/2 in isolated memory
  -> full-information replay projection
  -> canonical final-state verification
```

Replay therefore shares game-state semantics with live play while intentionally skipping connection leases, command deduplication, persistence, and broadcasting. Rejected commands and network retries are not replay frames because they did not change game state. Replay controls such as `frame`, seek, previous, next, and autoplay are playback controls—not domain game commands.

## Public Channel protocol

Socket URL:

```text
ws://localhost:4000/socket/websocket?vsn=2.0.0&token=SIGNED_TOKEN
```

Create a development token:

```sh
mix doudizhu.token guest-alice
```

### Friend rooms

Join `room:lobby`, then push:

```json
["create", {"player_name": "Alice"}]
```

The reply contains a `room_id` and one-time-display `invite_code`. Each friend joins `room:<room_id>` with:

```json
{"invite_code": "ABC12345", "player_name": "Bob"}
```

Push `ready` with `{"ready": true}`. The room owner pushes `start` after all three seats are ready. The resulting room snapshot contains `game_id`.

### Game join

Join `game:<game_id>` with the stable seated player ID:

```json
{"player_id": "guest-alice"}
```

The join reply contains that player's private snapshot. To spectate, join with:

```json
{"role": "spectator"}
```

Spectators receive only public projections and cannot command.

### Commands

Push all game commands under the Channel event `command`:

```json
{
  "protocol_version": 1,
  "kind": "command",
  "game_id": "game-example",
  "command_id": "globally-unique-command-id",
  "expected_version": 42,
  "action": {
    "type": "play_cards",
    "cards": ["C3", "D3", "H3", "C4"]
  }
}
```

Actions:

```json
{"type": "place_bid", "bid": 1}
{"type": "auction_pass"}
{"type": "play_cards", "cards": ["S10"]}
{"type": "play_pass"}
```

Card IDs use suit prefixes `C`, `D`, `H`, and `S`; ranks are `3` through `10`, `J`, `Q`, `K`, `A`, and `2`. Jokers are `JOKER_SMALL` and `JOKER_BIG`.

Push `resync` with `{}` to receive a fresh audience-specific snapshot. Clients should resynchronize when they detect a sequence gap.

Protocol schemas and examples are in [`priv/protocol/v1/`](priv/protocol/v1/).

## Headless CLI

After obtaining a token and game/player ID:

```sh
DOUDIZHU_TOKEN='...' node clients/channel_cli.mjs \
  --game game_id \
  --player player_id
```

Interactive commands:

```text
bid 1
auction-pass
play C3 D3 H3
pass
snapshot
quit
```

The script uses the Phoenix v2 Channel wire format and prints every observation as one JSON line. A bot can use exactly the same protocol.

## Local wire-faithful controller

`Doudizhu.Sessions.LocalSession` accepts the same JSON-compatible command envelope, forces a JSON encode/decode boundary, dispatches through `CommandGateway`, and receives the same projected outbox messages as a Channel. It is intended for local multiplayer, bots, and transport-conformance tests.

Pure unit tests and high-volume simulations may call:

```elixir
Doudizhu.Domain.Game.execute(game, command)
```

That direct path intentionally does not claim transport equivalence.

## Persistence and recovery

An accepted transition atomically:

1. compare-and-swaps the stored game version;
2. stores the versioned private snapshot;
3. appends internal event records;
4. records the command ID, canonical payload, hash, and result;
5. writes public and player-private outbox messages;
6. commits before publication.

A repeated command ID with the same actor and payload returns its original result. Reusing it with another payload is rejected. A restarted `GameServer` loads the explicit JSON-compatible snapshot codec rather than an opaque Erlang term.

`Doudizhu.Replays` independently reconstructs recorded games from the private system deal and accepted `processed_commands`. It refuses playback if reconstruction diverges from the canonical persisted snapshot.

## Tests

```sh
mix test
mix test test/doudizhu/domain
mix test test/doudizhu/sessions/adapter_parity_test.exs
mix test test/doudizhu_web/channels
mix test test/doudizhu_web/game_live_test.exs
mix precommit
```

Tests use PostgreSQL's Ecto SQL Sandbox and require no public internet or real players. The adapter parity test runs the same deterministic deal and command through local and Channel transports and compares canonical semantic transcripts.

## Reference model

The F# executable specification remains in [`../fs-doudizhu/`](../fs-doudizhu/). Its combination, auction, play, and scoring scenarios were ported to ExUnit.
