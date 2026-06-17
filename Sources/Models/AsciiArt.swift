import Foundation

/// Old-school colourful one-line ASCII art, addressable to a nick via `%nick%`.
/// Color is mIRC formatting: `\u{03}fg[,bg]` … `\u{0F}` reset. The message view
/// renders these codes (see RichText), so they show up colourful in-app too.
struct ArtLine: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let template: String
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
        template.replacingOccurrences(of: "%nick%", with: nick)
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
        ]),
        ("Blocks & Bling", [
            ArtLine(name: "Block banner",   template: "\(col(0,1))░▒▓█ \(col(11,1))%nick% \(col(0,1))█▓▒░\(RST)"),
            ArtLine(name: "Zigzag",         template: "\(col(9))▄▀▄▀ \(col(11))%nick% \(col(9))▄▀▄▀\(RST)"),
            ArtLine(name: "Money",          template: "\(col(3))[̲̅$̲̅(̲̅5̲̅)̲̅$̲̅]\(RST)"),
            ArtLine(name: "Rainbow bar",    template: rainbow("▇▆▅▄▃▂▁ %nick% ▁▂▃▄▅▆▇")),
            ArtLine(name: "Fire",           template: "\(col(4))( \(col(7))🔥 \(col(8))%nick% \(col(7))🔥\(col(4)) )\(RST)"),
        ]),
    ]
}
