import Foundation

/// Old-school colourful one-line ASCII art, addressable to a nick via `%nick%`.
/// Color is mIRC formatting: `\u{03}fg[,bg]` … `\u{0F}` reset. The message view
/// renders these codes (see RichText), so they show up colourful in-app too.
struct ArtLine: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var template: String

    init(name: String, template: String) { self.name = name; self.template = template }
}

private let CC = "\u{03}"          // color code
private let RST = "\u{0F}"         // reset all formatting
private let B  = "\u{02}"          // bold
private func col(_ f: Int, _ b: Int? = nil) -> String { b == nil ? "\(CC)\(f)" : "\(CC)\(f),\(b!)" }

/// Wrap each non-space character in a cycling rainbow of mIRC colors.
private func rainbow(_ s: String) -> String {
    let palette = [4, 7, 8, 9, 11, 12, 13]   // red orange yellow lgreen lcyan lblue pink
    var out = ""
    var i = 0
    for ch in s {
        if ch == " " { out += " " } else { out += col(palette[i % palette.count]) + String(ch); i += 1 }
    }
    return out + RST
}

enum ArtCatalog {
    static func render(_ template: String, nick: String) -> String {
        // Fast path: plain placeholder.
        var s = template.replacingOccurrences(of: "%nick%", with: nick)
        // rainbow() interleaves a color code between every character, splitting
        // the placeholder into %·n·i·c·k·% — a plain string replace can't see
        // it. Match the placeholder with any mIRC control codes in between; the
        // substituted nick inherits the color active at the match start.
        let ctl = "(?:\u{03}\\d{1,2}(?:,\\d{1,2})?|[\u{03}\u{02}\u{0F}\u{1D}\u{1F}\u{16}])*"
        s = s.replacingOccurrences(
            of: "%\(ctl)n\(ctl)i\(ctl)c\(ctl)k\(ctl)%",
            with: NSRegularExpression.escapedTemplate(for: nick),
            options: .regularExpression)
        return s
    }

