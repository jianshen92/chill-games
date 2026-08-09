module ChillGame.Domain.Tests.TestHelpers

open System
open Xunit
open ChillGame.Domain

let unwrap = function
    | Ok value -> value
    | Error error -> failwithf "Expected Ok but got Error: %A" error

let expectError = function
    | Ok value -> failwithf "Expected Error but got Ok: %A" value
    | Error error -> error

let card suit rank = Card.Standard(suit, rank)
let smallJoker = Card.Joker Joker.Small
let bigJoker = Card.Joker Joker.Big

let suits = [ Suit.Clubs; Suit.Diamonds; Suit.Hearts; Suit.Spades ]

let cardsOf rank count =
    suits |> List.take count |> List.map (fun suit -> card suit rank)

let one rank = cardsOf rank 1
let pair rank = cardsOf rank 2
let triple rank = cardsOf rank 3
let quad rank = cardsOf rank 4

let classify cards =
    Combination.classify RuleSet.standardThreePlayer cards |> unwrap

let player number name =
    let id = PlayerId.create(Guid.Parse(sprintf "00000000-0000-0000-0000-%012d" number))
    let playerName = PlayerName.create name |> unwrap
    Player.create id playerName

let firstPlayer = player 1 "Alice"
let secondPlayer = player 2 "Bob"
let thirdPlayer = player 3 "Chen"
let players = Players.create firstPlayer secondPlayer thirdPlayer |> unwrap
let firstId = Player.id firstPlayer
let secondId = Player.id secondPlayer
let thirdId = Player.id thirdPlayer

let newGame () =
    Game.create (GameId.newId ()) players RuleSet.standardThreePlayer |> unwrap

let standardDeck = DeckOrder.create Card.standardDeck |> unwrap

let execute command game = Game.execute command game |> unwrap

let deal deck game =
    execute (GameCommand.Deal(deck, firstId)) game |> fst

let bidThree player game =
    execute (GameCommand.Bid(player, BidAction.Place Bid.Three)) game |> fst

let handCards player game =
    Game.tryHand player game |> Option.map Hand.cards |> Option.defaultWith (fun () -> failwith "No hand")

let private without selected allCards =
    Set.difference (Set.ofList allCards) (Set.ofList selected) |> Set.toList

/// Build a valid deck order that gives the supplied 20 cards to the first player after
/// they become landlord: 17 cards through the deal and the final three bottom cards.
let deckWithFirstLandlordHand landlordCards =
    Assert.Equal(20, List.length landlordCards)
    Assert.Equal(20, landlordCards |> Set.ofList |> Set.count)

    let dealtToFirst = landlordCards |> List.take 17
    let bottom = landlordCards |> List.skip 17
    let others = without landlordCards Card.standardDeck
    let dealtToSecond = others |> List.take 17
    let dealtToThird = others |> List.skip 17

    let first51 =
        [ for index in 0..16 do
              yield dealtToFirst[index]
              yield dealtToSecond[index]
              yield dealtToThird[index] ]

    DeckOrder.create (first51 @ bottom) |> unwrap

/// Build a valid deck order from exact 17-card pre-auction hands and three bottom cards.
let deckWithHands
    (firstHand: Card list)
    (secondHand: Card list)
    (thirdHand: Card list)
    (bottom: Card list)
    =
    for hand in [ firstHand; secondHand; thirdHand ] do
        Assert.Equal(17, List.length hand)
        Assert.Equal(17, hand |> Set.ofList |> Set.count)

    Assert.Equal(3, List.length bottom)

    let all = firstHand @ secondHand @ thirdHand @ bottom
    Assert.True(Set.ofList Card.standardDeck = Set.ofList all)

    let first51 =
        [ for index in 0..16 do
              yield firstHand[index]
              yield secondHand[index]
              yield thirdHand[index] ]

    DeckOrder.create (first51 @ bottom) |> unwrap
