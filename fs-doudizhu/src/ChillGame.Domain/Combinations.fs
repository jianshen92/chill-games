namespace ChillGame.Domain

[<RequireQualifiedAccess>]
type CombinationKind =
    | Single
    | Pair
    | Triple
    | TripleWithSingle
    | TripleWithPair
    | Straight of cardCount: int
    | ConsecutivePairs of pairCount: int
    | Airplane of tripleCount: int
    | AirplaneWithSingles of tripleCount: int
    | AirplaneWithPairs of tripleCount: int
    | FourWithSingles
    | FourWithPairs
    | Bomb
    | Rocket

[<RequireQualifiedAccess>]
type CombinationError =
    | EmptySelection
    | DuplicatePhysicalCards of Card list
    | PatternNotRecognized

/// A selected set of physical cards that has been successfully classified.
type Combination =
    private
        { SelectedCards: Card list
          Kind: CombinationKind
          MainRank: CardRank option }

[<RequireQualifiedAccess>]
module Combination =
    type private RankCount = CardRank * int

    let cards combination = combination.SelectedCards
    let kind combination = combination.Kind
    let mainRank combination = combination.MainRank
    let cardCount combination = List.length combination.SelectedCards

    let isBombOrRocket combination =
        match combination.Kind with
        | CombinationKind.Bomb
        | CombinationKind.Rocket -> true
        | _ -> false

    let private create cards kind mainRank =
        { SelectedCards = cards
          Kind = kind
          MainRank = mainRank }

    let private rankCounts cards : RankCount list =
        cards
        |> List.countBy Card.rank
        |> List.sortBy (fst >> CardRank.strength)

    let private standardRank = function
        | CardRank.Standard rank -> Some rank
        | CardRank.Joker _ -> None

    let private areConsecutive ranks =
        let strengths = ranks |> List.map StandardRank.strength |> List.sort

        strengths
        |> List.pairwise
        |> List.forall (fun (lower, higher) -> higher = lower + 1)

    let private tryUniformStandardSequence requiredMultiplicity minimumRanks kindFactory counts =
        let ranks =
            counts
            |> List.choose (fun (rank, count) ->
                match rank, count with
                | CardRank.Standard standard, count when count = requiredMultiplicity -> Some standard
                | _ -> None)

        if
            List.length ranks = List.length counts
            && List.length ranks >= minimumRanks
            && ranks |> List.forall StandardRank.canAppearInSequence
            && areConsecutive ranks
        then
            let highRank = ranks |> List.maxBy StandardRank.strength |> CardRank.Standard
            Some(kindFactory (List.length ranks), highRank)
        else
            None

    let private slidingWindows size items =
        let rec loop remaining acc =
            if List.length remaining < size then
                List.rev acc
            else
                loop (List.tail remaining) ((remaining |> List.take size) :: acc)

        if size <= 0 then [] else loop items []

    let private airplaneBodies tripleCount counts =
        counts
        |> List.choose (fun (rank, count) ->
            match rank with
            | CardRank.Standard standard when
                count >= 3 && StandardRank.canAppearInSequence standard
                -> Some standard
            | _ -> None)
        |> List.sortBy StandardRank.strength
        |> slidingWindows tripleCount
        |> List.filter areConsecutive

    let private removeAirplaneBody body counts =
        let bodyRanks = body |> List.map CardRank.Standard |> Set.ofList

        counts
        |> List.choose (fun (rank, count) ->
            if Set.contains rank bodyRanks then
                let remainder = count - 3
                if remainder = 0 then None else Some(rank, remainder)
            else
                Some(rank, count))

    let private containsBothJokers counts =
        let ranks = counts |> List.map fst |> Set.ofList

        Set.contains (CardRank.Joker Joker.Small) ranks
        && Set.contains (CardRank.Joker Joker.Big) ranks

    let private wingsAvoidBody body remaining =
        let bodyRanks = body |> List.map CardRank.Standard |> Set.ofList
        remaining |> List.forall (fun (rank, _) -> not (Set.contains rank bodyRanks))

    let private tryAirplaneWithSingles rules cards counts =
        if List.length cards % 4 <> 0 then
            None
        else
            let tripleCount = List.length cards / 4

            if tripleCount < 2 then
                None
            else
                airplaneBodies tripleCount counts
                |> List.tryPick (fun body ->
                    let remaining = removeAirplaneBody body counts
                    let remainingCardCount = remaining |> List.sumBy snd

                    let multiplicityAllowed =
                        match rules.Attachments.AirplaneSingleWings with
                        | AirplaneSingleWingPolicy.DistinctRanks ->
                            remaining |> List.forall (fun (_, count) -> count = 1)
                        | AirplaneSingleWingPolicy.PairsAllowed ->
                            remaining |> List.forall (fun (_, count) -> count <= 2)
                        | AirplaneSingleWingPolicy.AnyCards -> true

                    let jokersAllowed =
                        rules.Attachments.BothJokersMayBeAttachments
                        || not (containsBothJokers remaining)

                    if
                        remainingCardCount = tripleCount
                        && wingsAvoidBody body remaining
                        && multiplicityAllowed
                        && jokersAllowed
                    then
                        let highRank = body |> List.maxBy StandardRank.strength |> CardRank.Standard
                        Some(CombinationKind.AirplaneWithSingles tripleCount, highRank)
                    else
                        None)

    let private tryAirplaneWithPairs cards counts =
        if List.length cards % 5 <> 0 then
            None
        else
            let tripleCount = List.length cards / 5

            if tripleCount < 2 then
                None
            else
                airplaneBodies tripleCount counts
                |> List.tryPick (fun body ->
                    let remaining = removeAirplaneBody body counts

                    let areDistinctStandardPairs =
                        List.length remaining = tripleCount
                        && remaining
                           |> List.forall (fun (rank, count) ->
                               count = 2 && CardRank.isStandard rank)

                    if wingsAvoidBody body remaining && areDistinctStandardPairs then
                        let highRank = body |> List.maxBy StandardRank.strength |> CardRank.Standard
                        Some(CombinationKind.AirplaneWithPairs tripleCount, highRank)
                    else
                        None)

    let private tryTripleWithSingle counts =
        match counts with
        | [ (CardRank.Standard tripleRank, 3); (_, 1) ]
        | [ (_, 1); (CardRank.Standard tripleRank, 3) ] ->
            Some(CombinationKind.TripleWithSingle, CardRank.Standard tripleRank)
        | _ -> None

    let private tryTripleWithPair counts =
        match counts with
        | [ (CardRank.Standard tripleRank, 3); (CardRank.Standard _, 2) ]
        | [ (CardRank.Standard _, 2); (CardRank.Standard tripleRank, 3) ] ->
            Some(CombinationKind.TripleWithPair, CardRank.Standard tripleRank)
        | _ -> None

    let private tryFourWithSingles rules counts =
        match counts |> List.tryFind (fun (rank, count) -> CardRank.isStandard rank && count = 4) with
        | None -> None
        | Some(quadRank, _) ->
            let remaining = counts |> List.filter (fun (rank, _) -> rank <> quadRank)
            let remainingCount = remaining |> List.sumBy snd

            let distinctRanksAllowed =
                not rules.Attachments.FourSingleWingsMustHaveDistinctRanks
                || (remaining |> List.forall (fun (_, count) -> count = 1))

            let jokersAllowed =
                rules.Attachments.BothJokersMayBeAttachments
                || not (containsBothJokers remaining)

            if remainingCount = 2 && distinctRanksAllowed && jokersAllowed then
                Some(CombinationKind.FourWithSingles, quadRank)
            else
                None

    let private tryFourWithPairs counts =
        match counts |> List.tryFind (fun (rank, count) -> CardRank.isStandard rank && count = 4) with
        | None -> None
        | Some(quadRank, _) ->
            let remaining = counts |> List.filter (fun (rank, _) -> rank <> quadRank)

            if
                List.length remaining = 2
                && remaining
                   |> List.forall (fun (rank, count) -> CardRank.isStandard rank && count = 2)
            then
                Some(CombinationKind.FourWithPairs, quadRank)
            else
                None

    let private classifyRecognized rules cards =
        let counts = rankCounts cards
        let count = List.length cards

        let exactPatterns =
            [ if count = 1 then
                  match counts with
                  | [ (rank, 1) ] -> Some(CombinationKind.Single, rank)
                  | _ -> None
              if count = 2 then
                  match counts with
                  | [ (CardRank.Joker Joker.Small, 1); (CardRank.Joker Joker.Big, 1) ] ->
                      Some(CombinationKind.Rocket, CardRank.Joker Joker.Big)
                  | [ (CardRank.Standard rank, 2) ] ->
                      Some(CombinationKind.Pair, CardRank.Standard rank)
                  | _ -> None
              if count = 3 then
                  match counts with
                  | [ (CardRank.Standard rank, 3) ] ->
                      Some(CombinationKind.Triple, CardRank.Standard rank)
                  | _ -> None
              if count = 4 then
                  match counts with
                  | [ (CardRank.Standard rank, 4) ] ->
                      Some(CombinationKind.Bomb, CardRank.Standard rank)
                  | _ -> tryTripleWithSingle counts
              if count = 5 then
                  tryTripleWithPair counts
              tryUniformStandardSequence 1 5 CombinationKind.Straight counts
              tryUniformStandardSequence 2 3 CombinationKind.ConsecutivePairs counts
              tryUniformStandardSequence 3 2 CombinationKind.Airplane counts
              tryAirplaneWithSingles rules cards counts
              tryAirplaneWithPairs cards counts
              if count = 6 then tryFourWithSingles rules counts
              if count = 8 then tryFourWithPairs counts ]

        exactPatterns |> List.choose id |> List.tryHead

    let classify rules cards =
        match cards with
        | [] -> Error CombinationError.EmptySelection
        | _ ->
            let duplicates =
                cards
                |> List.countBy id
                |> List.choose (fun (card, count) -> if count > 1 then Some card else None)

            if not (List.isEmpty duplicates) then
                Error(CombinationError.DuplicatePhysicalCards duplicates)
            else
                match classifyRecognized rules cards with
                | Some(kind, rank) -> Ok(create cards kind (Some rank))
                | None -> Error CombinationError.PatternNotRecognized

    let private rankIsHigher challenger current =
        match challenger.MainRank, current.MainRank with
        | Some challengerRank, Some currentRank ->
            CardRank.strength challengerRank > CardRank.strength currentRank
        | _ -> false

    /// Whether challenger legally beats current. Normal combinations must have the exact
    /// same kind (including sequence length); bombs and the rocket are exceptions.
    let beats current challenger =
        match current.Kind, challenger.Kind with
        | CombinationKind.Rocket, _ -> false
        | _, CombinationKind.Rocket -> true
        | CombinationKind.Bomb, CombinationKind.Bomb -> rankIsHigher challenger current
        | CombinationKind.Bomb, _ -> false
        | _, CombinationKind.Bomb -> true
        | currentKind, challengerKind when currentKind = challengerKind ->
            rankIsHigher challenger current
        | _ -> false
