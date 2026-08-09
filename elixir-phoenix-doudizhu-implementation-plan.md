# Elixir/Phoenix 斗地主 Implementation Plan

## Status

Executed. The Elixir/Phoenix application is implemented in [`ex-doudizhu/`](ex-doudizhu/) with domain, protocol, persistence, OTP, local transport, Phoenix Channels, friend rooms, a responsive browser UI, a headless client, deployment artifacts, and automated tests.

The existing F# implementation in [`fs-doudizhu/`](fs-doudizhu/) remains the executable rules reference for the Elixir port.

---

## 1. Objectives

Build an authoritative three-player 斗地主 game that:

1. allows friends to play over the internet;
2. supports human, CLI, and programmatic players through the same abstraction;
3. is fully playable without a graphical UI;
4. uses versioned JSON commands and observations;
5. behaves identically when played locally or through Phoenix Channels;
6. can be tested deterministically without an internet connection;
7. preserves hidden information correctly during live games;
8. survives reconnects and server-process restarts;
9. keeps the game rules independent of Phoenix, storage, and transport concerns.

The core architectural constraint is:

> Every playable mode enters through the same protocol, session, command, and projection boundaries. Only the final transport adapter differs.

---

## 2. Non-goals for the first playable version

The first version will not attempt to provide:

- four-player or regional 斗地主 variants;
- ranked matchmaking;
- real-money gambling or wallet integration;
- distributed multi-region game processes;
- anti-collusion analysis;
- a sophisticated graphical interface;
- voice, video, or chat;
- an AI strategy engine;
- blockchain or cryptographic card dealing;
- event sourcing as a goal in itself.

The architecture should leave room for these concerns without adding them prematurely.

---

## 3. Normative game rules

The Elixir implementation will initially reproduce the rule profile documented by the F# project:

- three players;
- one 54-card deck;
- 17 cards per player and three bottom cards;
- ascending bids of 1, 2, and 3;
- bidding continues until two consecutive passes follow the highest bid;
- three initial passes void the deal;
- the landlord receives the bottom cards and leads;
- standard singles, pairs, triples, attached triples, sequences, airplanes, bombs, rocket, and four-with-attachments combinations;
- two passes clear the current lead;
- the first empty hand ends the game;
- bombs and rocket multiply settlement;
- landlord spring and farmer anti-spring are supported.

Variant-sensitive attachment rules must remain explicit in a `RuleSet`. They must not be scattered through channel handlers or UI code.

The F# tests are the behavioral baseline. Any intentional discrepancy must be written down as a rule decision before changing either implementation.

---

## 4. Architectural principles

### 4.1 Functional core, stateful shell

The domain core is deterministic:

```text
state + command -> accepted(new state, events) | rejected(error)
```

The shell supplies:

- authenticated actor identity;
- shuffled deck order;
- generated IDs;
- current game version;
- persistence;
- timers;
- broadcasting;
- JSON encoding and decoding.

### 4.2 The transport never implements game behavior

Neither a Phoenix Channel nor an in-memory adapter may decide:

- whether it is a player's turn;
- whether a combination is legal;
- whether cards beat the current lead;
- whether bidding has ended;
- whether a player has won;
- how settlement is calculated.

Transport adapters decode, authenticate, dispatch, and deliver messages.

### 4.3 Player, controller, and connection are different

- **Player:** stable domain identity occupying a game seat.
- **Controller:** human UI, CLI, bot, or program acting for the player.
- **Connection:** temporary local session or WebSocket connection used by a controller.

A disconnect destroys a connection, not the player or seat.

### 4.4 The server is authoritative

Clients submit physical card IDs and desired actions. They do not submit trusted combination types, roles, scores, turn numbers, or outcomes.

### 4.5 Hidden information is projected, not merely filtered by clients

During live games, the server creates separate public and player-private observations; full internal state is never broadcast to a live public topic. After settlement, the replay layer deliberately exposes reconstructed all-hands review frames by high-entropy game ID.

### 4.6 Local/wire parity is tested explicitly

Identical scenarios run through the in-memory and Phoenix Channel adapters. Their canonical semantic transcripts must match.

---

## 5. Proposed technology choices

Use a single standard Phoenix application rather than an umbrella initially.

Expected components:

- Elixir and OTP;
- Phoenix Endpoint and Channels;
- Phoenix PubSub;
- Phoenix Presence for connection presence only;
- Ecto with PostgreSQL;
- Jason for JSON;
- ExUnit;
- StreamData for selected property-based tests;
- Bandit or the current Phoenix default HTTP server;
- Telemetry for metrics and tracing.

