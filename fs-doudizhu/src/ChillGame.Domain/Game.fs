namespace ChillGame.Domain

[<RequireQualifiedAccess>]
type Bid =
    | One
    | Two
    | Three

[<RequireQualifiedAccess>]
module Bid =
    let value = function
        | Bid.One -> 1
        | Bid.Two -> 2
        | Bid.Three -> 3

[<RequireQualifiedAccess>]
type BidAction =
    | Pass
    | Place of Bid

[<RequireQualifiedAccess>]
type PlayerRole =
    | Landlord
    | Farmer

[<RequireQualifiedAccess>]
type WinningSide =
    | Landlord
    | Farmers

[<RequireQualifiedAccess>]
type Spring =
    | None
    | LandlordSpring
    | FarmerSpring

/// Signed score points.
type Score = private Score of int

[<RequireQualifiedAccess>]
module Score =
    let value (Score value) = value

/// Final zero-sum score changes for all three players.
type Settlement =
    private
        { WinningSide: WinningSide
          WinningPlayer: PlayerId
          PerFarmerStake: int
          BombCount: int
          RocketCount: int
          Spring: Spring
          Deltas: Map<PlayerId, Score> }

[<RequireQualifiedAccess>]
module Settlement =
    let winningSide settlement = settlement.WinningSide
    let winningPlayer settlement = settlement.WinningPlayer
    let perFarmerStake settlement = settlement.PerFarmerStake
    let bombCount settlement = settlement.BombCount
    let rocketCount settlement = settlement.RocketCount
    let spring settlement = settlement.Spring
    let deltas settlement = settlement.Deltas
    let scoreFor playerId settlement = settlement.Deltas |> Map.tryFind playerId

[<RequireQualifiedAccess>]
type GamePhase =
    | AwaitingDeal
    | Bidding
    | Playing
    | Finished

[<RequireQualifiedAccess>]
type CommandName =
    | Deal
    | Bid
    | PlayCards
    | Pass

[<RequireQualifiedAccess>]
type GameCreationError =
    | InvalidScoringMultiplier of name: string * value: int

[<RequireQualifiedAccess>]
type GameError =
    | CommandNotAllowed of command: CommandName * phase: GamePhase
    | UnknownPlayer of PlayerId
    | NotPlayersTurn of expected: PlayerId * actual: PlayerId
    | BidMustExceed of current: Bid
    | InvalidCombination of CombinationError
    | DuplicateCardsSelected of Card list
    | CardsNotHeld of Card list
    | PlayDoesNotBeatCurrentLead
    | CannotPassWhenLeading

[<RequireQualifiedAccess>]
type GameCommand =
    | Deal of deck: DeckOrder * auctionStarter: PlayerId
    | Bid of player: PlayerId * action: BidAction
    | PlayCards of player: PlayerId * cards: Card list
    | Pass of player: PlayerId

[<RequireQualifiedAccess>]
type GameEvent =
    | CardsDealt of dealNumber: int * auctionStarter: PlayerId
    | AuctionPassed of PlayerId
    | BidPlaced of PlayerId * Bid
    | DealVoided of dealNumber: int
    | LandlordChosen of landlord: PlayerId * bid: Bid * revealedBottomCards: Card list option
    | CardsPlayed of PlayerId * Combination
    | TurnPassed of PlayerId
    | LeadCleared of nextLeader: PlayerId
    | GameFinished of Settlement

/// Public auction information. Hands remain accessible only through an explicit query.
type BiddingView =
    { DealNumber: int
      CurrentBidder: PlayerId
      HighestBid: (PlayerId * Bid) option
      ConsecutivePasses: int
      HandCounts: Map<PlayerId, int> }

/// Public information about the current lead.
type LeadView =
    { Player: PlayerId
      Combination: Combination }

/// Public playing information.
type PlayingView =
    { DealNumber: int
      Landlord: PlayerId
      WinningBid: Bid
      CurrentPlayer: PlayerId
      CurrentLead: LeadView option
      ConsecutivePasses: int
      HandCounts: Map<PlayerId, int>
      BombsPlayed: int
      RocketsPlayed: int }

/// Public information after settlement.
type FinishedView =
    { DealNumber: int
      Landlord: PlayerId
      HandCounts: Map<PlayerId, int>
      Settlement: Settlement }

