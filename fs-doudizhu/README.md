# Chill Game — 斗地主 Domain Model in F#

A deterministic, framework-independent domain model for one complete three-player hand of 斗地主 (Dou Dizhu / Fight the Landlord).

The implementation covers:

- exactly three distinct seated players;
- a validated 54-card deck and immutable hands;
- deterministic dealing from a caller-supplied shuffled deck;
- the complete ascending 1–3 auction, including continued bidding and all-pass redeals;
- landlord/farmer roles and assignment of the three bottom cards;
- all standard three-player combination families;
- combination comparison, including bombs and the rocket;
- turn order, passing, and clearing the lead after two passes;
- landlord and farmer victory;
- bid, bomb, rocket, spring, and anti-spring settlement;
- zero-sum score changes for all three players;
- immutable state transitions, explicit commands, events, and domain errors.

## Scope

`Game` represents one scored hand from `AwaitingDeal` through `Bidding`, `Playing`, and `Finished`. A longer match can accumulate each hand's `Settlement` in a separate match or account context.

The following deliberately remain outside this pure domain library:

- random-number generation and deck shuffling;
- matchmaking, rooms, readiness, and reconnection;
- authentication and authorization;
- storage and optimistic-concurrency implementation;
- network DTOs and player-specific redaction;
- timers, bots, UI card ordering, animation, and chat;
- wallets, leaderboards, and multi-hand score accumulation.

A shuffled deck is supplied as a validated `DeckOrder`, making dealing deterministic and testable. `Game.tryHand` is a trusted application-level query; a transport adapter must expose only the requesting player's hand.

## Implemented rule profile

斗地主 has regional and platform variants. `RuleSet.standardThreePlayer` follows the three-player rules documented by Pagat.

### Cards

- One 54-card deck: 52 suited cards plus small and big jokers.
- Rank, low to high: `3 4 5 6 7 8 9 10 J Q K A 2 SmallJoker BigJoker`.
- Suits identify physical cards but do not affect combination strength.
- Each player receives 17 cards; three bottom cards remain for the landlord.

### Auction

- The caller identifies the auction starter when dealing.
- A player may pass or bid `1`, `2`, or `3`.
- A bid must exceed the current highest bid.
- Passing does not permanently remove a player from the auction.
- After a bid, two consecutive passes make the highest bidder landlord.
- A bid of `3` ends the auction immediately.
- If the first three actions are passes, the deal is void and the game returns to `AwaitingDeal` with an incremented deal number.
- The landlord receives the bottom cards and leads with a 20-card hand.

### Combinations

| Model case | Rule |
|---|---|
| `Single` | Any one card |
| `Pair` | Two standard cards of one rank |
| `Triple` | Three standard cards of one rank |
| `TripleWithSingle` | Triple plus one card of another rank |
| `TripleWithPair` | Triple plus a standard pair of another rank |
| `Straight n` | At least five consecutive single ranks, from 3 through Ace |
| `ConsecutivePairs n` | At least three consecutive pairs, from 3 through Ace |
| `Airplane n` | At least two consecutive triples, from 3 through Ace |
| `AirplaneWithSingles n` | Consecutive triples plus one single wing per triple |
| `AirplaneWithPairs n` | Consecutive triples plus one distinct standard pair per triple |
| `FourWithSingles` | Four of a kind plus two single cards of different ranks |
| `FourWithPairs` | Four of a kind plus two distinct standard pairs |
| `Bomb` | Four of a kind |
| `Rocket` | Small and big joker together |

Twos and jokers cannot be in sequence bodies. They may be attachments where their multiplicity permits. Under the baseline profile:

- airplane single wings may contain a pair;
- a wing cannot be from an airplane body rank;
- airplane pair wings have distinct ranks;
- four-with-singles wings have distinct ranks;
- both jokers cannot be used together as attachments.

Those attachment choices are explicit in `AttachmentRules` because implementations differ.

### Beating the current play

- A normal response must have the same `CombinationKind`, including the same sequence/body length, and a higher main rank.
- A bomb beats every non-bomb normal combination, regardless of rank.
- A higher bomb beats a lower bomb.
- The rocket beats every combination.
- A four-with-attachments combination is not a bomb.

### Turn and pass rules