Do not introduce Broadway, GenStage, Horde, or another distributed-process library in the first version. A turn-based card game has low per-game throughput; correctness, isolation, and recovery matter more than pipeline throughput.

Phoenix LiveView may be added as a UI adapter later. LiveView streams must not become the game event protocol.

The intended future directory is:

```text
ex-doudizhu/
```

The F# reference remains isolated in:

```text
fs-doudizhu/
```

---

## 6. Target module structure

A likely structure is:

```text
ex-doudizhu/
├── lib/
│   ├── doudizhu/
│   │   ├── domain/
│   │   │   ├── player.ex
│   │   │   ├── card.ex
│   │   │   ├── deck.ex
│   │   │   ├── hand.ex
│   │   │   ├── rule_set.ex
│   │   │   ├── combination.ex
│   │   │   ├── combination_classifier.ex
│   │   │   ├── bidding.ex
│   │   │   ├── playing.ex
│   │   │   ├── settlement.ex
│   │   │   ├── command.ex
│   │   │   ├── event.ex
│   │   │   └── game.ex
│   │   ├── protocol/
│   │   │   ├── decoder.ex
│   │   │   ├── encoder.ex
│   │   │   ├── command_envelope.ex
│   │   │   ├── message_envelope.ex
│   │   │   ├── card_codec.ex
│   │   │   └── error_code.ex
│   │   ├── sessions/
│   │   │   ├── actor_context.ex
│   │   │   ├── command_gateway.ex
│   │   │   ├── controller_lease.ex
│   │   │   └── local_session.ex
│   │   ├── games/
│   │   │   ├── game_server.ex
│   │   │   ├── game_supervisor.ex
│   │   │   ├── game_registry.ex
│   │   │   ├── game_repository.ex
│   │   │   └── recovery.ex
│   │   ├── projections/
│   │   │   ├── public_projection.ex
│   │   │   ├── player_projection.ex
│   │   │   └── snapshot.ex
│   │   ├── rooms/
│   │   │   ├── room.ex
│   │   │   ├── room_server.ex
│   │   │   └── invitations.ex
│   │   └── bots/
│   │       ├── controller.ex
│   │       └── local_runner.ex
│   └── doudizhu_web/
│       ├── channels/
│       │   ├── game_channel.ex
│       │   └── room_channel.ex
│       ├── user_socket.ex
│       └── endpoint.ex
├── priv/
│   ├── protocol/v1/
│   │   ├── command.schema.json
│   │   ├── message.schema.json
│   │   └── examples/
│   └── repo/migrations/
└── test/
    ├── doudizhu/domain/
    ├── doudizhu/protocol/
    ├── doudizhu/sessions/
    ├── doudizhu/games/
    ├── doudizhu_web/channels/
    ├── fixtures/
    └── support/
```

This is a planning map, not a requirement to create one file for every type. Modules should be merged when separation adds no clarity.

---

## 7. Domain model port

### 7.1 Domain values

Port the following concepts from F#:

- `GameId`;
- `PlayerId`;
- `PlayerName`;
- exactly three ordered players/seats;
- `Suit`;
- `StandardRank`;
- `Joker`;
- physical `Card`;
- immutable `Hand`;
- validated `DeckOrder`;
- `RuleSet`;
- `Bid` and `BidAction`;
- `Combination` and `CombinationKind`;
- game phase states;
- commands, events, domain errors, and settlement.

Use constructors returning `{:ok, value}` or `{:error, reason}` for constrained values. Mark important domain types as `@opaque` where useful, while recognizing that Elixir cannot enforce constructor privacy as strongly as F#.

### 7.2 Phase model

Represent phases with separate structs and pattern matching rather than a record containing flags and optional fields:

```text
%Game{state: %AwaitingDeal{}}
%Game{state: %Bidding{}}
%Game{state: %Playing{}}
%Game{state: %Finished{}}
```

Phase-specific functions must reject commands for other phases.

### 7.3 Card model

A card must retain physical identity:

```text
standard card = suit + rank
joker card    = small | big
```

Suits do not influence strength but distinguish the four physical standard cards of each rank.

Define a stable canonical card order for:

- deterministic snapshots;
- transcript comparison;
- JSON encoding;
- test fixtures.

### 7.4 Combination classifier

Port every F# combination classification and comparison test before integrating Phoenix.

The classifier should:

- reject empty selections;
- reject duplicate physical cards;
- group selected cards by rank;
- classify one legal combination or reject it;
- preserve the selected physical cards;
- expose main rank and shape;
- compare only already-classified combinations.