[<RequireQualifiedAccess>]
type GameStatus =
    | AwaitingDeal of dealNumber: int
    | Bidding of BiddingView
    | Playing of PlayingView
    | Finished of FinishedView

type private AwaitingDealState = { DealNumber: int }

type private HighestBid = { Bidder: PlayerId; Bid: Bid }

type private BiddingState =
    { DealNumber: int
      Hands: Map<PlayerId, Hand>
      BottomCards: Card list
      CurrentBidder: PlayerId
      HighestBid: HighestBid option
      ConsecutivePasses: int }

type private Lead =
    { Player: PlayerId
      Combination: Combination }

type private PlayingState =
    { DealNumber: int
      Hands: Map<PlayerId, Hand>
      PlayedCards: Set<Card>
      Landlord: PlayerId
      WinningBid: Bid
      CurrentPlayer: PlayerId
      CurrentLead: Lead option
      ConsecutivePasses: int
      BombsPlayed: int
      RocketsPlayed: int
      PlaysByPlayer: Map<PlayerId, int> }

type private FinishedState =
    { DealNumber: int
      Hands: Map<PlayerId, Hand>
      PlayedCards: Set<Card>
      Landlord: PlayerId
      Settlement: Settlement }

[<RequireQualifiedAccess>]
type private InternalGameState =
    | AwaitingDeal of AwaitingDealState
    | Bidding of BiddingState
    | Playing of PlayingState
    | Finished of FinishedState

/// Aggregate root for one three-player hand.
type Game =
    private
        { Id: GameId
          Players: Players
          Rules: RuleSet
          Version: int64
          State: InternalGameState }

