import SwiftUI
import LinkPresentation
import os

let linkPreviewLog = Logger(subsystem: "org.relay.irc", category: "linkpreview")

/// Renders one display row. Modern grouped layout: avatar gutter + name/time
/// header + body, with distinct treatments for actions, notices, server lines
/// and coalesced join/part event groups.
struct MessageRowView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model
    @AppStorage("showTimestamps") private var showTimestamps = true
    let row: MessageRow

    private let gutter: CGFloat = 45  // avatar column (34) + spacing

    // Hover link preview. Item-based presentation so the popover and its URL
    // can never desync (an isPresented + separate URL state raced and showed
    // an empty popover).
    struct PreviewLink: Identifiable { let id: String; let url: URL }
    @State private var hoverPreview: PreviewLink?
    @State private var hoverTask: Task<Void, Never>?

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
                        .onTapGesture { model.revealMember(m.nick) }
                        .contextMenu { MemberActionsMenu(nick: m.nick) }
                } else { Color.clear }
            }
            .frame(width: Theme.avatarSize, height: Theme.avatarSize)

            VStack(alignment: .leading, spacing: 2) {
                if showHeader {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Click a nick → reveal in the member list; right-click
                        // → the same full menu as the member list.
                        Text(m.nick).font(.system(size: 13.5, weight: .semibold))
                            .onTapGesture { model.revealMember(m.nick) }
                            .contextMenu { MemberActionsMenu(nick: m.nick) }
                            .help("Click to show in member list")
                        if showTimestamps {
                            Text(m.timeString).font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
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
        .contextMenu {
            Button("Whois \(m.nick)") { model.whois(m.nick) }
            Button("Message \(m.nick)") { model.openDM(m.nick) }
            Button("Ban \(m.nick)…", role: .destructive) { model.banPrompt(m.nick) }
            Menu("Send ASCII Art") { ArtMenu { model.sendArt($0, toNick: m.nick) } }
            Divider()
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(m.text, forType: .string)
            }
        }
        // Hover preview lives on the ROW, not the Text — .textSelection bridges
        // the Text to an AppKit text view that eats hover events, so onHover
        // on the Text itself never fires.
        .onHover { hovering in linkHover(hovering, text: m.text) }
        .popover(item: $hoverPreview, arrowEdge: .bottom) { p in
            LinkHoverPreview(url: p.url)
        }
    }

    /// Hovering a message that contains a URL pops a small preview after a
    /// short delay (and closes it shortly after the pointer leaves).
    private func linkHover(_ hovering: Bool, text: String) {
        hoverTask?.cancel()
        if hovering {
            guard let url = Self.firstURL(in: text) else { return }
            // @MainActor is load-bearing: a bare Task in a View method runs on
            // a background executor, and @State written off-main is dropped —
            // the popover presented with no content.
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                linkPreviewLog.info("presenting preview: \(url.absoluteString, privacy: .public)")
                hoverPreview = PreviewLink(id: url.absoluteString, url: url)
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                hoverPreview = nil
            }
        }
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let ns = text as NSString
        let match = detector?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        guard let url = match?.url, url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}

// MARK: - Hover link preview (LinkPresentation)

/// Fetches and caches LPLinkMetadata so re-hovering a link is instant.
@MainActor
final class LinkMetadataCache {
    static let shared = LinkMetadataCache()
    private var cache: [URL: LPLinkMetadata] = [:]

    func metadata(for url: URL) async throws -> LPLinkMetadata {
        if let hit = cache[url] { return hit }
        let md = try await LPMetadataProvider().startFetchingMetadata(for: url)
        if cache.count > 100 { cache.removeAll() }   // LPLinkMetadata pins WebKit memory
        cache[url] = md
        return md
    }

    static func image(from md: LPLinkMetadata) async -> NSImage? {
        guard let provider = md.imageProvider else { return nil }
        return await withCheckedContinuation { cont in
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                cont.resume(returning: obj as? NSImage)
            }
        }
    }
}

private struct LinkHoverPreview: View {
    let url: URL
    @State private var title: String?
    @State private var image: NSImage?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(nsImage: image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 296, height: 150).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let title {
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(3)
            }
            HStack(spacing: 5) {
                Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(url.host() ?? url.absoluteString)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if loading { Spacer(); ProgressView().controlSize(.mini) }
            }
            if failed {
                Text("No preview available — click to open")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(url) }
        .task {
            defer { loading = false }
            do {
                let md = try await LinkMetadataCache.shared.metadata(for: url)
                linkPreviewLog.info("metadata ok: \(md.title ?? "(no title)", privacy: .public)")
                title = md.title
                image = await LinkMetadataCache.image(from: md)
            } catch {
                linkPreviewLog.error("metadata failed \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failed = true
            }
        }
    }
}

private struct EventGroupView: View {
    let summary: String
    let lines: [String]
    @State private var showDetails = false

    var body: some View {
        Button { showDetails.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right.circle").font(.system(size: 10))
                Text(summary).font(.system(size: 12.5))
            }
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .popover(isPresented: $showDetails, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { l in
                    Text(l).font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(12)
            .frame(maxWidth: 460, alignment: .leading)
        }
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