The server derives combination information from cards. Client-supplied classification metadata is informational at most and must never be trusted.

### 7.5 Pure transition API

Aim for an API shaped like:

```elixir
@spec execute(Game.t(), Command.t()) ::
        {:ok, Game.t(), [Event.t()]}
        | {:error, DomainError.t()}
```

A rejection must not mutate state or increment the game version.

The pure domain version may be represented separately from the persisted aggregate version if necessary, but one authoritative monotonic game version is preferable.

### 7.6 Deterministic dependencies

The domain must not call:

- random-number functions;
- `System.system_time/0`;
- UUID generators;
- database functions;
- Phoenix PubSub;
- process messaging.

Supply deck orders, IDs, deadlines, and timeout commands explicitly.

---

## 8. Protocol design

### 8.1 Versioned semantic protocol

All external messages include a protocol version:

```json
{
  "protocol_version": 1,
  "kind": "command"
}
```

Store JSON Schemas under `priv/protocol/v1/`. Treat schemas, examples, stable error codes, and transcript fixtures as part of the public API.

### 8.2 Command envelope

Proposed shape:

```json
{
  "protocol_version": 1,
  "kind": "command",
  "game_id": "game-123",
  "command_id": "01HT...",
  "expected_version": 42,
  "action": {
    "type": "play_cards",
    "cards": ["C3", "D3", "H3", "C4"]
  }
}
```

Required properties:

- `command_id` is unique per controller command;
- `expected_version` detects stale observations;
- actor/player identity is obtained from the authenticated session, not trusted from the body;
- card IDs use one documented canonical representation;
- unknown or malformed actions are protocol errors, not domain errors.

Player actions:

- `place_bid`;
- auction `pass`;
- `play_cards`;
- playing `pass`.

System actions remain internal:

- deal a validated deck;
- expire a turn;
- cancel or recover a game.

### 8.3 Command result

Accepted:

```json
{
  "protocol_version": 1,
  "kind": "command_result",
  "command_id": "01HT...",
  "status": "accepted",
  "game_version": 43
}
```

Rejected:

```json
{
  "protocol_version": 1,
  "kind": "command_result",
  "command_id": "01HT...",
  "status": "rejected",
  "game_version": 42,
  "error": {
    "code": "does_not_beat_current_lead"
  }
}
```

Error codes must be stable and machine-readable. Localized human text is a presentation concern.

### 8.4 Stream messages

Public event example:

```json
{
  "protocol_version": 1,
  "kind": "game_event",
  "game_id": "game-123",
  "sequence": 43,
  "event": {
    "type": "cards_played",
    "player_id": "player-1",
    "cards": ["C3", "D3", "H3", "C4"],
    "combination": {
      "type": "triple_with_single",
      "main_rank": "3"
    }
  }
}
```

Player-private snapshot example:

```json
{
  "protocol_version": 1,
  "kind": "snapshot",
  "game_id": "game-123",
  "sequence": 43,
  "you": {
    "player_id": "player-2",
    "role": "farmer",
    "hand": ["C5", "D5", "H7"]
  },
  "game": {
    "phase": "playing",
    "current_player": "player-2",
    "landlord": "player-1",
    "hand_counts": {
      "player-1": 14,
      "player-2": 3,
      "player-3": 11
    }
  }
}
```

### 8.5 Message ordering

Every committed transition receives a monotonically increasing sequence/version.

Clients must use sequence numbers rather than packet arrival timing to determine order. A detected gap triggers snapshot resynchronization.

The initiating client may receive a command result and stream event close together. The game sequence is authoritative even if transport scheduling changes their arrival order.

### 8.6 Compatibility policy

For protocol version 1:

- required fields cannot change meaning;
- error codes remain stable;
- additive optional fields are permitted;
- unknown optional fields should generally be ignored by clients;
- breaking changes require a new protocol version;
- decoded maps, not textual JSON object key order, are used for equality tests.

---

## 9. Local and wire equivalence

### 9.1 Shared path

Both transports must call the same application boundary:

```text
Protocol.Decoder
    -> CommandGateway
    -> authorization
    -> idempotency/version check
    -> GameServer
    -> Domain.Game.execute
    -> persistence
    -> Projection
    -> Protocol.Encoder
```

### 9.2 In-memory playable transport

`LocalSession` should:

- accept the same JSON-compatible command maps as the channel;
- pass them through the same decoder;
- provide the same authenticated `ActorContext` shape;
- call the same `CommandGateway`;
- receive messages from the same projection functions;
- encode and decode messages with the production protocol codec in wire-faithful mode.

