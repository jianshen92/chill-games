module ChillGame.Domain.Tests.GameTests

open System
open Xunit
open ChillGame.Domain
open ChillGame.Domain.Tests.TestHelpers

let biddingStatus game =
    match Game.status game with
    | GameStatus.Bidding view -> view
    | status -> failwithf "Expected bidding status, got %A" status

let playingStatus game =
    match Game.status game with
    | GameStatus.Playing view -> view
    | status -> failwithf "Expected playing status, got %A" status

let finishedStatus game =
    match Game.status game with
    | GameStatus.Finished view -> view
    | status -> failwithf "Expected finished status, got %A" status

let score player settlement =
    Settlement.scoreFor player settlement |> Option.get |> Score.value

let kindOf cards = classify cards |> Combination.kind

[<Fact>]
let ``standard deck contains 54 unique physical cards`` () =
    Assert.Equal(54, List.length Card.standardDeck)
    Assert.Equal(54, Card.standardDeck |> Set.ofList |> Set.count)
    Assert.Equal(
        52,
        Card.standardDeck
        |> List.filter (Card.rank >> CardRank.isStandard)
        |> List.length
    )

[<Fact>]
let ``deal gives each player 17 cards and starts the requested bidder`` () =
    let game = newGame () |> deal standardDeck
    let view = biddingStatus game

    Assert.Equal(firstId, view.CurrentBidder)
    Assert.Equal(17, view.HandCounts[firstId])
    Assert.Equal(17, view.HandCounts[secondId])
    Assert.Equal(17, view.HandCounts[thirdId])
    Assert.Equal(1L, Game.version game)

[<Fact>]
let ``three opening passes void the deal`` () =
    let game0 = newGame () |> deal standardDeck
    let game1, _ = execute (GameCommand.Bid(firstId, BidAction.Pass)) game0
    let game2, _ = execute (GameCommand.Bid(secondId, BidAction.Pass)) game1
    let game3, events = execute (GameCommand.Bid(thirdId, BidAction.Pass)) game2

    match Game.status game3 with
    | GameStatus.AwaitingDeal 2 -> ()
    | status -> failwithf "Unexpected status: %A" status

    Assert.Contains(GameEvent.DealVoided 1, events)
    Assert.Equal(4L, Game.version game3)

[<Fact>]
let ``auction continues until two passes follow the highest bid`` () =
    let game0 = newGame () |> deal standardDeck

    let game1, _ =
        execute (GameCommand.Bid(firstId, BidAction.Place Bid.One)) game0

    let game2, _ = execute (GameCommand.Bid(secondId, BidAction.Pass)) game1

    let game3, _ =
        execute (GameCommand.Bid(thirdId, BidAction.Place Bid.Two)) game2

    let game4, _ = execute (GameCommand.Bid(firstId, BidAction.Pass)) game3
    let game5, _ = execute (GameCommand.Bid(secondId, BidAction.Pass)) game4
    let view = playingStatus game5

    Assert.Equal(thirdId, view.Landlord)
    Assert.Equal(thirdId, view.CurrentPlayer)
    Assert.Equal(Bid.Two, view.WinningBid)
    Assert.Equal(20, view.HandCounts[thirdId])
    Assert.Equal(17, view.HandCounts[firstId])
    Assert.Equal(17, view.HandCounts[secondId])

[<Fact>]
let ``bid of three ends auction immediately`` () =
    let game = newGame () |> deal standardDeck |> bidThree firstId
    let view = playingStatus game

    Assert.Equal(firstId, view.Landlord)
    Assert.Equal(firstId, view.CurrentPlayer)
    Assert.Equal(Bid.Three, view.WinningBid)
    Assert.Equal(20, view.HandCounts[firstId])
    Assert.Equal(Some PlayerRole.Landlord, Game.tryRole firstId game)
    Assert.Equal(Some PlayerRole.Farmer, Game.tryRole secondId game)
    Assert.Equal(Some PlayerRole.Farmer, Game.tryRole thirdId game)

[<Fact>]
let ``bid must exceed current highest bid`` () =
    let game0 = newGame () |> deal standardDeck

    let game1, _ =
        execute (GameCommand.Bid(firstId, BidAction.Place Bid.Two)) game0

    let error =
        Game.execute (GameCommand.Bid(secondId, BidAction.Place Bid.One)) game1
        |> expectError

    Assert.Equal(GameError.BidMustExceed Bid.Two, error)
    Assert.Equal(2L, Game.version game1)

