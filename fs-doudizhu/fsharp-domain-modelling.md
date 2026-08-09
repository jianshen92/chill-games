# F# Domain Modelling: Core Primitives and Practical Wisdom

## Purpose

This note explains the small set of F# ideas that make it unusually effective for domain modelling, and the design wisdom that follows from them. It is about modelling business and game rules, not merely translating an object-oriented design into F# syntax.

The central claim is:

> The core primitive of functional domain modelling is a type describing valid values, together with functions describing valid transitions between those values.

Most of the technique can be derived from three building blocks:

1. **Product types** describe values that contain this **and** that.
2. **Sum types** describe values that are this **or** that.
3. **Functions** describe transformations from one set of valid values to another.

In F#, records and tuples are product types, discriminated unions are sum types, and function signatures are lightweight specifications. `option`, `Result`, state machines, constrained values, commands, events, and workflows are compositions of those elements.

---

## 1. Start with the domain language

Domain modelling starts in conversation, before it starts in code. Listen for:

- nouns: `Game`, `Hand`, `Bid`, `Combination`;
- distinctions: `PlayerId` versus `GameId`;
- choices: landlord or farmer;
- rules: a response must beat the current play;
- state changes: bidding finishes and play begins;
- failure language: not your turn, cards not owned, invalid combination;
- quantities: exactly three bottom cards, at least five cards in a straight.

A type definition is a hypothesis about that language. It should be cheap to revise when the team learns that two apparently identical concepts differ, or two apparently different concepts are actually one.

Do not begin by copying database tables, JSON documents, or screen forms. Those are representations at system boundaries, not necessarily the domain model.

---

## 2. The algebraic core: AND, OR, and transformations

### 2.1 Product types: values containing this AND that

An F# record groups named values that must be present together:

```fsharp
type PlayerProfile = {
    PlayerId: PlayerId
    DisplayName: PlayerName
}
```

A `PlayerProfile` has a `PlayerId` **and** a `DisplayName`.

Tuples are also product types:

```fsharp
PlayerId * Bid
```

Use tuples for small, local groupings whose meaning is obvious. Prefer records when names carry domain meaning, when the value crosses an API boundary, or when its shape is likely to evolve.

### 2.2 Sum types: values containing this OR that

A discriminated union enumerates the legitimate alternatives:

```fsharp
type Role =
    | Landlord
    | Farmer

type Game =
    | Bidding of BiddingState
    | Playing of PlayingState
    | Finished of FinishedState
```

A `Game` is bidding **or** playing **or** finished. Each case carries only the information relevant to that phase.

This is more than a convenient enum. A union case may carry case-specific data, and pattern matching forces consumers to acknowledge the alternatives.

### 2.3 Functions: valid input transformed into valid output

A function signature can describe a use case before implementation exists:

```fsharp
type PlayCards =
    RuleSet
        -> PlayerId
        -> Card list
        -> PlayingState
        -> Result<Game * GameEvent list, PlayError>
```

Read this as a domain sentence:

> Given a rule set, a player, selected cards, and a game in the playing phase, either produce a new game plus events, or explain why the play was rejected.

Writing signatures first is a useful design practice. Awkward signatures often reveal missing concepts, mixed responsibilities, or an incorrect boundary.

---

## 3. Values and immutability

F# bindings and records are immutable by default:

```fsharp
let advanceTurn nextPlayer state =
    { state with CurrentPlayer = nextPlayer }
```

The function returns a new value rather than changing the old value in place.

This matters for domain modelling because:

- a value cannot be damaged from an unrelated part of the program;
- state transitions are visible as functions;
- old and new states can be compared in tests;
- pure decisions are deterministic and easy to replay;
- concurrency boundaries become easier to reason about.

Immutability does **not** mean the domain has no change. It means change is represented explicitly as `old state -> new state`.

A long-lived domain entity can still have identity:

```fsharp
type GameId = private GameId of System.Guid

type Version = private Version of int64

type GameSnapshot = {
    Id: GameId
    Version: Version
    State: Game
}
```

Two snapshots may describe the same game identity at different versions. F# records have structural equality by default, but structural equality is not automatically the correct definition of entity identity. Make identity explicit and compare entities according to the domain's rules.

---

## 4. Give domain concepts their own types

This declaration does not create a distinct type:

```fsharp
// Type abbreviations: these values can still be mixed up.
type PlayerId = System.Guid
type GameId = System.Guid
```