This is the default local multiplayer and integration-test path.

### 9.3 Direct simulation mode

A separate fast simulator may call pure domain functions with Elixir structs for:

- unit tests;
- property tests;
- exhaustive rule exploration;
- high-volume bot training.

It must not be described as a transport-equivalence test. It deliberately bypasses protocol, authorization, persistence, and projection concerns.

### 9.4 Adapter contract

Define a test contract that any playable transport must satisfy:

```text
connect actor
join game
receive player snapshot
submit command
receive command result
receive observations
request resynchronization
leave/reconnect
```

Run the contract against:

- `LocalSession`;
- `GameChannel` through `Phoenix.ChannelTest`;
- optionally a localhost WebSocket client.

### 9.5 Canonical transcript comparison

A transcript contains semantic messages only:

- command accepted/rejected results;
- game sequence/version;
- public events;
- each player's private observations;
- final settlement.

Normalize or omit:

- socket references;
- Phoenix join references;
- heartbeats;
- connection IDs;
- wall-clock timestamps;
- JSON key order;
- packet boundaries.

Given the same initial players, rules, deck order, and commands, local and channel transcripts must be equal.

---

## 10. Session and authorization boundary

### 10.1 Actor context

The gateway receives actor identity separately from command payload:

```text
ActorContext
- account or guest identity
- player identity
- room/game identity
- controller lease ID
- connection/session ID
```

### 10.2 Controller leases

Initially allow one active controller lease per player.

Required behavior:

- reconnecting can reclaim the same player;
- a newer authorized lease invalidates or supersedes the previous lease;
- losing a WebSocket does not immediately remove the player from the game;
- spectators cannot submit player commands;
- a controller cannot act for a different seat by changing JSON.

### 10.3 Idempotency

A repeated `command_id` must not execute twice.

The gateway should return the previously recorded command result when the same actor repeats the same command ID. Reuse of a command ID with a different payload should be rejected as a protocol or session error.

### 10.4 Stale commands

If `expected_version` is not current:

- reject with `stale_game_version`;
- include the current version;
- optionally send or direct the client to request a fresh snapshot.

---

## 11. OTP process architecture

Proposed supervision tree:

```text
Doudizhu.Application
├── Doudizhu.Repo
├── Phoenix.PubSub
├── DoudizhuWeb.Endpoint
├── Doudizhu.Games.Registry
├── Doudizhu.Games.DynamicSupervisor
│   ├── GameServer(game-1)
│   └── GameServer(game-2)
└── Doudizhu.Rooms.DynamicSupervisor
    ├── RoomServer(room-1)
    └── RoomServer(room-2)
```

### 11.1 One GameServer per active game

`GameServer` is responsible for:

- serializing commands for one game;
- holding a cached current state;
- invoking the pure domain transition;
- coordinating durable commit;
- scheduling turn deadlines;
- initiating publication after commit.

It is not responsible for JSON or socket state.

### 11.2 Process discovery

Use a local `Registry` for the initial single-node deployment. Start game processes on demand under a `DynamicSupervisor`.

Do not assume that a registry makes state durable. On restart, a `GameServer` loads the current persisted snapshot.

### 11.3 Multi-node deployment

Defer multi-node process placement until a real need exists. Before enabling it, define:

- one authoritative process owner per game;
- cross-node command routing;
- split-brain prevention;
- database compare-and-swap on game version;
- process migration/recovery behavior;
- clustered PubSub.

A database version check remains necessary even if a distributed registry is introduced.

---

## 12. Persistence design

### 12.1 PostgreSQL records

Likely tables:

#### `games`

- `id`;
- `room_id`;
- `status`;
- `version`;
- `rules` as versioned structured data;
- current state snapshot as versioned structured data;
- current actor/deadline summary where useful for queries;
- inserted/updated timestamps.

#### `game_events`

- `game_id`;
- `sequence`;
- internal event type;
- versioned event payload;
- inserted timestamp;
- unique `(game_id, sequence)`.

Internal events may contain secret deal information and must not be exposed directly.

#### `processed_commands`

- `game_id`;
- `command_id`;
- actor/player ID;
- payload hash;
- accepted/rejected result;
- resulting version;
- unique `(game_id, command_id)`.

#### `outbox_messages`

- source game/version;
- audience type and audience ID;
- encoded or structured protocol message;
- publication status and attempts;
- inserted/published timestamps.

#### `rooms` and `room_seats`

- room/invitation state;
- exactly three seat positions;
- stable player identity;
- ready/controller status as appropriate.