- The landlord leads first.
- A leader must play; passing is legal only while responding to a current lead.
- A player may pass even if able to beat the lead.
- Passing does not prevent that player from playing later in the same contest.
- After two consecutive passes, the current lead is cleared and its owner leads a new combination.
- The first player with an empty hand ends the hand immediately.
- If the landlord empties their hand, the landlord side wins.
- If either farmer empties their hand, both farmers win.

### Settlement

Let the per-farmer stake be:

```text
winning bid
× bomb multiplier ^ bombs played
× rocket multiplier ^ rockets played
× spring multiplier when applicable
```

The standard multipliers are all `2`.

- Landlord win: landlord `+2 × stake`; each farmer `−stake`.
- Farmer win: landlord `−2 × stake`; each farmer `+stake`.
- Landlord spring: landlord wins before either farmer successfully plays cards.
- Farmer spring / anti-spring: farmers win after the landlord successfully played only the opening combination.

The resulting `Settlement.Deltas` always sum to zero.

## Model structure

```text
src/ChillGame.Domain/
├── Primitives.fs     player IDs, names, players, and three-seat ordering
├── Cards.fs          cards, ranks, deck validation, and immutable hands
├── Rules.fs          explicit variant and scoring rules
├── Combinations.fs   classification and beating relation
└── Game.fs           auction, gameplay, settlement, commands, events, and queries
```

### Algebraic design

The principal state machine is a discriminated union hidden inside the aggregate:

```fsharp
AwaitingDeal -> Bidding -> Playing -> Finished
                    |
                    +------ all pass ------> AwaitingDeal
```

Invalid phase-specific fields cannot coexist. Public commands are interpreted by one aggregate function:

```fsharp
Game.execute:
    GameCommand
        -> Game
        -> Result<Game * GameEvent list, GameError>
```

A successful command produces a new immutable `Game`, increments its version, and emits meaningful events. A rejected command leaves the original value unchanged.

`Combination` is opaque. The only way to obtain one is classification:

```fsharp
Combination.classify:
    RuleSet
        -> Card list
        -> Result<Combination, CombinationError>
```

This means `Combination.beats` receives only already-valid plays.

### Main commands

```fsharp
GameCommand.Deal(deck, auctionStarter)
GameCommand.Bid(player, BidAction.Pass)
GameCommand.Bid(player, BidAction.Place Bid.Two)
GameCommand.PlayCards(player, cards)
GameCommand.Pass(player)
```

### Main events

```fsharp
CardsDealt
AuctionPassed
BidPlaced
DealVoided
LandlordChosen
CardsPlayed
TurnPassed
LeadCleared
GameFinished
```

Events are useful domain outputs but this model does not require event sourcing.

### Querying without exposing construction

Internal game-state records and constrained values have private representations. Read access is through functions such as:

```fsharp
Game.status
Game.phase
Game.version
Game.tryRole
Game.tryHand
Combination.kind
Combination.mainRank
Combination.cards
Settlement.scoreFor
```

This keeps construction controlled while allowing application adapters to build appropriate views.

## Build and test

Requires the .NET 8 SDK.

```bash
dotnet build ChillGame.sln
dotnet test ChillGame.sln
```

The tests exercise every combination family and important negative cases, auction transitions, role selection, passing and lead reset, card ownership, complete landlord and farmer wins, bomb multipliers, spring and anti-spring, and zero-sum settlement.

## Example

```fsharp
open ChillGame.Domain

let game =
    Game.create gameId players RuleSet.standardThreePlayer
    |> Result.bind (fun game ->
        Game.execute (GameCommand.Deal(deck, auctionStarter)) game
        |> Result.map fst)

let afterBid =
    game
    |> Result.bind (fun game ->
        Game.execute
            (GameCommand.Bid(auctionStarter, BidAction.Place Bid.Three))
            game
        |> Result.map fst)

let afterPlay =
    afterBid
    |> Result.bind (fun game ->
        Game.execute
            (GameCommand.PlayCards(auctionStarter, selectedCards))
            game
        |> Result.map fst)
```

In a real application, the imperative shell creates IDs, shuffles and validates the deck, loads a game version, calls `Game.execute`, atomically persists the new version, and publishes returned events.

## Sources

- Pagat, “Dou Dizhu” — <https://www.pagat.com/climbing/doudizhu.html>
- General F# domain-modelling background — [`fsharp-domain-modelling.md`](fsharp-domain-modelling.md)

The Pagat rules are the normative baseline for this implementation. Variant-sensitive assumptions are called out above rather than hidden in classifier conditionals.
