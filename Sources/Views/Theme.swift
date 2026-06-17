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

/// AttributedString builder: clickable URLs + self-mention emphasis.
enum RichText {
    static func render(_ text: String, selfNick: String, dark: Bool) -> AttributedString {
        var attr = AttributedString(text)
        // Links
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let ns = text as NSString
        detector?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, let url = match.url,
                  let range = Range(match.range, in: attr) else { return }
            attr[range].link = url
            attr[range].foregroundColor = dark ? Color(red: 0.41, green: 0.71, blue: 1.0)
                                                : Color(red: 0.04, green: 0.44, blue: 0.84)
            attr[range].underlineStyle = .single
        }
        // Self-mention pill
        if !selfNick.isEmpty,
           let r = attr.range(of: selfNick, options: .caseInsensitive) {
            attr[r].backgroundColor = Theme.mention
            attr[r].foregroundColor = .white
            attr[r].font = .system(size: 14, weight: .semibold)
        }
        return attr
    }
}