### 12.2 Snapshot format

Do not persist arbitrary Erlang terms as opaque binaries. Use an explicitly versioned codec so schema evolution and operational inspection remain possible.

The storage representation is not the public JSON protocol. It may contain complete private state.

### 12.3 Commit order

For an accepted command:

1. verify actor, lease, command ID, and expected version;
2. execute the pure transition;
3. begin database transaction;
4. update the game row only if the stored version matches;
5. append internal events;
6. record processed command result;
7. write public/private outbox messages;
8. commit;
9. update the GameServer cache;
10. publish committed outbox messages;
11. return the command result.

Rejected domain commands should be recorded only if durable idempotent rejection behavior is desired. At minimum, accepted commands must be deduplicated durably.

### 12.4 Recovery

On process start:

- load the latest game snapshot;
- verify its codec version;
- optionally replay events newer than the snapshot;
- restore the current sequence;
- reschedule any active deadline;
- resume unpublished outbox delivery.

If a crash happens after commit but before broadcast, the outbox permits later publication. Clients can always recover by requesting a snapshot.

---

## 13. Public and private projection

### 13.1 Public projection

May contain:

- players and seats;
- room/game phase;
- auction starter and bids;
- landlord identity;
- revealed bottom cards when enabled;
- current turn;
- current lead and played physical cards;
- passes;
- hand counts;
- bomb/rocket counters;
- winner and settlement.

### 13.2 Player-private projection

May additionally contain:

- that player's hand;
- private command result;
- reconnect/controller status;
- player-specific available action summary.

Do not send opponent hands or unrevealed bottom cards.

### 13.3 Spectator projection

A live spectator receives public information only. Spectators cannot join player-private topics or submit game commands. Completed-game replay is a separate public review mode that exposes all historical hands without attaching to a live game process.

### 13.4 Projection tests

For every state phase, test each audience:

- landlord;
- first farmer;
- second farmer;
- spectator.

Add explicit assertions that no serialized opponent hand appears in another audience's messages.

---

## 14. Phoenix transport

### 14.1 Topics

Conceptual topics:

```text
room:<room_id>
game:<game_id>:public
game:<game_id>:player:<player_id>
```

Topic naming does not grant authorization. Every join validates the authenticated actor and controller lease.

### 14.2 GameChannel behavior

On join:

1. authenticate session token;
2. resolve player or spectator identity;
3. verify room/game membership;
4. claim or validate controller lease;
5. subscribe to authorized public/private streams;
6. send a current audience-specific snapshot.

On command:

1. decode through `Doudizhu.Protocol.Decoder`;
2. attach server-derived actor context;
3. dispatch through `CommandGateway`;
4. reply with the encoded command result;
5. allow committed observations to arrive through the shared publication path.

### 14.3 Presence

Use Phoenix Presence to show online controller status in rooms. Do not use presence state as the source of truth for:

- game membership;
- seats;
- roles;
- cards;
- turn state;
- winner.

### 14.4 Slow clients

Game traffic is low, but clients can still fall behind. Use sequence numbers and snapshots rather than retaining an unbounded per-client queue. Disconnect or resynchronize clients that cannot keep up.

---

## 15. Rooms and friend multiplayer

### 15.1 Room lifecycle

Suggested lifecycle:

```text
Open -> Ready -> GameStarted -> Closed
```

Capabilities:

- create a room;
- receive a shareable invitation code/link;
- join as a guest or authenticated account;
- claim one of exactly three seats;
- choose a player name;
- mark ready;
- start when all required conditions are met;
- create the game with stable player IDs and seat order.

### 15.2 Guest identity

For the first internet version, signed guest tokens may be sufficient. A guest token should bind:

- guest/account identity;
- room membership;
- player identity when seated;
- expiry and token version.

The server still verifies current room membership and lease state.

### 15.3 Shuffle and deal

Production shuffle occurs in the trusted application shell using cryptographically strong randomness. The resulting complete deck order is passed to the domain as data.

Tests inject a fixed deck order. Saving the deck order in the private game record enables exact replay.

---

## 16. Headless clients and bots

### 16.1 Remote headless client

The first non-test client should be a small CLI that:

- connects to Phoenix Channels;
- authenticates;
- joins a room/game;
- prints decoded observations;
- accepts bid/pass/card commands;
- reconnects and requests a snapshot.

This proves the game is usable without a UI.

### 16.2 External bots

A bot in any language follows the JSON protocol:

```text
connect -> receive observation -> choose action -> submit command -> repeat
```

Bots receive exactly the same player-private view as humans.

