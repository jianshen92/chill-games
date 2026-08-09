namespace ChillGame.Domain

[<RequireQualifiedAccess>]
type Suit =
    | Clubs
    | Diamonds
    | Hearts
    | Spades

[<RequireQualifiedAccess>]
type StandardRank =
    | Three
    | Four
    | Five
    | Six
    | Seven
    | Eight
    | Nine
    | Ten
    | Jack
    | Queen
    | King
    | Ace
    | Two

[<RequireQualifiedAccess>]
type Joker =
    | Small
    | Big

/// A physical card. Suits identify standard cards even though suits do not affect play strength.
[<RequireQualifiedAccess>]
type Card =
    | Standard of Suit * StandardRank
    | Joker of Joker

/// The rank used to classify and compare plays.
[<RequireQualifiedAccess>]
type CardRank =
    | Standard of StandardRank
    | Joker of Joker

[<RequireQualifiedAccess>]
module StandardRank =
    let all =
        [ StandardRank.Three
          StandardRank.Four
          StandardRank.Five
          StandardRank.Six
          StandardRank.Seven
          StandardRank.Eight
          StandardRank.Nine
          StandardRank.Ten
          StandardRank.Jack
          StandardRank.Queen
          StandardRank.King
          StandardRank.Ace
          StandardRank.Two ]

    let strength = function
        | StandardRank.Three -> 3
        | StandardRank.Four -> 4
        | StandardRank.Five -> 5
        | StandardRank.Six -> 6
        | StandardRank.Seven -> 7
        | StandardRank.Eight -> 8
        | StandardRank.Nine -> 9
        | StandardRank.Ten -> 10
        | StandardRank.Jack -> 11
        | StandardRank.Queen -> 12
        | StandardRank.King -> 13
        | StandardRank.Ace -> 14
        | StandardRank.Two -> 15

    /// Twos and jokers cannot be part of a sequence.
    let canAppearInSequence rank = rank <> StandardRank.Two

[<RequireQualifiedAccess>]
module CardRank =
    let ofCard = function
        | Card.Standard(_, rank) -> CardRank.Standard rank
        | Card.Joker joker -> CardRank.Joker joker

    let strength = function
        | CardRank.Standard rank -> StandardRank.strength rank
        | CardRank.Joker Joker.Small -> 16
        | CardRank.Joker Joker.Big -> 17

    let isStandard = function
        | CardRank.Standard _ -> true
        | CardRank.Joker _ -> false

[<RequireQualifiedAccess>]
module Card =
    let rank = CardRank.ofCard
    let strength card = rank card |> CardRank.strength

    let standardDeck =
        [ for suit in [ Suit.Clubs; Suit.Diamonds; Suit.Hearts; Suit.Spades ] do
              for rank in StandardRank.all do
                  Card.Standard(suit, rank)
          Card.Joker Joker.Small
          Card.Joker Joker.Big ]

[<RequireQualifiedAccess>]
type DeckError =
    | WrongCardCount of expected: int * actual: int
    | DuplicateCards of Card list
    | MissingCards of Card list

/// A caller-supplied ordering of every card in a standard 54-card deck.
/// Randomness and shuffling live outside the deterministic domain.
type DeckOrder = private DeckOrder of Card list

[<RequireQualifiedAccess>]
module DeckOrder =
    let create cards =
        if List.length cards <> 54 then
            Error(DeckError.WrongCardCount(54, List.length cards))
        else
            let duplicates =
                cards
                |> List.countBy id
                |> List.choose (fun (card, count) -> if count > 1 then Some card else None)

            if not (List.isEmpty duplicates) then
                Error(DeckError.DuplicateCards duplicates)
            else
                let supplied = Set.ofList cards
                let missing = Set.difference (Set.ofList Card.standardDeck) supplied |> Set.toList

                if not (List.isEmpty missing) then
                    Error(DeckError.MissingCards missing)
                else
                    Ok(DeckOrder cards)

    let cards (DeckOrder cards) = cards

[<RequireQualifiedAccess>]
type HandError =
    | DuplicateCards of Card list
    | CardsNotHeld of Card list

/// An immutable set of physical cards.
type Hand = private Hand of Set<Card>

[<RequireQualifiedAccess>]
module Hand =
    let create cards =
        let duplicates =
            cards
            |> List.countBy id
            |> List.choose (fun (card, count) -> if count > 1 then Some card else None)

        if List.isEmpty duplicates then
            Ok(Hand(Set.ofList cards))
        else
            Error(HandError.DuplicateCards duplicates)

    let empty = Hand Set.empty
    let cards (Hand cards) = Set.toList cards
    let count (Hand cards) = Set.count cards
    let isEmpty hand = count hand = 0
    let contains card (Hand cards) = Set.contains card cards

    let add addedCards (Hand cards) =
        let duplicateCards = addedCards |> List.filter (fun card -> Set.contains card cards)

        if List.isEmpty duplicateCards then
            Hand(Set.union cards (Set.ofList addedCards)) |> Ok
        else
            Error(HandError.DuplicateCards duplicateCards)

    let remove selectedCards (Hand cards) =
        let duplicateSelections =
            selectedCards
            |> List.countBy id
            |> List.choose (fun (card, count) -> if count > 1 then Some card else None)

        if not (List.isEmpty duplicateSelections) then
            Error(HandError.DuplicateCards duplicateSelections)
        else
            let selected = Set.ofList selectedCards
            let missing = Set.difference selected cards |> Set.toList

            if List.isEmpty missing then
                Ok(Hand(Set.difference cards selected))
            else
                Error(HandError.CardsNotHeld missing)