[<RequireQualifiedAccess>]
module Game =
    let private phaseOf = function
        | InternalGameState.AwaitingDeal _ -> GamePhase.AwaitingDeal
        | InternalGameState.Bidding _ -> GamePhase.Bidding
        | InternalGameState.Playing _ -> GamePhase.Playing
        | InternalGameState.Finished _ -> GamePhase.Finished

    let private validateRules rules =
        [ "bomb", rules.Scoring.BombMultiplier
          "rocket", rules.Scoring.RocketMultiplier
          "spring", rules.Scoring.SpringMultiplier ]
        |> List.tryFind (fun (_, value) -> value < 1)
        |> function
            | Some(name, value) -> Error(GameCreationError.InvalidScoringMultiplier(name, value))
            | None -> Ok rules

    let create id players rules =
        validateRules rules
        |> Result.map (fun validRules ->
            { Id = id
              Players = players
              Rules = validRules
              Version = 0L
              State = InternalGameState.AwaitingDeal { DealNumber = 1 } })

    let id game = game.Id
    let players game = game.Players
    let rules game = game.Rules
    let version game = game.Version
    let phase game = phaseOf game.State

    let tryRole playerId game =
        if not (Players.contains playerId game.Players) then
            None
        else
            let roleFor landlord =
                if playerId = landlord then PlayerRole.Landlord else PlayerRole.Farmer

            match game.State with
            | InternalGameState.Playing state -> Some(roleFor state.Landlord)
            | InternalGameState.Finished state -> Some(roleFor state.Landlord)
            | _ -> None

    let private handCounts hands = hands |> Map.map (fun _ hand -> Hand.count hand)

    let status game =
        match game.State with
        | InternalGameState.AwaitingDeal state ->
            GameStatus.AwaitingDeal state.DealNumber
        | InternalGameState.Bidding state ->
            GameStatus.Bidding
                { DealNumber = state.DealNumber
                  CurrentBidder = state.CurrentBidder
                  HighestBid = state.HighestBid |> Option.map (fun bid -> bid.Bidder, bid.Bid)
                  ConsecutivePasses = state.ConsecutivePasses
                  HandCounts = handCounts state.Hands }
        | InternalGameState.Playing state ->
            GameStatus.Playing
                { DealNumber = state.DealNumber
                  Landlord = state.Landlord
                  WinningBid = state.WinningBid
                  CurrentPlayer = state.CurrentPlayer
                  CurrentLead =
                    state.CurrentLead
                    |> Option.map (fun lead ->
                        { Player = lead.Player
                          Combination = lead.Combination })
                  ConsecutivePasses = state.ConsecutivePasses
                  HandCounts = handCounts state.Hands
                  BombsPlayed = state.BombsPlayed
                  RocketsPlayed = state.RocketsPlayed }
        | InternalGameState.Finished state ->
            GameStatus.Finished
                { DealNumber = state.DealNumber
                  Landlord = state.Landlord
                  HandCounts = handCounts state.Hands
                  Settlement = state.Settlement }

    /// Full-hand query intended for trusted game/application logic. A network adapter should
    /// expose only the requesting player's hand.
    let tryHand playerId game =
        match game.State with
        | InternalGameState.AwaitingDeal _ -> None
        | InternalGameState.Bidding state -> state.Hands |> Map.tryFind playerId
        | InternalGameState.Playing state -> state.Hands |> Map.tryFind playerId
        | InternalGameState.Finished state -> state.Hands |> Map.tryFind playerId

    let private commandNotAllowed command game =
        Error(GameError.CommandNotAllowed(command, phase game))

    let private nextPlayer playerId game =
        match Players.nextId playerId game.Players with
        | Some next -> next
        | None -> failwith "Internal invariant broken: current actor is not seated"

    let private knownHand cards =
        match Hand.create cards with
        | Ok hand -> hand
        | Error _ -> failwith "Internal invariant broken: validated deck produced an invalid hand"

    let private dealHands game deck =
        let playerIds = Players.ids game.Players
        let dealtCards = deck |> DeckOrder.cards |> List.take 51

        playerIds
        |> List.mapi (fun playerIndex playerId ->
            let cards =
                dealtCards
                |> List.indexed
                |> List.choose (fun (cardIndex, card) ->
                    if cardIndex % 3 = playerIndex then Some card else None)

            playerId, knownHand cards)
        |> Map.ofList

    let private withState state game =
        { game with
            Version = game.Version + 1L
            State = state }

    let private handleDeal deck auctionStarter (state: AwaitingDealState) game =
        if not (Players.contains auctionStarter game.Players) then
            Error(GameError.UnknownPlayer auctionStarter)
        else
            let allCards = DeckOrder.cards deck
            let hands = dealHands game deck
            let bottomCards = allCards |> List.skip 51

            let bidding =
                { DealNumber = state.DealNumber
                  Hands = hands
                  BottomCards = bottomCards
                  CurrentBidder = auctionStarter
                  HighestBid = None
                  ConsecutivePasses = 0 }

            let updated = withState (InternalGameState.Bidding bidding) game
            Ok(updated, [ GameEvent.CardsDealt(state.DealNumber, auctionStarter) ])

    let private startPlaying (highest: HighestBid) (state: BiddingState) game =
        let landlordHand = state.Hands |> Map.find highest.Bidder

        let enlargedHand =
            match Hand.add state.BottomCards landlordHand with
            | Ok hand -> hand
            | Error _ -> failwith "Internal invariant broken: bottom cards already belong to a hand"

        let hands = state.Hands |> Map.add highest.Bidder enlargedHand
        let playCounts = Players.ids game.Players |> List.map (fun id -> id, 0) |> Map.ofList

        let playing =
            { DealNumber = state.DealNumber
              Hands = hands
              PlayedCards = Set.empty
              Landlord = highest.Bidder
              WinningBid = highest.Bid
              CurrentPlayer = highest.Bidder
              CurrentLead = None
              ConsecutivePasses = 0
              BombsPlayed = 0
              RocketsPlayed = 0
              PlaysByPlayer = playCounts }

        let revealed =
            if game.Rules.RevealBottomCards then Some state.BottomCards else None

        InternalGameState.Playing playing,
        GameEvent.LandlordChosen(highest.Bidder, highest.Bid, revealed)

    let private handleAuctionPass player (state: BiddingState) game =
        if not (Players.contains player game.Players) then
            Error(GameError.UnknownPlayer player)
        elif player <> state.CurrentBidder then
            Error(GameError.NotPlayersTurn(state.CurrentBidder, player))
        else
            let passCount = state.ConsecutivePasses + 1
            let passEvent = GameEvent.AuctionPassed player

            match state.HighestBid with
            | None when passCount = 3 ->
                let awaiting =
                    InternalGameState.AwaitingDeal
                        { DealNumber = state.DealNumber + 1 }

                let updated = withState awaiting game
                Ok(updated, [ passEvent; GameEvent.DealVoided state.DealNumber ])
            | Some highest when passCount = 2 ->
                let playing, landlordEvent = startPlaying highest state game
                let updated = withState playing game
                Ok(updated, [ passEvent; landlordEvent ])
            | _ ->
                let bidding =
                    { state with
                        CurrentBidder = nextPlayer player game
                        ConsecutivePasses = passCount }

                let updated = withState (InternalGameState.Bidding bidding) game
                Ok(updated, [ passEvent ])

    let private handleBid player bid (state: BiddingState) game =
        if not (Players.contains player game.Players) then
            Error(GameError.UnknownPlayer player)
        elif player <> state.CurrentBidder then
            Error(GameError.NotPlayersTurn(state.CurrentBidder, player))
        else
            match state.HighestBid with
            | Some current when Bid.value bid <= Bid.value current.Bid ->
                Error(GameError.BidMustExceed current.Bid)
            | _ ->
                let highest = { Bidder = player; Bid = bid }
                let bidEvent = GameEvent.BidPlaced(player, bid)

                if bid = Bid.Three then
                    let playing, landlordEvent = startPlaying highest state game
                    let updated = withState playing game
                    Ok(updated, [ bidEvent; landlordEvent ])
                else
                    let bidding =
                        { state with
                            CurrentBidder = nextPlayer player game
                            HighestBid = Some highest
                            ConsecutivePasses = 0 }

                    let updated = withState (InternalGameState.Bidding bidding) game
                    Ok(updated, [ bidEvent ])

    let private mapHandError = function
        | HandError.DuplicateCards cards -> GameError.DuplicateCardsSelected cards
        | HandError.CardsNotHeld cards -> GameError.CardsNotHeld cards

    let private power factor exponent =
        [ 1..exponent ] |> List.fold (fun total _ -> total * factor) 1

    let private calculateSettlement winner winningSide (state: PlayingState) game =
        let farmerIds =
            Players.ids game.Players |> List.filter (fun id -> id <> state.Landlord)

        let landlordPlayCount = state.PlaysByPlayer |> Map.find state.Landlord

        let farmersPlayCount =
            farmerIds
            |> List.sumBy (fun farmer -> state.PlaysByPlayer |> Map.find farmer)

        let spring =
            match winningSide with
            | WinningSide.Landlord when farmersPlayCount = 0 -> Spring.LandlordSpring
            | WinningSide.Farmers when landlordPlayCount = 1 -> Spring.FarmerSpring
            | _ -> Spring.None

        let scoring = game.Rules.Scoring

        let springFactor =
            match spring with
            | Spring.None -> 1
            | _ -> scoring.SpringMultiplier

        let perFarmerStake =
            Bid.value state.WinningBid
            * power scoring.BombMultiplier state.BombsPlayed
            * power scoring.RocketMultiplier state.RocketsPlayed
            * springFactor

        let landlordDelta, farmerDelta =
            match winningSide with
            | WinningSide.Landlord -> 2 * perFarmerStake, -perFarmerStake
            | WinningSide.Farmers -> -2 * perFarmerStake, perFarmerStake

        let deltas =
            [ state.Landlord, Score landlordDelta
              yield! farmerIds |> List.map (fun farmer -> farmer, Score farmerDelta) ]
            |> Map.ofList

        { WinningSide = winningSide
          WinningPlayer = winner
          PerFarmerStake = perFarmerStake
          BombCount = state.BombsPlayed
          RocketCount = state.RocketsPlayed
          Spring = spring
          Deltas = deltas }

    let private handlePlay player selectedCards (state: PlayingState) game =
        if not (Players.contains player game.Players) then
            Error(GameError.UnknownPlayer player)
        elif player <> state.CurrentPlayer then
            Error(GameError.NotPlayersTurn(state.CurrentPlayer, player))
        else
            let currentHand = state.Hands |> Map.find player

            match Hand.remove selectedCards currentHand with
            | Error handError -> Error(mapHandError handError)
            | Ok remainingHand ->
                match Combination.classify game.Rules selectedCards with
                | Error combinationError ->
                    Error(GameError.InvalidCombination combinationError)
                | Ok combination ->
                    let beatsLead =
                        match state.CurrentLead with
                        | None -> true
                        | Some lead -> Combination.beats lead.Combination combination

                    if not beatsLead then
                        Error GameError.PlayDoesNotBeatCurrentLead
                    else
                        let hands = state.Hands |> Map.add player remainingHand

                        let playsByPlayer =
                            state.PlaysByPlayer
                            |> Map.change player (Option.map ((+) 1))

                        let bombsPlayed, rocketsPlayed =
                            match Combination.kind combination with
                            | CombinationKind.Bomb -> state.BombsPlayed + 1, state.RocketsPlayed
                            | CombinationKind.Rocket -> state.BombsPlayed, state.RocketsPlayed + 1
                            | _ -> state.BombsPlayed, state.RocketsPlayed

                        let playedCards = Set.union state.PlayedCards (Set.ofList selectedCards)

                        let afterPlay =
                            { state with
                                Hands = hands
                                PlayedCards = playedCards
                                CurrentLead = Some { Player = player; Combination = combination }
                                ConsecutivePasses = 0
                                BombsPlayed = bombsPlayed
                                RocketsPlayed = rocketsPlayed
                                PlaysByPlayer = playsByPlayer }

                        let playEvent = GameEvent.CardsPlayed(player, combination)

                        if Hand.isEmpty remainingHand then
                            let winningSide =
                                if player = state.Landlord then
                                    WinningSide.Landlord
                                else
                                    WinningSide.Farmers

                            let settlement = calculateSettlement player winningSide afterPlay game

                            let finished =
                                { DealNumber = state.DealNumber
                                  Hands = hands
                                  PlayedCards = playedCards
                                  Landlord = state.Landlord
                                  Settlement = settlement }

                            let updated = withState (InternalGameState.Finished finished) game
                            Ok(updated, [ playEvent; GameEvent.GameFinished settlement ])
                        else
                            let playing =
                                { afterPlay with
                                    CurrentPlayer = nextPlayer player game }

                            let updated = withState (InternalGameState.Playing playing) game
                            Ok(updated, [ playEvent ])

    let private handlePlayPass player (state: PlayingState) game =
        if not (Players.contains player game.Players) then
            Error(GameError.UnknownPlayer player)
        elif player <> state.CurrentPlayer then
            Error(GameError.NotPlayersTurn(state.CurrentPlayer, player))
        else
            match state.CurrentLead with
            | None -> Error GameError.CannotPassWhenLeading
            | Some lead ->
                let passEvent = GameEvent.TurnPassed player
                let passCount = state.ConsecutivePasses + 1

                if passCount = 2 then
                    let playing =
                        { state with
                            CurrentPlayer = lead.Player
                            CurrentLead = None
                            ConsecutivePasses = 0 }

                    let updated = withState (InternalGameState.Playing playing) game
                    Ok(updated, [ passEvent; GameEvent.LeadCleared lead.Player ])
                else
                    let playing =
                        { state with
                            CurrentPlayer = nextPlayer player game
                            ConsecutivePasses = passCount }

                    let updated = withState (InternalGameState.Playing playing) game
                    Ok(updated, [ passEvent ])

    let execute command game =
        match command, game.State with
        | GameCommand.Deal(deck, starter), InternalGameState.AwaitingDeal state ->
            handleDeal deck starter state game
        | GameCommand.Bid(player, BidAction.Pass), InternalGameState.Bidding state ->
            handleAuctionPass player state game
        | GameCommand.Bid(player, BidAction.Place bid), InternalGameState.Bidding state ->
            handleBid player bid state game
        | GameCommand.PlayCards(player, cards), InternalGameState.Playing state ->
            handlePlay player cards state game
        | GameCommand.Pass player, InternalGameState.Playing state ->
            handlePlayPass player state game
        | GameCommand.Deal _, _ -> commandNotAllowed CommandName.Deal game
        | GameCommand.Bid _, _ -> commandNotAllowed CommandName.Bid game
        | GameCommand.PlayCards _, _ -> commandNotAllowed CommandName.PlayCards game
        | GameCommand.Pass _, _ -> commandNotAllowed CommandName.Pass game