### 16.3 Local bots

An optional Elixir controller behaviour may be added:

```text
observation + bot state -> action + new bot state
```

The local bot runner should normally connect through `LocalSession`, not mutate game state directly.

### 16.4 High-speed simulation

For training or exhaustive simulation, provide a clearly separate direct-domain runner. It reuses:

- domain commands;
- pure transition functions;
- audience projection functions;
- deterministic deck injection.

It may omit JSON, database, GenServer, and Phoenix overhead.

---

## 17. Testing strategy

### 17.1 Domain example tests

Port all F# examples covering:

- deck uniqueness;
- every combination family;
- invalid sequences containing two/jokers;
- airplane attachment restrictions;
- duplicate cards;
- comparison by shape and rank;
- bomb and rocket precedence;
- full auction behavior;
- card ownership;
- turn and pass rules;
- landlord/farmer wins;
- bomb and rocket multipliers;
- spring and anti-spring;
- zero-sum settlement.

### 17.2 Property-based tests

Useful properties:

- accepted states never duplicate physical cards;
- cards are conserved between hands, bottom cards, and played cards;
- classification is unchanged by permutation of selected cards;
- a valid combination does not beat itself;
- if normal `a` beats normal `b`, `b` does not beat `a`;
- sequence bodies never contain two or jokers;
- rejected commands leave state and version unchanged;
- successful commands increment the version exactly once;
- settlement deltas sum to zero;
- only the current player can act;
- finished games accept no player actions.

### 17.3 Scenario DSL

Create a test helper for readable full games:

```text
create game
inject deck
bid(player, 1)
pass(player)
play(player, cards)
expect public event
expect private hand
expect final settlement
```

The DSL must submit commands through a selectable adapter so the same scenario can exercise local and channel paths.

### 17.4 Protocol tests

Test:

- all command and message examples against JSON Schema;
- encode/decode round trips;
- stable card identifiers;
- stable error codes;
- malformed JSON;
- missing required fields;
- unknown command types;
- unsupported protocol versions;
- additive unknown optional fields;
- no atom creation from untrusted strings.

### 17.5 Adapter conformance tests

Run identical scenarios through:

- in-memory wire-faithful adapter;
- `Phoenix.ChannelTest` adapter;
- optional localhost WebSocket adapter.

Compare canonical transcripts per audience.

### 17.6 Persistence tests

Using Ecto SQL Sandbox, test:

- optimistic version checks;
- command deduplication;
- transaction rollback;
- process restart and state reload;
- unpublished outbox recovery;
- snapshot codec migration;
- concurrent attempts to command one game.

### 17.7 Reconnection tests

Test:

- disconnect and reconnect to the same seat;
- replacement of an old controller lease;
- snapshot after missed events;
- stale expected version;
- duplicate command after lost acknowledgement;
- event sequence gap detection;
- spectator cannot reclaim a player seat.

### 17.8 Security/redaction tests

Test that:

- player identity cannot be forged in JSON;
- one player cannot join another player's private topic;
- spectators cannot submit commands;
- no opponent hand appears in public/private serialized messages;
- unrevealed bottom cards remain private;
- logs and telemetry omit card hands and auth tokens.

### 17.9 Differential fixtures with F#

Export shared language-neutral fixtures for selected rules:

```json
{
  "cards": ["C3", "D3", "H3", "C4"],
  "expected_kind": "triple_with_single",
  "main_rank": "3"
}
```

Both F# and Elixir tests consume or generate equivalent fixtures. The production systems do not call one another.

---

## 18. Observability

Emit Telemetry events for:

- command dispatch duration;
- domain acceptance/rejection counts by stable error code;
- persistence duration and conflicts;
- active game/room process counts;
- channel joins and reconnects;
- snapshot resynchronizations;
- outbox publication delay;
- process recovery failures.

Structured logs should include:

- game ID;
- command ID;
- actor/player ID where appropriate;
- expected/current version;
- event sequence;
- trace/correlation ID.

Do not log:

- complete hands;
- unrevealed bottom cards;
- session tokens;
- raw private snapshots.

---

## 19. Deployment progression

### Initial deployment

- one Phoenix node;
- one PostgreSQL database;
- TLS-enabled public endpoint;
- WebSocket support through the hosting proxy;
- persisted game state and reconnect support;
- regular database backups.

### Later scaling

Scale only after measuring:

- active connections;
- active games;
- process memory;
- database command latency;
- PubSub/outbox delay.

Before multiple nodes, add explicit game ownership and routing. Do not rely on accidental process location or sticky sessions for correctness.

---