Both names remain aliases for `Guid`. Prefer single-case unions when interchange would be a domain error:

```fsharp
type PlayerId = private PlayerId of System.Guid
type GameId = private GameId of System.Guid
```

Now a `PlayerId` cannot be passed where a `GameId` is required.

This technique addresses **primitive obsession**. A player ID is represented by a `Guid`, but it is not conceptually “just a Guid.” Likewise, an email address is represented by a string but is not every possible string.

Do not wrap every primitive mechanically. Introduce a type when it adds at least one of:

- a domain distinction;
- a constraint;
- domain operations;
- clearer signatures;
- protection against accidental interchange.

---

## 5. Constrained values and smart constructors

A public wrapper case can still be forged. Hide its representation and expose a function that constructs only valid values:

```fsharp
type PlayerNameError =
    | PlayerNameRequired
    | PlayerNameTooLong of maximum: int

type PlayerName = private PlayerName of string

module PlayerName =
    let create (raw: string) : Result<PlayerName, PlayerNameError> =
        if System.String.IsNullOrWhiteSpace raw then
            Error PlayerNameRequired
        else
            let normalized = raw.Trim()

            if normalized.Length > 30 then
                Error (PlayerNameTooLong 30)
            else
                Ok (PlayerName normalized)

    let value (PlayerName name) = name
```

Once a `PlayerName` exists, downstream code should not repeatedly check whether it is blank or too long. Validation happened at the point where untrusted data became a domain value.

This is close to the broader principle **“parse, don't validate”**:

- do not accept a weak value, check it, and continue passing the weak value around;
- convert it once into a stronger type that records what is now known.

### Local versus contextual invariants

A smart constructor is good for invariants determined by one value, such as length or numeric range. It cannot prove contextual rules such as:

- whether it is this player's turn;
- whether the selected cards are in the current hand;
- whether a name is unique in a database;
- whether a command was based on the latest game version.

Those rules belong in a decision function with the required state or dependency. Do not force every business rule into a tiny wrapper type.

---

## 6. Make illegal states unrepresentable

Consider a flag-oriented design:

```fsharp
type WeakGameState = {
    IsBidding: bool
    IsFinished: bool
    CurrentPlayer: PlayerId option
    Winner: PlayerId option
}
```

It permits contradictory combinations:

- bidding and finished at the same time;
- finished without a winner;
- bidding with a current playing-turn player;
- active play with a winner.

Represent the legitimate cases directly:

```fsharp
type Game =
    | Bidding of BiddingState
    | Playing of PlayingState
    | Finished of FinishedState
```

The individual states carry only appropriate fields:

```fsharp
type BiddingState = {
    Hands: Map<PlayerId, Hand>
    BottomCards: Card list
    CurrentBidder: PlayerId
    Bids: Bid list
}

type PlayingState = {
    Hands: Map<PlayerId, Hand>
    Landlord: PlayerId
    CurrentPlayer: PlayerId
    CurrentLead: CurrentLead option
}

type FinishedState = {
    Landlord: PlayerId
    Winner: WinningSide
    Score: Score
}
```

This is the practical meaning of “make illegal states unrepresentable”: shape the type so that meaningless combinations have no constructor.

The phrase should not be interpreted as “prove the whole application correct in the type system.” Authorization, time, distributed concurrency, and rules depending on current state still require runtime decisions.

---

## 7. Use `option` only for genuine optionality

Conceptually, F#'s option type is a sum:

```fsharp
type Option<'value> =
    | None
    | Some of 'value
```

It states that a value is either absent or present. It avoids `null` as an undocumented extra state.

Good uses include:

```fsharp
type PlayerProfile = {
    Nickname: PlayerName option
}
```

Use `option` when absence is normal and no explanation is required. Do not use it when callers need to know why an operation failed; use `Result` for that.

Also avoid using many independent options when only certain combinations are legal:

```fsharp
// Allows neither method, even if the domain requires at least one.
type WeakContact = {
    Email: EmailAddress option
    PostalAddress: PostalAddress option
}
```

Model the actual alternatives instead:

```fsharp
type ContactMethod =
    | EmailOnly of EmailAddress
    | PostalOnly of PostalAddress
    | EmailAndPostal of EmailAddress * PostalAddress
```

---

## 8. Treat expected failures as domain values

Conceptually, `Result` is another sum type:

