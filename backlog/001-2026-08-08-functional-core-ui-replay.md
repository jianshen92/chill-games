# Functional-core Doudizhu, browser UI, and replay

**Date:** 2026-08-08  
**Status:** Completed

## Summary

Implemented the Elixir/Phoenix Doudizhu application from the F# executable specification while preserving a deterministic functional core.

- Ported cards, combinations, auction, turn play, scoring, springs, and settlement to pure Elixir.
- Added protocol-v1 JSON commands, stable errors, audience projections, and schema tests.
- Added durable `GameServer` processes, PostgreSQL snapshots/events, command idempotency, controller leases, optimistic versions, and an outbox.
- Added friend rooms, invitation links, guest identities, reconnect/resync, Channels, Presence, a headless CLI, and local/wire transcript parity.
- Added a responsive browser UI that uses the same `CommandGateway` as headless clients.
- Added deterministic replay from the original deck and accepted command history.
- Changed completed replay to public-by-high-entropy-game-ID review mode with all hands, bottom cards, event history, seeking, autoplay, and shareable links.
- Kept unfinished games private to prevent replay-based live hand leakage.
- Reviewed the architecture and confirmed that live UI, headless play, and replay share `Protocol.Decoder`, `Protocol.DomainCommand`, and `Domain.Game.execute/2`.

## Verification

- Functional core has no Phoenix, Ecto, process, clock, random, or JSON dependencies.
- Live/replay regression tests compare semantic state at every accepted version.
- Final replay state is checked against the canonical persisted snapshot.
- `mix precommit` passes with 72 tests, including property, transport-parity, replay, privacy, and Channel tests.

## Follow-ups

- Project server-provided `available_actions` instead of deriving action visibility in JavaScript.
- Persist a domain/rules-engine version for long-term replay compatibility across future rule changes.
- Add account-based guest identity recovery if replay history must survive cleared browser storage.