## 20. Implementation phases

## Phase 0 — Freeze decisions and fixtures

Tasks:

- confirm the standard rule profile;
- list variant decisions inherited from F#;
- select canonical card IDs and ordering;
- define game/player/command ID formats;
- draft protocol v1 JSON Schemas;
- create shared combination and settlement fixtures;
- define canonical transcript normalization.

Exit criteria:

- no unresolved baseline rule ambiguity;
- representative JSON examples validate conceptually;
- local/wire parity has a written comparison definition.

## Phase 1 — Create the project and pure domain

Tasks:

- create the Phoenix/Elixir project under `ex-doudizhu/`;
- add pure domain modules with no Phoenix dependencies;
- port cards, hands, deck validation, and rules;
- port combination classification and comparison;
- port game phases, auction, play, passing, victory, and settlement;
- port all F# example tests;
- add initial property-based invariants.

Exit criteria:

- every standard combination is implemented;
- complete deterministic games run in pure tests;
- domain tests pass without starting Phoenix or PostgreSQL;
- no I/O or randomness exists in domain modules.

## Phase 2 — Protocol and projection

Tasks:

- implement protocol v1 decoder and encoder;
- implement stable domain-to-protocol error mapping;
- implement public and player-private snapshots/events;
- validate examples against schemas;
- add protocol round-trip and redaction tests;
- define command and message canonicalization.

Exit criteria:

- a complete game can be represented as JSON commands and observations;
- each player receives only permitted information;
- malformed protocol input never reaches the domain.

## Phase 3 — In-memory playable session

Tasks:

- implement `ActorContext`;
- implement `CommandGateway` without network transport;
- implement command ID and version semantics in memory;
- implement `LocalSession` in wire-faithful mode;
- create a three-controller scenario runner;
- record canonical per-audience transcripts;
- add simple local bot/controller hooks.

Exit criteria:

- three local headless players can complete a game using JSON-compatible messages;
- no test needs Phoenix Channels or internet access;
- duplicate and stale commands behave as designed.

## Phase 4 — Durable GameServer

Tasks:

- add Ecto schemas and migrations;
- implement current-state snapshot codec;
- implement game events and processed-command records;
- implement outbox records;
- add Registry, DynamicSupervisor, and one GameServer per active game;
- make GameServer load/recover state;
- atomically persist successful transitions before publication;
- test restart, duplicate command, and version conflict behavior.

Exit criteria:

- killing a GameServer does not lose a committed game;
- a repeated accepted command is not executed twice;
- clients can recover using a snapshot after missed publication.

## Phase 5 — Phoenix Channel transport

Tasks:

- implement socket authentication;
- implement public and private game topics;
- implement controller lease checks;
- make GameChannel a thin adapter over the gateway;
- send audience snapshot on join;
- route committed outbox/projection messages through PubSub;
- implement `Phoenix.ChannelTest` adapter;
- run local/channel transcript conformance tests.

Exit criteria:

- channel and local scenarios produce equal canonical transcripts;
- channel tests require no external internet connection;
- private information remains protected;
- reconnect returns the correct snapshot and sequence.

## Phase 6 — Rooms and friend invitations

Tasks:

- implement room lifecycle and exactly three seats;
- add shareable invitation codes;
- add signed guest identity or account authentication;
- add ready/start behavior;
- generate a trusted shuffled deck in the application shell;
- create/start the durable game from room state;
- use Presence only for online display.

Exit criteria:

- one player can create a room and invite two friends;
- all three can claim stable seats and start;
- disconnecting does not lose room or game membership.

## Phase 7 — Headless remote client

Tasks:

- build a minimal CLI client;
- support authentication, room join, snapshots, bids, plays, and passes;
- support reconnect and stale-version recovery;
- document the protocol for external bot authors;
- provide protocol example transcripts.

Exit criteria:

- three CLI clients can play a complete internet game;
- a program can participate without any graphical UI;
- bot and human controllers are indistinguishable to the game domain.

## Phase 8 — Graphical UI adapter

Tasks:

- choose browser Channel client or LiveView adapter;
- consume the same command gateway and projections;
- display only server-provided legal state;
- keep card classification and outcome authority on the server;
- run shared player-controller scenarios where practical.

Exit criteria:

- the UI introduces no alternate rule path;
- a UI player can play against CLI/bot players in the same game.

## Phase 9 — Reliability and operational hardening

Tasks:

- add persisted turn deadlines and timeout commands if desired;
- add rate limits and abuse controls;
- add outbox retry worker;
- add metrics, dashboards, and alerting;
- add backup/recovery procedure;
- test rolling deployment and snapshot codec upgrades;
- fuzz protocol decoders;
- load test large numbers of idle connections and active rooms.

