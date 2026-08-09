namespace ChillGame.Domain

/// How duplicate ranks may be used as the single-card wings of an airplane.
[<RequireQualifiedAccess>]
type AirplaneSingleWingPolicy =
    /// Every attached card must have a different rank.
    | DistinctRanks
    /// A pair may supply two attached cards, but triples and quads may not be split into wings.
    | PairsAllowed
    /// Any remaining cards may be wings, provided they are not from an airplane body rank.
    | AnyCards

/// Rules whose treatment differs among common three-player implementations.
type AttachmentRules =
    { AirplaneSingleWings: AirplaneSingleWingPolicy
      FourSingleWingsMustHaveDistinctRanks: bool
      BothJokersMayBeAttachments: bool }

/// Multipliers applied during settlement.
type ScoringRules =
    { BombMultiplier: int
      RocketMultiplier: int
      SpringMultiplier: int }

/// An explicit three-player rules profile.
type RuleSet =
    { Attachments: AttachmentRules
      Scoring: ScoringRules
      RevealBottomCards: bool }

[<RequireQualifiedAccess>]
module RuleSet =
    /// Baseline used by this implementation, following the Pagat three-player rules:
    /// airplane single wings may include a pair; quad single wings are different ranks;
    /// and both jokers cannot be used together as attachments.
    let standardThreePlayer =
        { Attachments =
            { AirplaneSingleWings = AirplaneSingleWingPolicy.PairsAllowed
              FourSingleWingsMustHaveDistinctRanks = true
              BothJokersMayBeAttachments = false }
          Scoring =
            { BombMultiplier = 2
              RocketMultiplier = 2
              SpringMultiplier = 2 }
          RevealBottomCards = true }
