import Foundation

/// Undernet user and channel modes, transcribed from the official help pages:
/// https://www.undernet.org/help/faq_usermodes.php
/// https://www.undernet.org/help/faq_channelmodes.php
/// and the X (Channel Service) command reference:
/// https://user-com.undernet.org/docs/xcmds.txt

// MARK: - User modes (the ones a user can set on themselves)

struct UserMode: Identifiable, Hashable {
    let letter: String           // "x"
    var id: String { letter }
    let name: String
    let detail: String
}

// MARK: - Channel modes

enum ModeParam: Hashable {
    case none          // boolean flag
    case nick          // operates on a member (+o/+v)
    case mask          // nick!user@host (+b)
    case number        // +l
    case key           // +k
}

struct ChannelMode: Identifiable, Hashable {
    let letter: String
    var id: String { letter }
    let name: String
    let param: ModeParam
    let detail: String
    /// Modes the user toggles in the channel-modes editor (excludes per-member
    /// o/v/b and auto-set R/d).
    let editable: Bool
}

enum Undernet {

    static let userModes: [UserMode] = [
        UserMode(letter: "i", name: "Invisible",
                 detail: "Hides you from /who and /names for people not in a common channel."),
        UserMode(letter: "w", name: "Wallops",
                 detail: "Receive network-wide WALLOPS messages from IRC operators."),
        UserMode(letter: "d", name: "Deaf",
                 detail: "Stop receiving channel chat; you still see joins, parts, topics and modes."),
        UserMode(letter: "x", name: "Hidden host",
                 detail: "Mask your host as ident@account.users.undernet.org (requires X login)."),
    ]

    static let channelModes: [ChannelMode] = [
        ChannelMode(letter: "o", name: "Operator", param: .nick,
                    detail: "Grants channel-operator status (@).", editable: false),
        ChannelMode(letter: "v", name: "Voice", param: .nick,
                    detail: "Lets a user speak while the channel is moderated (+).", editable: false),
        ChannelMode(letter: "b", name: "Ban", param: .mask,
                    detail: "Bans a nick!user@host mask from the channel.", editable: false),
        ChannelMode(letter: "l", name: "Limit", param: .number,
                    detail: "Limits the channel to a maximum number of users.", editable: true),
        ChannelMode(letter: "k", name: "Key", param: .key,
                    detail: "Sets a password required to join the channel.", editable: true),
        ChannelMode(letter: "i", name: "Invite only", param: .none,
                    detail: "Only invited users may join.", editable: true),
        ChannelMode(letter: "m", name: "Moderated", param: .none,
                    detail: "Only ops and voiced users can send to the channel.", editable: true),
        ChannelMode(letter: "n", name: "No external messages", param: .none,
                    detail: "Block messages from users not in the channel.", editable: true),
        ChannelMode(letter: "t", name: "Topic locked", param: .none,
                    detail: "Only ops can change the topic.", editable: true),
        ChannelMode(letter: "p", name: "Private", param: .none,
                    detail: "Hides the channel from WHOIS unless the asker is a member.", editable: true),
        ChannelMode(letter: "s", name: "Secret", param: .none,
                    detail: "Hides the channel from /list and /who entirely.", editable: true),
        ChannelMode(letter: "r", name: "Registered only", param: .none,
                    detail: "Only users logged in to X may join.", editable: true),
        ChannelMode(letter: "D", name: "Delayed join", param: .none,
                    detail: "Joining users stay hidden until they speak or get op/voice.", editable: true),
        ChannelMode(letter: "c", name: "No colors", param: .none,
                    detail: "Strips mIRC/ANSI color control codes.", editable: true),
        ChannelMode(letter: "C", name: "No CTCP", param: .none,
                    detail: "Blocks channel-wide CTCP requests.", editable: true),
        ChannelMode(letter: "d", name: "Hidden users present", param: .none,
                    detail: "Set automatically when -D leaves hidden users behind.", editable: false),
        ChannelMode(letter: "R", name: "Registered", param: .none,
                    detail: "Channel is registered with X (set automatically).", editable: false),
    ]

    static var editableChannelModes: [ChannelMode] { channelModes.filter(\.editable) }
}

// MARK: - X (Channel Service) settings

/// A configurable X channel setting (`/msg X SET <#chan> <option> <value>`).
struct XChannelSetting: Identifiable, Hashable {
    enum Kind: Hashable { case toggle, number(ClosedRange<Int>), text(Int) }
    let option: String
    var id: String { option }
    let kind: Kind
    let detail: String
}

/// A configurable X user setting (`/msg X USET <option> <value>`).
struct XUserSetting: Identifiable, Hashable {
    enum Kind: Hashable { case toggle, text }
    let option: String
    var id: String { option }
    let kind: Kind
    let detail: String
}

extension Undernet {
    static let xChannelSettings: [XChannelSetting] = [
        .init(option: "AUTOJOIN", kind: .toggle, detail: "X rejoins the channel when it comes back online."),
        .init(option: "AUTOTOPIC", kind: .toggle, detail: "Reset the topic to DESCRIPTION + URL every 30 minutes."),
        .init(option: "NOOP", kind: .toggle, detail: "Nobody (except managers) may be opped."),
        .init(option: "STRICTOP", kind: .toggle, detail: "Only authenticated level-100+ users may be opped."),
        .init(option: "FLOATLIM", kind: .toggle, detail: "Dynamically adjust the channel user limit (+l)."),
        .init(option: "MASSDEOPPRO", kind: .number(0...7), detail: "Max deops allowed within 15 seconds before X acts."),
        .init(option: "FLOATMARGIN", kind: .number(2...20), detail: "Users added on top of the current count for the limit."),
        .init(option: "FLOATGRACE", kind: .number(0...19), detail: "Grace threshold to avoid needless limit changes."),
        .init(option: "FLOATPERIOD", kind: .number(20...200), detail: "Seconds between floating-limit recalculations."),
        .init(option: "FLOATMAX", kind: .number(0...65536), detail: "Cap for the floating limit."),
        .init(option: "USERFLAGS", kind: .number(0...2), detail: "Default automode for newly added users (0/1/2)."),
        .init(option: "DESCRIPTION", kind: .text(80), detail: "Channel description shown in CHANINFO."),
        .init(option: "URL", kind: .text(75), detail: "Channel website URL shown in CHANINFO."),
        .init(option: "KEYWORDS", kind: .text(80), detail: "Space-separated search keywords for the channel."),
    ]

    static let xUserSettings: [XUserSetting] = [
        .init(option: "INVISIBLE", kind: .toggle, detail: "Hide your online status and username from others."),
        .init(option: "NOADDUSER", kind: .toggle, detail: "Prevent others from adding you to their channels."),
        .init(option: "LANG", kind: .text, detail: "X response language code (en, es, fr, de, …)."),
    ]
}