Exit criteria:

- recovery behavior is documented and tested;
- operational failures do not silently corrupt game state;
- hidden card data does not appear in logs or public telemetry.

---

## 21. Milestone acceptance scenarios

The following scenarios should become permanent executable specifications.

### Scenario A: all-pass redeal

- three players join;
- each passes before a bid;
- deal is voided;
- game returns to awaiting deal with incremented deal number.

### Scenario B: normal landlord game

- player A bids 1;
- player B passes;
- player C bids 2;
- A and B pass;
- C receives bottom cards and leads;
- game finishes with correct settlement.

### Scenario C: lead reset

- landlord plays;
- two players pass;
- landlord receives a cleared lead and may play any combination.

### Scenario D: bomb and rocket scoring

- deterministic deal allows bomb and rocket plays;
- event counters and final multipliers are correct;
- settlement remains zero-sum.

### Scenario E: farmer anti-spring

- landlord plays only the opening combination;
- farmer side wins;
- anti-spring multiplier is applied.

### Scenario F: duplicate command

- client submits command;
- commit succeeds but acknowledgement is simulated as lost;
- client resubmits the same command ID;
- command executes only once and the original result is returned.

### Scenario G: disconnect and replay

- player disconnects for several turns;
- public events continue;
- player reconnects;
- player receives a current private snapshot and sequence;
- subsequent action is accepted from the new lease.

### Scenario H: local/channel parity

- run one deterministic complete game through `LocalSession`;
- run it through `Phoenix.ChannelTest`;
- canonical public and private transcripts are identical.

### Scenario I: information security

- capture every message delivered to each audience;
- assert no player receives an opponent's unplayed cards;
- assert spectator receives public information only.

---

## 22. Important risks and mitigations

### Risk: game rules leak into Channel handlers

Mitigation: Channel tests assert only decoding/dispatch; all rules are tested in domain modules. Code review rejects rule decisions in web modules.

### Risk: local tests bypass production behavior

Mitigation: maintain separate direct-domain tests and wire-faithful local integration tests. Adapter conformance is a release criterion.

### Risk: PubSub messages are lost around crashes

Mitigation: persist before broadcast, use sequence numbers/snapshots, and introduce an outbox for committed observations.

### Risk: private cards leak through a shared event

Mitigation: separate internal events from audience projections and add serialized redaction tests.

### Risk: GenServer state is mistaken for durable state

Mitigation: PostgreSQL is authoritative after persistence is introduced; processes recover from versioned snapshots.

### Risk: duplicate commands execute twice

Mitigation: unique durable command IDs and persisted command results.

### Risk: dynamic Elixir types weaken F# invariants

Mitigation: constructors, opaque types, pattern-matched phase structs, typespecs, exhaustive tests, property tests, and shared fixtures.

### Risk: distributed deployment creates two owners for one game

Mitigation: start single-node; later combine explicit ownership with database version compare-and-swap.

### Risk: protocol evolves accidentally

Mitigation: versioned schemas, golden examples, stable error codes, and compatibility tests.

---

## 23. Definition of done for the first complete release

The first complete release is done when:

- the Elixir domain passes the F# parity suite;
- three friends can join a private room over the internet;
- each player can reconnect without losing their seat or game;
- three headless JSON clients can complete a game;
- a graphical client, if present, uses the same command/projection boundary;
- local and Phoenix Channel canonical transcripts match;
- commands are versioned and idempotent;
- state survives a GameServer restart;
- every audience receives only authorized information;
- final scoring is deterministic and zero-sum;
- the game can be replayed locally from its private initial deal and command history;
- build, domain, protocol, persistence, channel, and security tests pass without public internet access.

---

## 24. First decision checkpoint

Before implementation begins, confirm these choices:

1. Pagat/F# remains the normative three-player rule profile.
2. The first deployment is a single Phoenix node with PostgreSQL.
3. Guest invitation links are sufficient before full accounts.
4. One active controller lease is allowed per player.
5. The public protocol is JSON over Phoenix Channels.
6. Local playable mode passes through the same JSON codec and gateway.
7. Internal persistence events are distinct from public/private observations.
8. A CLI is the first real client; graphical UI follows.
9. Sequence snapshots and idempotent commands are included before public internet play.
10. Multi-node distribution and advanced matchmaking are deferred.

Once these are agreed, Phase 0 can convert the decisions into fixtures and protocol schemas before application code is created.
