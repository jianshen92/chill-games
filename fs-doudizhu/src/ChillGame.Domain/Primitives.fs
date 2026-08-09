namespace ChillGame.Domain

open System

/// Stable identity of one game.
type GameId = private GameId of Guid

[<RequireQualifiedAccess>]
module GameId =
    let create value = GameId value
    let newId () = GameId(Guid.NewGuid())
    let value (GameId value) = value

/// Stable identity of a player. It is deliberately not interchangeable with GameId.
type PlayerId = private PlayerId of Guid

[<RequireQualifiedAccess>]
module PlayerId =
    let create value = PlayerId value
    let newId () = PlayerId(Guid.NewGuid())
    let value (PlayerId value) = value

[<RequireQualifiedAccess>]
type PlayerNameError =
    | Required
    | TooLong of maximum: int

/// A non-blank player name of at most 30 Unicode code units.
type PlayerName = private PlayerName of string

[<RequireQualifiedAccess>]
module PlayerName =
    let create (raw: string) =
        if String.IsNullOrWhiteSpace raw then
            Error PlayerNameError.Required
        else
            let normalized = raw.Trim()

            if normalized.Length > 30 then
                Error(PlayerNameError.TooLong 30)
            else
                Ok(PlayerName normalized)

    let value (PlayerName value) = value

/// A domain player. Equality is structural, while game membership is determined by Id.
type Player = private { Id: PlayerId; Name: PlayerName }

[<RequireQualifiedAccess>]
module Player =
    let create id name = { Id = id; Name = name }
    let id player = player.Id
    let name player = player.Name

[<RequireQualifiedAccess>]
type Seat =
    | First
    | Second
    | Third

[<RequireQualifiedAccess>]
type SeatingError =
    | DuplicatePlayerId of PlayerId

/// Exactly three distinct players in table order.
type Players =
    private
        { First: Player
          Second: Player
          Third: Player }

[<RequireQualifiedAccess>]
module Players =
    let create first second third =
        let ids = [ Player.id first; Player.id second; Player.id third ]

        match ids |> List.countBy id |> List.tryFind (fun (_, count) -> count > 1) with
        | Some(duplicate, _) -> Error(SeatingError.DuplicatePlayerId duplicate)
        | None ->
            Ok
                { First = first
                  Second = second
                  Third = third }

    let all players = [ players.First; players.Second; players.Third ]

    let ids players = all players |> List.map Player.id

    let playerAt seat players =
        match seat with
        | Seat.First -> players.First
        | Seat.Second -> players.Second
        | Seat.Third -> players.Third

    let idAt seat players = playerAt seat players |> Player.id

    let contains playerId players = ids players |> List.contains playerId

    let trySeatOf playerId players =
        if Player.id players.First = playerId then Some Seat.First
        elif Player.id players.Second = playerId then Some Seat.Second
        elif Player.id players.Third = playerId then Some Seat.Third
        else None

    let nextSeat = function
        | Seat.First -> Seat.Second
        | Seat.Second -> Seat.Third
        | Seat.Third -> Seat.First

    let nextId playerId players =
        trySeatOf playerId players
        |> Option.map (fun seat -> nextSeat seat |> fun next -> idAt next players)
