import SwiftUI

/// Renders one display row. Modern grouped layout: avatar gutter + name/time
/// header + body, with distinct treatments for actions, notices, server lines
/// and coalesced join/part event groups.
struct MessageRowView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model
    let row: MessageRow

    private let gutter: CGFloat = 45  // avatar column (34) + spacing

    var body: some View {
        switch row {
        case .divider:
            HStack(spacing: 10) {
                line; Text("NEW MESSAGES")
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.mention)
                line
            }
            .padding(.horizontal, 16).padding(.vertical, 7)

        case let .events(_, summary, lines, _):
            EventGroupView(summary: summary, lines: lines).padding(.leading, gutter + 18)

        case let .message(m, showHeader, isMention):
            messageRow(m, showHeader: showHeader, isMention: isMention)

        case let .action(m):
            (Text("✶ ").foregroundStyle(.secondary)
             + Text(m.nick).foregroundStyle(NickColor.color(for: m.nick, dark: scheme == .dark))
             + Text(" \(m.text)").foregroundStyle(.secondary))
                .font(.system(size: 14)).italic()
                .padding(.leading, gutter + 18).padding(.trailing, 18).padding(.vertical, 3)

        case let .notice(m):
            (Text(m.nick).foregroundStyle(Theme.notice).fontWeight(.semibold)
             + Text("  \(m.text)").foregroundStyle(.secondary))
                .font(.system(size: 13.5))
                .padding(.leading, gutter + 18).padding(.trailing, 18).padding(.vertical, 3)

        case let .server(m):
            Text(m.text)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary)
                .padding(.leading, gutter + 18).padding(.trailing, 18).padding(.vertical, 1)
        }
    }

    private var line: some View { Rectangle().fill(Theme.mention.opacity(0.45)).frame(height: 1) }

    private func messageRow(_ m: Message, showHeader: Bool, isMention: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Group {
                if showHeader {
                    Circle()
                        .fill(NickColor.color(for: m.nick, dark: scheme == .dark))
                        .overlay(Text(NickColor.monogram(m.nick))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                } else { Color.clear }
            }
            .frame(width: Theme.avatarSize, height: Theme.avatarSize)

            VStack(alignment: .leading, spacing: 2) {
                if showHeader {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(m.nick).font(.system(size: 13.5, weight: .semibold))
                        Text(m.timeString).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Text(RichText.render(m.text, selfNick: model.selfNick, dark: scheme == .dark))
                    .font(.system(size: 14)).textSelection(.enabled)
                if let p = m.preview { PreviewCard(preview: p) }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, showHeader ? 9 : 1).padding(.horizontal, 18).padding(.bottom, 1)
        .background(alignment: .leading) {
            if isMention {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.mention).frame(width: 3)
                    Theme.mention.opacity(scheme == .dark ? 0.13 : 0.07)
                }
            }
        }
    }
}

private struct EventGroupView: View {
    let summary: String
    let lines: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button { expanded.toggle() } label: {
                Text("\(expanded ? "▾" : "▸") \(summary)")
                    .font(.system(size: 12.5)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(lines, id: \.self) { l in
                    Text(l).font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PreviewCard: View {
    let preview: LinkPreview

    var body: some View {
        switch preview.kind {
        case .link:
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "arrow.up.right").foregroundStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(preview.meta).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10).frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
            .padding(.top, 7)
        case .image:
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 1), Color(red: 0.64, green: 0.23, blue: 0.85), Color(red: 1, green: 0.48, blue: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 150)
                HStack {
                    Text(preview.label); Spacer(); Text(preview.dims)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 6)
            }
            .frame(width: 360)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
            .padding(.top, 7)
        }
    }
}