```fsharp
type Result<'success, 'error> =
    | Ok of 'success
    | Error of 'error
```

Use it for expected rejections that a caller can understand or act upon:

```fsharp
type PlayError =
    | GameIsNotInPlayingPhase
    | NotPlayersTurn of expected: PlayerId
    | CardsNotOwned of Card list
    | InvalidCombination of CombinationError
    | DoesNotBeatCurrentLead
```

These are part of the domain's language. They should not initially be HTTP status codes, UI strings, log messages, or exceptions. Translate them at the relevant boundary.

### `option`, `Result`, and exceptions

A useful rule of thumb is:

| Mechanism | Use when |
|---|---|
| `option` | Absence is expected and its reason is irrelevant |
| `Result` | Failure is expected and the caller needs domain information |
| Exception | The failure is unexpected, diagnostic, environmental, or indicates a defect/broken internal invariant |

Do not turn every function into `Result`. Scott Wlaschin's later “Against Railway-Oriented Programming” explicitly warns against using `Result` as a universal substitute for exceptions or for control flow whose errors nobody needs.

Sequential `Result.bind` composition normally stops at the first error. Independent input checks may instead need an applicative validation approach that accumulates several errors. Pick the error semantics required by the use case rather than applying one fashionable abstraction everywhere.

---

## 9. Collections also have domain meaning

A plain `'a list` permits an empty list. If the domain requires at least one item, represent that fact:

```fsharp
type NonEmptyList<'value> = private {
    Head: 'value
    Tail: 'value list
}

module NonEmptyList =
    let create = function
        | [] -> None
        | head :: tail -> Some { Head = head; Tail = tail }

    let toList values =
        values.Head :: values.Tail
```

Other collection distinctions may matter:

- sequence versus set;
- ordered versus unordered;
- unique keys versus duplicates;
- exactly two jokers;
- exactly three bottom cards;
- bounded hand size.

Do not create a complex collection wrapper without a real invariant. But do not use `list` everywhere merely because it is convenient.

Some cardinalities are awkward to prove with ordinary F# types. A private representation plus a checked constructor is often the pragmatic answer.

---

## 10. Units of measure prevent dimensional mistakes

F# units of measure can distinguish numeric dimensions at compile time:

```fsharp
[<Measure>]
type point

[<Measure>]
type multiplier

type BaseScore = int<point>
type ScoreMultiplier = int<multiplier>
```

They are useful for physical units and some domain quantities because invalid arithmetic becomes a compile-time error.

Units of measure are erased at runtime. Serialization must preserve the unit's meaning separately, and a compile-time currency unit is often inappropriate when currency is selected dynamically. Use them where dimensional analysis matches the domain; do not treat them as a universal replacement for domain value types.

---

## 11. Pattern matching makes decisions explicit

A discriminated union is paired naturally with exhaustive pattern matching:

```fsharp
let teamOf landlord player =
    if player = landlord then LandlordSide else FarmerSide

let winnerSide landlord winner =
    match teamOf landlord winner with
    | LandlordSide -> LandlordSide
    | FarmerSide -> FarmerSide
```

When a new union case is added, the compiler points to matches that may need reconsideration. This is valuable change guidance: adding a domain possibility reveals the decisions affected by it.

Prefer explicit domain functions over relying accidentally on F#'s structural ordering of union cases. For example, define card strength deliberately:

```fsharp
let standardRankStrength = function
    | Three -> 3
    | Four -> 4
    | Five -> 5
    // ...
    | Ace -> 14
    | Two -> 15
```

Declaration order is an implementation detail unless the domain intentionally makes it part of the API.

Discriminated unions model a **closed world**: all cases are known here. That is excellent for stable domain alternatives and exhaustive decisions. If third parties must add new cases without modifying the defining module, an interface or another extensibility mechanism may fit better.

---

## 12. Model workflows as functions

Object-oriented designs often begin with a graph of objects. Functional domain modelling often begins with a use case:

```text
Input -> Decode -> Decide -> New state + events
```

The pure domain decision should ideally have no database, clock, network, logging, or framework dependency:

```fsharp
type Decide<'command, 'state, 'event, 'error> =
    'command
        -> 'state
        -> Result<'state * 'event list, 'error>
```

The surrounding application shell performs effects:

```text
receive DTO
  -> decode into domain command
  -> load state
  -> call pure decision
  -> persist new state
  -> publish events
  -> translate result into transport response
```

