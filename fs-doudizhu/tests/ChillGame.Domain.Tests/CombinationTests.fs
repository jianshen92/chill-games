module ChillGame.Domain.Tests.CombinationTests

open Xunit
open ChillGame.Domain
open ChillGame.Domain.Tests.TestHelpers

let kindOf cards = classify cards |> Combination.kind

[<Fact>]
let ``all basic combination families classify`` () =
    let cases =
        [ [ bigJoker ], CombinationKind.Single
          pair StandardRank.Three, CombinationKind.Pair
          triple StandardRank.Four, CombinationKind.Triple
          triple StandardRank.Five @ one StandardRank.King,
          CombinationKind.TripleWithSingle
          triple StandardRank.Six @ pair StandardRank.Ace,
          CombinationKind.TripleWithPair
          [ StandardRank.Three
            StandardRank.Four
            StandardRank.Five
            StandardRank.Six
            StandardRank.Seven ]
          |> List.collect one,
          CombinationKind.Straight 5
          [ StandardRank.Eight; StandardRank.Nine; StandardRank.Ten ]
          |> List.collect pair,
          CombinationKind.ConsecutivePairs 3
          triple StandardRank.Four @ triple StandardRank.Five,
          CombinationKind.Airplane 2
          triple StandardRank.Six
          @ triple StandardRank.Seven
          @ one StandardRank.Nine
          @ one StandardRank.Ten,
          CombinationKind.AirplaneWithSingles 2
          triple StandardRank.Eight
          @ triple StandardRank.Nine
          @ pair StandardRank.Jack
          @ pair StandardRank.Queen,
          CombinationKind.AirplaneWithPairs 2
          quad StandardRank.Three, CombinationKind.Bomb
          [ smallJoker; bigJoker ], CombinationKind.Rocket
          quad StandardRank.Six @ one StandardRank.Eight @ one StandardRank.Nine,
          CombinationKind.FourWithSingles
          quad StandardRank.Jack @ pair StandardRank.Nine @ pair StandardRank.Queen,
          CombinationKind.FourWithPairs ]

    for cards, expectedKind in cases do
        Assert.Equal(expectedKind, kindOf cards)

[<Fact>]
let ``sequences exclude two and jokers`` () =
    let withTwo =
        [ StandardRank.Ten
          StandardRank.Jack
          StandardRank.Queen
          StandardRank.King
          StandardRank.Ace
          StandardRank.Two ]
        |> List.collect one

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer withTwo |> expectError
    )

    let withJoker =
        [ card Suit.Clubs StandardRank.Jack
          card Suit.Clubs StandardRank.Queen
          card Suit.Clubs StandardRank.King
          card Suit.Clubs StandardRank.Ace
          smallJoker ]

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer withJoker |> expectError
    )

[<Fact>]
let ``airplane single wings may form a pair under standard rules`` () =
    let cards =
        triple StandardRank.Three
        @ triple StandardRank.Four
        @ pair StandardRank.Nine

    Assert.Equal(CombinationKind.AirplaneWithSingles 2, kindOf cards)

[<Fact>]
let ``airplane bodies cannot include two`` () =
    let cards = triple StandardRank.Ace @ triple StandardRank.Two

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer cards |> expectError
    )

[<Fact>]
let ``airplane wings cannot use a body rank`` () =
    let cards =
        quad StandardRank.Three
        @ triple StandardRank.Four
        @ one StandardRank.Nine

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer cards |> expectError
    )

[<Fact>]
let ``both jokers cannot be attachments under standard rules`` () =
    let airplane =
        triple StandardRank.Three
        @ triple StandardRank.Four
        @ [ smallJoker; bigJoker ]

    let quadplex = quad StandardRank.Five @ [ smallJoker; bigJoker ]

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer airplane |> expectError
    )

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer quadplex |> expectError
    )

[<Fact>]
let ``quadplex singles must have distinct ranks under standard rules`` () =
    let cards = quad StandardRank.Five @ pair StandardRank.Nine

    Assert.Equal(
        CombinationError.PatternNotRecognized,
        Combination.classify RuleSet.standardThreePlayer cards |> expectError
    )

[<Fact>]
let ``duplicate physical cards are rejected`` () =
    let duplicate = card Suit.Clubs StandardRank.Three

    match Combination.classify RuleSet.standardThreePlayer [ duplicate; duplicate ] with
    | Error(CombinationError.DuplicatePhysicalCards [ actual ]) -> Assert.Equal(duplicate, actual)
    | other -> failwithf "Unexpected result: %A" other

[<Fact>]
let ``higher matching shape beats lower matching shape`` () =
    let lower =
        [ StandardRank.Three
          StandardRank.Four
          StandardRank.Five
          StandardRank.Six
          StandardRank.Seven ]
        |> List.collect one
        |> classify

    let higher =
        [ StandardRank.Four
          StandardRank.Five
          StandardRank.Six
          StandardRank.Seven
          StandardRank.Eight ]
        |> List.collect one
        |> classify

    Assert.True(Combination.beats lower higher)
    Assert.False(Combination.beats higher lower)

[<Fact>]
let ``different sequence lengths do not beat one another`` () =
    let five =
        [ StandardRank.Three
          StandardRank.Four
          StandardRank.Five
          StandardRank.Six
          StandardRank.Seven ]
        |> List.collect one
        |> classify

    let six =
        [ StandardRank.Four
          StandardRank.Five
          StandardRank.Six
          StandardRank.Seven
          StandardRank.Eight
          StandardRank.Nine ]
        |> List.collect one
        |> classify

    Assert.False(Combination.beats five six)
    Assert.False(Combination.beats six five)

[<Fact>]
let ``bomb and rocket precedence is explicit`` () =
    let highStraight =
        [ StandardRank.Ten
          StandardRank.Jack
          StandardRank.Queen
          StandardRank.King
          StandardRank.Ace ]
        |> List.collect one
        |> classify

    let lowBomb = quad StandardRank.Three |> classify
    let highBomb = quad StandardRank.Ace |> classify
    let rocket = [ smallJoker; bigJoker ] |> classify

    Assert.True(Combination.beats highStraight lowBomb)
    Assert.True(Combination.beats lowBomb highBomb)
    Assert.True(Combination.beats highBomb rocket)
    Assert.False(Combination.beats rocket highBomb)

[<Fact>]
let ``quadplex is not a bomb`` () =
    let quadplex =
        quad StandardRank.Ace @ one StandardRank.Three @ one StandardRank.Four
        |> classify

    let bomb = quad StandardRank.Three |> classify

    Assert.True(Combination.beats quadplex bomb)
    Assert.False(Combination.beats bomb quadplex)
