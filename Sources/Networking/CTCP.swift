import Foundation

/// CTCP request/response handling. The client answers VERSION with a fixed
/// signature and PING (and friends) with deliberately silly nonsense instead of
/// the usual echo.
enum CTCP {
    /// Reply to a CTCP VERSION query.
    static let versionReply = "Happily vibe coded by Rufus with 200k tokens"

    /// Pool of nonsense PING replies — picked at random per request.
    static let sillyPings: [String] = [
        "pong but emotionally",
        "42ms, measured in vibes",
        "your packet was eaten by a goose 🪿",
        "ping? in this economy?",
        "🏓 take that",
        "latency is a social construct",
        "i felt that ping in my soul",
        "reply hazy, try again later",
        "ack ack ack (morse for hi)",
        "the call is coming from inside the house",
        "buffering enlightenment…",
        "yes hello it is i, the computer",
    ]

    static let sillyTimes: [String] = [
        "somewhere between now and 200k tokens",
        "o'clock-ish",
        "time is a flat circle, but it's roughly Tuesday",
        "half past vibes",
    ]

    /// Returns the reply text for a CTCP command, or nil if we don't answer it.
    /// `seed` varies the random pick without needing a clock.
    static func reply(to command: String, argument: String, seed: Int) -> String? {
        switch command.uppercased() {
        case "VERSION":    return versionReply
        case "PING":       return pick(sillyPings, seed)
        case "TIME":       return pick(sillyTimes, seed)
        case "SOURCE":     return "Rufus's keyboard, ~200k tokens of it"
        case "CLIENTINFO": return "VERSION PING TIME SOURCE — the rest is improvisation"
        case "FINGER":     return "stop touching me"
        default:           return nil
        }
    }

    private static func pick(_ list: [String], _ seed: Int) -> String {
        list[((seed % list.count) + list.count) % list.count]
    }
}