This is often called a **functional core, imperative shell**. It is compatible with hexagonal architecture:

- the domain owns its language and decisions;
- adapters own HTTP, storage, queues, serialization, and UI details;
- dependencies point toward the domain.

When a workflow genuinely needs outside information, make that requirement visible. One approach is to pass a small function capability:

```fsharp
type CurrentTime = unit -> System.DateTimeOffset
```

Another is to have the pure decision return instructions or events that an application layer interprets. Choose the simpler design for the use case. Passing every repository operation through every function can obscure the domain just as easily as hiding all I/O in global state.

---

## 13. Commands, events, and state transitions

A command asks for something to happen. An event records a meaningful fact that did happen:

```fsharp
type GameCommand =
    | PlaceBid of PlayerId * Bid
    | PlayCards of PlayerId * Card list
    | Pass of PlayerId

type GameEvent =
    | BidPlaced of PlayerId * Bid
    | LandlordChosen of PlayerId
    | CardsPlayed of PlayerId * Combination
    | PlayerPassed of PlayerId
    | GameFinished of WinningSide
```

A command may be rejected; an event should already be a valid fact.

Domain events are useful outputs even without event sourcing. They may drive UI updates, audit records, scoring, or integration. Do not publish every internal implementation detail as a global event, and do not adopt event sourcing unless historical reconstruction, audit, temporal reasoning, or replay justifies its operational cost.

State-specific functions can make the transition rules clearer than one giant command handler:

```fsharp
type PlaceBid =
    RuleSet
        -> PlayerId
        -> Bid
        -> BiddingState
        -> Result<Game * GameEvent list, BidError>

type PlayCards =
    RuleSet
        -> PlayerId
        -> Card list
        -> PlayingState
        -> Result<Game * GameEvent list, PlayError>
```

The compiler now prevents `PlayCards` from receiving a `BiddingState`. An outer application function can inspect `Game` and route a command to the appropriate phase-specific workflow.

---

## 14. Encapsulation belongs at construction boundaries

Functional data can be transparent without being unsafe because it is immutable. Nevertheless, constrained values require controlled construction.

F# provides several useful boundaries:

- `private` union cases or record representations;
- companion modules exposing `create`, `value`, and domain operations;
- `.fsi` signature files exposing an abstract type while hiding its implementation;
- project/module boundaries aligned with bounded contexts.

A typical public surface is small:

```fsharp
// Combination.fsi

type Combination

type CombinationError =
    | EmptySelection
    | DuplicateCard
    | UnsupportedPattern

module Combination =
    val classify:
        RuleSet
            -> Card list
            -> Result<Combination, CombinationError>

    val beats:
        RuleSet
            -> current: Combination
            -> challenger: Combination
            -> bool
```

Callers can classify cards and compare valid combinations, but cannot manufacture an invalid `Combination`.

Separating immutable data from module functions is not the same failure as an object-oriented anemic domain model. Functional cohesion comes from meaningful types, controlled construction, domain-oriented modules, and explicit workflows—not from attaching every operation as an instance method.

---

## 15. Bounded contexts still matter

F#'s type system helps with tactical modelling, but it does not discover strategic boundaries automatically.

For a game system, possible contexts include:

- **Accounts:** identity, profile, authentication;
- **Lobby:** rooms, invitations, readiness, matchmaking;
- **Gameplay:** dealing, bidding, combinations, turns, winning;
- **Scoring:** multipliers, settlement, rankings;
- **Presentation:** card ordering, animation, reconnect views.

A `Player` need not have one universal representation across all these contexts. `Accounts.UserId` and `Gameplay.PlayerId` may intentionally be distinct types with translation at the boundary.

Do not put the entire enterprise vocabulary into one enormous discriminated union or shared “domain” assembly. A model is valid within a purpose and context. Some duplication is safer than semantic coupling.

F# file ordering can reinforce dependency direction, but compiler ordering is not a substitute for finding the right domain boundaries.

---

## 16. A small 斗地主 modelling sketch

This sketch illustrates the technique; it is not a complete rules implementation.

### Domain vocabulary