[<Fact>]
let ``two play passes clear the lead and return lead to last player`` () =
    let game0 = newGame () |> deal standardDeck |> bidThree firstId
    let cardToLead = handCards firstId game0 |> List.head
    let game1, _ = execute (GameCommand.PlayCards(firstId, [ cardToLead ])) game0
    let game2, _ = execute (GameCommand.Pass secondId) game1
    let game3, events = execute (GameCommand.Pass thirdId) game2
    let view = playingStatus game3

    Assert.Equal(firstId, view.CurrentPlayer)
    Assert.True(view.CurrentLead.IsNone)
    Assert.Contains(GameEvent.LeadCleared firstId, events)

    let error = Game.execute (GameCommand.Pass firstId) game3 |> expectError
    Assert.Equal(GameError.CannotPassWhenLeading, error)

[<Fact>]
let ``a player cannot play cards not in their hand`` () =
    let game = newGame () |> deal standardDeck |> bidThree firstId
    let otherPlayersCard = handCards secondId game |> List.head

    let error =
        Game.execute (GameCommand.PlayCards(firstId, [ otherPlayersCard ])) game
        |> expectError

    match error with
    | GameError.CardsNotHeld [ actual ] -> Assert.Equal(otherPlayersCard, actual)
    | other -> failwithf "Unexpected error: %A" other

[<Fact>]
let ``a response must beat the current lead`` () =
    let game0 = newGame () |> deal standardDeck |> bidThree firstId
    let highLead = handCards firstId game0 |> List.maxBy Card.strength
    let lowResponse = handCards secondId game0 |> List.minBy Card.strength
    Assert.True(Card.strength highLead > Card.strength lowResponse)

    let game1, _ = execute (GameCommand.PlayCards(firstId, [ highLead ])) game0

    let error =
        Game.execute (GameCommand.PlayCards(secondId, [ lowResponse ])) game1
        |> expectError

    Assert.Equal(GameError.PlayDoesNotBeatCurrentLead, error)

[<Fact>]
let ``unknown actors are rejected explicitly`` () =
    let game = newGame () |> deal standardDeck
    let stranger = PlayerId.newId ()

    let error =
        Game.execute (GameCommand.Bid(stranger, BidAction.Pass)) game |> expectError

    Assert.Equal(GameError.UnknownPlayer stranger, error)

[<Fact>]
let ``landlord can win with one airplane and receives spring settlement`` () =
    let winningHand =
        triple StandardRank.Three
        @ triple StandardRank.Four
        @ triple StandardRank.Five
        @ triple StandardRank.Six
        @ pair StandardRank.Seven
        @ pair StandardRank.Eight
        @ pair StandardRank.Nine
        @ pair StandardRank.Ten

    Assert.Equal(CombinationKind.AirplaneWithPairs 4, kindOf winningHand)

    let deck = deckWithFirstLandlordHand winningHand
    let game0 = newGame () |> deal deck |> bidThree firstId
    let game1, events = execute (GameCommand.PlayCards(firstId, winningHand)) game0
    let finished = finishedStatus game1
    let settlement = finished.Settlement

    Assert.Equal(WinningSide.Landlord, Settlement.winningSide settlement)
    Assert.Equal(Spring.LandlordSpring, Settlement.spring settlement)
    Assert.Equal(6, Settlement.perFarmerStake settlement)
    Assert.Equal(12, score firstId settlement)
    Assert.Equal(-6, score secondId settlement)
    Assert.Equal(-6, score thirdId settlement)
    Assert.Contains(GameEvent.GameFinished settlement, events)

[<Fact>]
let ``bomb and spring multipliers compose in settlement`` () =
    let bomb = quad StandardRank.Three

    let airplane =
        triple StandardRank.Four
        @ triple StandardRank.Five
        @ triple StandardRank.Six
        @ triple StandardRank.Seven
        @ one StandardRank.Eight
        @ one StandardRank.Nine
        @ one StandardRank.Ten
        @ one StandardRank.Jack

    Assert.Equal(CombinationKind.AirplaneWithSingles 4, kindOf airplane)

    let deck = deckWithFirstLandlordHand (bomb @ airplane)
    let game0 = newGame () |> deal deck |> bidThree firstId
    let game1, _ = execute (GameCommand.PlayCards(firstId, bomb)) game0
    let game2, _ = execute (GameCommand.Pass secondId) game1
    let game3, _ = execute (GameCommand.Pass thirdId) game2
    let game4, _ = execute (GameCommand.PlayCards(firstId, airplane)) game3
    let settlement = (finishedStatus game4).Settlement

    Assert.Equal(1, Settlement.bombCount settlement)
    Assert.Equal(Spring.LandlordSpring, Settlement.spring settlement)
    Assert.Equal(12, Settlement.perFarmerStake settlement)
    Assert.Equal(24, score firstId settlement)

