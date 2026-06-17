import SwiftUI

struct MessageRowView: View {
    let line: ChatLine

    var body: some View {
        switch line.kind {
        case .message, .notice:
            standardRow
        case .action:
            actionRow
        case .join, .part, .quit, .server:
            metaRow
        case .topic:
            metaRow
        }
    }

    private var standardRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timestamp
            Text(line.sender)
                .font(.body.weight(.semibold))
                .foregroundStyle(NickColor.color(for: line.sender))
            bodyText
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(line.isMention ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var actionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timestamp
            (Text("\(line.sender) ").font(.body.weight(.semibold))
                .foregroundColor(NickColor.color(for: line.sender))
             + Text(line.text))
                .italic()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timestamp
            Text(line.text)
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private var timestamp: some View {
        Text(line.timestamp, format: .dateTime.hour().minute())
            .font(.caption.monospacedDigit())
            .foregroundStyle(.quaternary)
            .frame(width: 42, alignment: .leading)
    }

    private var bodyText: Text {
        Text(NickColor.linkified(line.text))
    }
}

/// Deterministic per-nick coloring + lightweight URL linkification.
enum NickColor {
    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .red, .mint, .cyan
    ]

    static func color(for nick: String) -> Color {
        let hash = nick.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }

    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let ns = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: attributed) else { continue }
            attributed[range].link = url
            attributed[range].underlineStyle = .single
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }
}