    static let groups: [(name: String, lines: [ArtLine])] = [
        ("Greetings", [
            ArtLine(name: "Rainbow hello",  template: rainbow("hello %nick%!")),
            ArtLine(name: "Wassup",         template: "\(B)\(col(9))ＷＡＳＳＵＰ \(col(11))%nick%\(RST)"),
            ArtLine(name: "Fancy brackets", template: "\(col(12))(¯`·._.·[ \(col(13))%nick%\(col(12)) ]·._.·´¯)\(RST)"),
            ArtLine(name: "Stars",          template: "\(col(8))★彡 \(col(11))%nick% \(col(8))彡★\(RST)"),
            ArtLine(name: "Hug",            template: "\(col(13))(づ｡◕‿‿◕｡)づ \(col(11))%nick%\(RST)"),
            ArtLine(name: "Disco",          template: "\(rainbow("♪┏(･o･)┛♪ %nick%"))"),
        ]),
        ("Faces", [
            ArtLine(name: "Shrug",          template: "¯\\_(ツ)_/¯"),
            ArtLine(name: "Lenny",          template: "( ͡° ͜ʖ ͡°)"),
            ArtLine(name: "Bear",           template: "ʕ•ᴥ•ʔ"),
            ArtLine(name: "Look of disapproval", template: "ಠ_ಠ"),
            ArtLine(name: "Happy",          template: "(•◡•)"),
            ArtLine(name: "Sparkle eyes",   template: "✧◝(⁰▿⁰)◜✧"),
            ArtLine(name: "Cool shades",    template: "(⌐■_■)"),
            ArtLine(name: "Crying",         template: "(ಥ﹏ಥ)"),
            ArtLine(name: "Wink",           template: "(^_-)≡☆"),
            ArtLine(name: "Flushed",        template: "(///▽///)"),
            ArtLine(name: "No u",           template: "( ͠° ͟ʖ ͡°)"),
            ArtLine(name: "Strong",         template: "ᕦ(ò_óˇ)ᕤ"),
        ]),
        ("Flips & Tables", [
            ArtLine(name: "Table flip",     template: "\(col(4))(╯°□°)╯︵ ┻━┻\(RST)"),
            ArtLine(name: "Double flip",    template: "\(col(4))┻━┻ ︵ヽ(`Д´)ﾉ︵ ┻━┻\(RST)"),
            ArtLine(name: "Put table back", template: "\(col(9))┬─┬ ノ( ゜-゜ノ)\(RST)"),
            ArtLine(name: "Person flip",    template: "(ノಠ益ಠ)ノ彡┻━┻"),
        ]),
        ("Weapons & Mischief", [
            ArtLine(name: "Pew pew",        template: "\(col(14))︻╦╤─ \(col(4))%nick%   \(col(8))pew pew\(RST)"),
            ArtLine(name: "Salute %nick%",  template: "\(col(12))o7 \(col(11))%nick%\(RST)"),
            ArtLine(name: "Flip off %nick%",template: "\(col(4))╭∩╮(º_º)╭∩╮ \(col(8))%nick%\(RST)"),
            ArtLine(name: "Sword",          template: "\(col(14))(▀̿Ĺ̯▀̿ ̿) ⚔ %nick%\(RST)"),
            ArtLine(name: "Long gun",       template: "\(col(14))▄︻̷̿┻̿═━一 \(col(4))%nick%\(RST)"),
            ArtLine(name: "Bow & arrow",    template: "\(col(9))ϵ( 'Θ' )϶ →→ \(col(4))%nick%\(RST)"),
            ArtLine(name: "Fight me",       template: "\(col(4))(ง'̀-'́)ง \(col(8))%nick%\(RST)"),
            ArtLine(name: "Deal with it",   template: rainbow("(•_•) ( •_•)>⌐■-■ (⌐■_■)")),
        ]),
        ("Blocks & Bling", [
            ArtLine(name: "Block banner",   template: "\(col(0,1))░▒▓█ \(col(11,1))%nick% \(col(0,1))█▓▒░\(RST)"),
            ArtLine(name: "Zigzag",         template: "\(col(9))▄▀▄▀ \(col(11))%nick% \(col(9))▄▀▄▀\(RST)"),
            ArtLine(name: "Money",          template: "\(col(3))[̲̅$̲̅(̲̅5̲̅)̲̅$̲̅]\(RST)"),
            ArtLine(name: "Rainbow bar",    template: rainbow("▇▆▅▄▃▂▁ %nick% ▁▂▃▄▅▆▇")),
            ArtLine(name: "Fire",           template: "\(col(4))( \(col(7))🔥 \(col(8))%nick% \(col(7))🔥\(col(4)) )\(RST)"),
            ArtLine(name: "Hearts",         template: "\(col(4))♥\(col(13))♥\(col(8))♥ \(col(0))%nick% \(col(8))♥\(col(13))♥\(col(4))♥\(RST)"),
            ArtLine(name: "Sparkles",       template: rainbow("✦ ⋆ ˚ %nick% ˚ ⋆ ✦")),
        ]),
        ("Animals", [
            ArtLine(name: "Cat",            template: "=^.^="),
            ArtLine(name: "Fish",           template: "\(col(11))><(((°>\(RST)"),
            ArtLine(name: "Bird",           template: "(•ө•)♡"),
            ArtLine(name: "Dog",            template: "U・ᴥ・U"),
            ArtLine(name: "Bunny",          template: "(\\(\\ ( -.-) o_(\")(\")"),
            ArtLine(name: "Spider",         template: "/\\oo/\\"),
            ArtLine(name: "Bat",            template: "/|\\ ^._.^ /|\\"),
            ArtLine(name: "Snail",          template: "🐌  %nick% ... eventually"),
        ]),
        ("Reactions & Hype", [
            ArtLine(name: "Clap",           template: "\(col(8))👏 %nick% 👏\(RST)"),
            ArtLine(name: "GG",             template: "\(B)\(col(9))GG \(col(11))%nick%\(RST)"),
            ArtLine(name: "Mind blown",     template: rainbow("(☞ ﾟ∀ﾟ)☞ %nick% ☜(ﾟ∀ﾟ☜)")),
            ArtLine(name: "Cheers",         template: "\(col(8))🍻 cheers %nick%!\(RST)"),
            ArtLine(name: "This is fine",   template: "\(col(7))🔥 this is fine 🔥\(RST)"),
            ArtLine(name: "Party",          template: rainbow("🎉 ♪┏(･o･)┛♪ %nick% ♪┗(･o･)┓♪ 🎉")),
            ArtLine(name: "Big mad",        template: "\(col(4))(ノಠ益ಠ)ノ彡 %nick%\(RST)"),
        ]),
        ("Classic IRC", [
            ArtLine(name: "Welcome banner", template: "\(col(0,2)) ▓▒░ WELCOME \(col(8,2))%nick%\(col(0,2)) ░▒▓ \(RST)"),
            ArtLine(name: "Trout slap",     template: "👋🐟 slaps \(col(4))%nick%\(RST) around a bit with a large trout"),
            ArtLine(name: "0wnz j00",       template: "\(B)\(col(4))%nick% 0wnz j00\(RST)"),
            ArtLine(name: "Beer to %nick%", template: "\(col(8))🍺 → %nick%\(RST)"),
            ArtLine(name: "brb",            template: "\(col(8))⌛ brb\(RST)"),
            ArtLine(name: "afk",            template: "\(col(14))—— afk ——\(RST)"),
            ArtLine(name: "Back",           template: "\(col(9))[ back ]\(RST)"),
            ArtLine(name: "Hi5 %nick%",     template: "\(col(11))o/\\o  hi5 %nick%\(RST)"),
        ]),
        ("Music", [
            ArtLine(name: "Notes",          template: rainbow("♫ ♪ ♬ %nick% ♬ ♪ ♫")),
            ArtLine(name: "Vibing",         template: "\(col(13))🎧 %nick% is vibing\(RST)"),
            ArtLine(name: "Equalizer",      template: "\(col(9))▁▃▅▇▅▃▁ \(col(11))%nick% \(col(9))▁▃▅▇▅▃▁\(RST)"),
            ArtLine(name: "Now playing",    template: "\(col(12))♪ now playing: vibes.mp3 ♪\(RST)"),
        ]),
    ]
}