```fsharp
type Suit =
    | Clubs
    | Diamonds
    | Hearts
    | Spades

type StandardRank =
    | Three | Four | Five | Six | Seven
    | Eight | Nine | Ten | Jack | Queen
    | King | Ace | Two

type Card =
    | SuitedCard of Suit * StandardRank
    | SmallJoker
    | BigJoker

type Role =
    | Landlord
    | Farmer

type WinningSide =
    | LandlordSide
    | FarmerSide
```

A standard card and a joker have different valid data, so `Card` uses different union cases rather than fake suits or nullable ranks.

### Keep classification valid by construction

A selected group of cards and its rule interpretation are related but not identical. Preserve the physical cards while hiding the classified representation:

```fsharp
type Combination

module Combination =
    val classify:
        RuleSet
            -> Card list
            -> Result<Combination, CombinationError>

    val cards: Combination -> Card list

    val beats:
        RuleSet
            -> current: Combination
            -> challenger: Combination
            -> bool
```

This gives one authoritative place for straights, consecutive pairs, airplanes, bombs, the rocket, and variant-specific rules. It avoids repeating array inspection and rank comparison throughout UI handlers and services.

### Model game phases, not flags

```fsharp
type Game =
    | Bidding of BiddingState
    | Playing of PlayingState
    | Finished of FinishedState
```

Phase-specific functions enforce the broad transition shape:

```fsharp
val placeBid:
    RuleSet
        -> PlayerId
        -> Bid
        -> BiddingState
        -> Result<Game * GameEvent list, BidError>

val playCards:
    RuleSet
        -> PlayerId
        -> Card list
        -> PlayingState
        -> Result<Game * GameEvent list, PlayError>

val pass:
    PlayerId
        -> PlayingState
        -> Result<Game * GameEvent list, PassError>
```

Important runtime invariants still belong in these functions:

- every physical card has exactly one location;
- only the current player may act;
- played cards belong to that player's hand;
- selected cards classify under the active `RuleSet`;
- a response beats the current lead unless the player is leading;
- two passes return control to the last player who played;
- an empty hand finishes the game and determines the winning side.

A `RuleSet` should make supported rule variations explicit. Variant behavior hidden in presentation conditionals is not part of a reliable domain model.

---

## 17. Testing follows naturally from the model

Pure functions and constrained types reduce test setup. Tests can focus on examples and laws rather than mocking infrastructure.

Useful example tests include:

- two jokers classify as a rocket;
- a rocket beats every other valid combination;
- a straight cannot include `Two` or jokers;
- a player cannot play a card absent from their hand;
- a farmer finishing first gives `FarmerSide` victory.

Useful property-based tests include:

- classification never returns a combination containing cards not supplied;
- accepted plays conserve the total set of physical cards;
- if `a` beats `b`, then `b` does not beat `a` under the same rules;
- every successful transition preserves game invariants;
- smart constructors never produce values violating their documented constraints.

The compiler proves shape-level facts; tests prove examples, algebraic laws, and contextual behavior. Neither replaces domain review with people who understand the game or business.

---

## 18. Common mistakes

### Mistake 1: treating type aliases as domain types

```fsharp
type CustomerId = int
type OrderId = int
```

These remain interchangeable. Use distinct wrappers when interchange is invalid.

### Mistake 2: validating and then continuing with primitives

```fsharp
val validateName: string -> Result<unit, Error>
```

The caller still holds only a `string` and can forget whether it was checked. Prefer parsing into `PlayerName`.

### Mistake 3: exposing a constrained type's constructor

If anyone can call `PlayerName ""`, the smart constructor provides convention, not enforcement. Hide the representation.

### Mistake 4: modelling state with booleans and unrelated options

This creates a Cartesian product of states, most of which may be meaningless. Use a discriminated union with one case per legitimate phase.

### Mistake 5: putting `Result` around everything

Use `Result` for expected, actionable failures. It is not a replacement for diagnostics, fail-fast behavior, or all exceptions.

### Mistake 6: believing types eliminate runtime validation

Ownership, authorization, uniqueness, time, version conflicts, and current-state rules require runtime information. Types can ensure those checks return explicit domain outcomes; they cannot know facts they were never given.

### Mistake 7: allowing transport and persistence to shape the domain

DTOs may contain nullable strings and ORM-friendly fields. Decode them into domain values at the boundary and encode domain outputs back into transport forms. Do not weaken the core merely to make a serializer convenient.

### Mistake 8: creating types without domain value

Hundreds of wrappers with no distinction, constraint, or behavior make a model harder to navigate. Type precision has a maintenance cost; spend it on important domain knowledge.