[<Fact>]
let ``rocket and spring multipliers compose in settlement`` () =
    let rocket = [ smallJoker; bigJoker ]
    let lowPair = pair StandardRank.Three

    let airplane =
        triple StandardRank.Four
        @ triple StandardRank.Five
        @ triple StandardRank.Six
        @ triple StandardRank.Seven
        @ one StandardRank.Eight
        @ one StandardRank.Nine
        @ one StandardRank.Ten
        @ one StandardRank.Jack

    let deck = deckWithFirstLandlordHand (rocket @ lowPair @ airplane)
    let game0 = newGame () |> deal deck |> bidThree firstId
    let game1, _ = execute (GameCommand.PlayCards(firstId, rocket)) game0
    let game2, _ = execute (GameCommand.Pass secondId) game1
    let game3, _ = execute (GameCommand.Pass thirdId) game2
    let game4, _ = execute (GameCommand.PlayCards(firstId, lowPair)) game3
    let game5, _ = execute (GameCommand.Pass secondId) game4
    let game6, _ = execute (GameCommand.Pass thirdId) game5
    let game7, _ = execute (GameCommand.PlayCards(firstId, airplane)) game6
    let settlement = (finishedStatus game7).Settlement

    Assert.Equal(1, Settlement.rocketCount settlement)
    Assert.Equal(Spring.LandlordSpring, Settlement.spring settlement)
    Assert.Equal(12, Settlement.perFarmerStake settlement)
    Assert.Equal(24, score firstId settlement)

[<Fact>]
let ``farmers win together and anti-spring applies when landlord played only once`` () =
    let farmerFinisher =
        triple StandardRank.Four
        @ triple StandardRank.Five
        @ triple StandardRank.Six
        @ triple StandardRank.Seven
        @ one StandardRank.Eight
        @ one StandardRank.Nine
        @ one StandardRank.Ten
        @ one StandardRank.Jack

    let farmerHighSingle = card Suit.Clubs StandardRank.Two
    let secondHand = farmerHighSingle :: farmerFinisher
    let landlordLead = card Suit.Clubs StandardRank.Three

    let availableAfterSecond =
        Card.standardDeck
        |> List.filter (fun card -> not (Set.contains card (Set.ofList secondHand)))

    let firstRest =
        availableAfterSecond
        |> List.filter ((<>) landlordLead)
        |> List.take 16

    let firstHand = landlordLead :: firstRest
    let used = Set.ofList (firstHand @ secondHand)
    let remaining = Card.standardDeck |> List.filter (fun card -> not (Set.contains card used))
    let bottom = remaining |> List.take 3
    let thirdHand = remaining |> List.skip 3
    let deck = deckWithHands firstHand secondHand thirdHand bottom

    let game0 = newGame () |> deal deck |> bidThree firstId
    let game1, _ = execute (GameCommand.PlayCards(firstId, [ landlordLead ])) game0
    let game2, _ = execute (GameCommand.PlayCards(secondId, [ farmerHighSingle ])) game1
    let game3, _ = execute (GameCommand.Pass thirdId) game2
    let game4, _ = execute (GameCommand.Pass firstId) game3
    let game5, _ = execute (GameCommand.PlayCards(secondId, farmerFinisher)) game4
    let settlement = (finishedStatus game5).Settlement

    Assert.Equal(WinningSide.Farmers, Settlement.winningSide settlement)
    Assert.Equal(secondId, Settlement.winningPlayer settlement)
    Assert.Equal(Spring.FarmerSpring, Settlement.spring settlement)
    Assert.Equal(6, Settlement.perFarmerStake settlement)
    Assert.Equal(-12, score firstId settlement)
    Assert.Equal(6, score secondId settlement)
    Assert.Equal(6, score thirdId settlement)
    Assert.Equal(0, Settlement.deltas settlement |> Map.toList |> List.sumBy (snd >> Score.value))
