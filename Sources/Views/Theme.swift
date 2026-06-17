import SwiftUI

/// Design tokens mirroring the approved prototype. Most map onto system
/// materials/colors; explicit values are kept where the prototype is specific.
enum Theme {
    // Accent options exposed in Settings (graphite is the default).
    enum Accent: String, CaseIterable, Identifiable {
        case graphite, blue, multicolor
        var id: String { rawValue }
        var selectionUsesAccentFill: Bool { self != .graphite }
        var color: Color {
            switch self {
            case .graphite:   return Color(nsColor: .systemGray)
            case .blue, .multicolor: return Color(red: 0.04, green: 0.52, blue: 1.0) // #0A84FF
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable {
        case comfortable, compact
        var id: String { rawValue }
        var bodyFontSize: CGFloat { self == .compact ? 13 : 14 }
        var rowTopPadding: CGFloat { self == .compact ? 4 : 9 }
    }

    // Always-blue mention accent regardless of the app accent.
    static let mention = Color(red: 0.04, green: 0.52, blue: 1.0)         // #0A84FF
    static let opGreen = Color(red: 0.20, green: 0.78, blue: 0.35)        // #34C759
    static let voiceBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let notice = Color(red: 0.89, green: 0.66, blue: 0.34)         // #E3A857

    static let avatarSize: CGFloat = 34
    static let windowCornerRadius: CGFloat = 11
    static let composerCornerRadius: CGFloat = 11
}

/// AttributedString builder: mIRC color/format codes + clickable URLs +
/// self-mention emphasis.
enum RichText {
    static func render(_ text: String, selfNick: String, dark: Bool) -> AttributedString {
        var attr = parseMIRC(text, dark: dark)
        let plain = String(attr.characters)

        // Links (offsets map to the control-code-stripped plain text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let ns = plain as NSString
        detector?.enumerateMatches(in: plain, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let url = match.url,
                  let range = Range(match.range, in: attr) else { return }
            attr[range].link = url
            attr[range].foregroundColor = dark ? Color(red: 0.41, green: 0.71, blue: 1.0)
                                                : Color(red: 0.04, green: 0.44, blue: 0.84)
            attr[range].underlineStyle = .single
        }
        // Self-mention pill
        if !selfNick.isEmpty, let r = attr.range(of: selfNick, options: .caseInsensitive) {
            attr[r].backgroundColor = Theme.mention
            attr[r].foregroundColor = .white
            attr[r].font = .system(size: 14, weight: .semibold)
        }
        return attr
    }

    // MARK: - mIRC formatting (\x03 color, \x02 bold, \x1D italic, \x1F underline, \x0F reset)

    private static func parseMIRC(_ raw: String, dark: Bool) -> AttributedString {
        var result = AttributedString()
        var fg: Int?, bg: Int?
        var bold = false, italic = false, underline = false
        var buffer = ""

        func styled(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            var font = Font.system(size: 14)
            if bold { font = font.bold() }
            if italic { font = font.italic() }
            a.font = font
            if underline { a.underlineStyle = .single }
            if let fg, let c = mircColor(fg) { a.foregroundColor = c }
            if let bg, let c = mircColor(bg) { a.backgroundColor = c }
            return a
        }
        func flush() { if !buffer.isEmpty { result.append(styled(buffer)); buffer = "" } }

        var i = raw.startIndex
        while i < raw.endIndex {
            let ch = raw[i]
            switch ch {
            case "\u{02}": flush(); bold.toggle(); i = raw.index(after: i)
            case "\u{1D}": flush(); italic.toggle(); i = raw.index(after: i)
            case "\u{1F}": flush(); underline.toggle(); i = raw.index(after: i)
            case "\u{0F}": flush(); fg = nil; bg = nil; bold = false; italic = false; underline = false; i = raw.index(after: i)
            case "\u{16}": flush(); swap(&fg, &bg); i = raw.index(after: i)   // reverse
            case "\u{03}":
                flush()
                i = raw.index(after: i)
                var fgStr = ""
                while i < raw.endIndex, fgStr.count < 2, raw[i].isNumber { fgStr.append(raw[i]); i = raw.index(after: i) }
                if fgStr.isEmpty { fg = nil; bg = nil }   // bare \x03 resets color
                else {
                    fg = Int(fgStr)
                    if i < raw.endIndex, raw[i] == "," {
                        let after = raw.index(after: i)
                        if after < raw.endIndex, raw[after].isNumber {
                            i = after
                            var bgStr = ""
                            while i < raw.endIndex, bgStr.count < 2, raw[i].isNumber { bgStr.append(raw[i]); i = raw.index(after: i) }
                            bg = Int(bgStr)
                        }
                    }
                }
            default:
                buffer.append(ch); i = raw.index(after: i)
            }
        }
        flush()
        return result
    }

    /// The classic 16-color mIRC palette.
    private static func mircColor(_ i: Int) -> Color? {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r/255, green: g/255, blue: b/255) }
        let palette: [Color] = [
            c(255,255,255), c(0,0,0),     c(0,0,127),   c(0,147,0),
            c(255,0,0),     c(127,0,0),   c(156,0,156), c(252,127,0),
            c(255,255,0),   c(0,252,0),   c(0,147,147), c(0,255,255),
            c(0,0,252),     c(255,0,255), c(127,127,127), c(210,210,210),
        ]
        guard i >= 0, i < palette.count else { return nil }
        return palette[i]
    }
}