### Mistake 9: modelling only nouns

The heart of many domains is a decision or workflow. Model verbs through typed functions, commands, events, policies, and transitions.

### Mistake 10: mistaking tactical F# elegance for strategic DDD

Beautiful unions do not identify bounded contexts, resolve conflicting terminology, or determine consistency boundaries. Those require discovery with domain experts and iterative design.

---

## 19. A practical modelling process

1. **Collect concrete scenarios.** Include failures and edge cases, not only the happy path.
2. **Build a glossary.** Resolve overloaded or ambiguous terms.
3. **Identify context boundaries.** Ask where each term and rule is valid.
4. **Write type sketches.** Use records for AND and unions for OR.
5. **Write workflow signatures.** Describe inputs, outputs, state, and expected errors.
6. **List invariants.** Separate local value constraints from contextual rules.
7. **Hide constrained representations.** Expose smart constructors and meaningful operations.
8. **Keep decisions pure where practical.** Move I/O and framework concerns to adapters.
9. **Test examples and properties.** Verify rules and preservation of invariants.
10. **Refactor the language.** Treat compiler errors after a type change as a map of affected decisions.
11. **Add architecture only when earned.** Event sourcing, microservices, generic rule engines, and elaborate abstractions are not prerequisites for a good domain model.

---

## 20. Condensed wisdom

- Types are executable domain vocabulary.
- Records model conjunctions; discriminated unions model alternatives.
- A function signature is a compact statement of a use case.
- Prefer strong domain values over repeated validation of primitives.
- Make meaningful illegal states impossible to construct where practical.
- Use `option` for absence and `Result` for expected, actionable rejection.
- Represent change as an explicit transition between immutable values.
- Keep pure decisions separate from effects and framework concerns.
- Let bounded contexts own their language; avoid one universal model.
- Use the compiler as a design assistant, not as a substitute for domain knowledge.
- Precision has a cost. Model the distinctions that protect important rules and support likely change.
- The model is provisional: revise it as understanding improves.

---

## Sources and further reading

### Primary F# domain-modelling material

- Scott Wlaschin, *Domain Modeling Made Functional* — <https://pragprog.com/titles/swdddf/domain-modeling-made-functional/>
- Scott Wlaschin, Domain-Driven Design material — <https://fsharpforfunandprofit.com/ddd/>
- Scott Wlaschin, “Designing with Types” series — <https://fsharpforfunandprofit.com/series/designing-with-types/>
- Scott Wlaschin, “Single case union types” — <https://fsharpforfunandprofit.com/posts/designing-with-types-single-case-dus/>
- Scott Wlaschin, “Making illegal states unrepresentable” — <https://fsharpforfunandprofit.com/posts/designing-with-types-making-illegal-states-unrepresentable/>
- Scott Wlaschin, “Making state explicit” — <https://fsharpforfunandprofit.com/posts/designing-with-types-representing-states/>
- Scott Wlaschin, “Constrained strings” — <https://fsharpforfunandprofit.com/posts/designing-with-types-more-semantic-types/>
- Scott Wlaschin, “Non-string types” — <https://fsharpforfunandprofit.com/posts/designing-with-types-non-strings/>
- Scott Wlaschin, “Railway Oriented Programming” — <https://fsharpforfunandprofit.com/rop/>
- Scott Wlaschin, “Against Railway-Oriented Programming” — <https://fsharpforfunandprofit.com/posts/against-railway-oriented-programming/>

### Official F# references

- F# types — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/fsharp-types>
- Records — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/records>
- Discriminated unions — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/discriminated-unions>
- Options — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/options>
- Results — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/results>
- Units of measure — <https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/units-of-measure>

### Wider design context

- Eric Evans, *Domain-Driven Design: Tackling Complexity in the Heart of Software*.
- Martin Fowler, “Domain Model” — <https://martinfowler.com/eaaCatalog/domainModel.html>
- Alistair Cockburn, “Hexagonal Architecture” — <https://alistair.cockburn.us/hexagonal-architecture/>
- Alexis King, “Parse, don't validate” — <https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/>

The Scott Wlaschin sources provide the main synthesis of DDD and idiomatic F#. The Microsoft references establish the precise language mechanisms. The wider sources supply architectural and modelling context; “parse, don't validate” is not F#-specific but closely expresses the boundary discipline used by constrained domain types.
