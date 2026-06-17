# SwiftUI macOS IRC Client — Design Prompt

> Prompt handed to Claude Design to produce the interactive UI. The scaffold in
> this repo mirrors the architecture described here so the generated design can
> be dropped onto a working skeleton.

---

**Build a native macOS IRC client in SwiftUI — fully functional, deeply Mac-like.**

Implement a complete IRC client as a SwiftUI macOS app that feels first-party
(Messages / Mail / Xcode design language). Target macOS 14+ (Sonoma / Sequoia /
Tahoe), Swift 5.9+, SwiftUI-first with AppKit bridging only where SwiftUI falls
short.

## Architecture
- `NavigationSplitView` three-column layout: source-list sidebar (networks →
  channels/DMs), message list (content), member list (detail, collapsible via
  `.toolbar`).
- MVVM with `@Observable` (Observation framework) view models; `@MainActor` UI,
  structured concurrency for networking.
- Networking layer using `Network.framework` (`NWConnection`) for the raw IRC
  TCP/TLS socket — parse the IRC line protocol (RFC 1459/2812 + IRCv3 message
  tags, SASL) in a dedicated actor. Keep transport, protocol parsing, and view
  models cleanly separated.
- App lifecycle via SwiftUI `App` / `WindowGroup` + `Settings` scene;
  `@AppStorage` / `SceneStorage` for layout and preferences persistence; model
  persistence with SwiftData.

## Core layout & chrome
- Sidebar with `List` + `Section` per network, selection-bound, unread badges
  (`.badge`) and mention indicators. Vibrancy via `.background(.regularMaterial)`
  / `NSVisualEffectView` bridge if needed.
- Unified toolbar (`.toolbar`, `.toolbarRole(.editor)`), traffic-light-aware
  window, resizable panes with min/ideal/max widths,
  `.navigationSplitViewColumnWidth`.
- Layout state restored per window.

## Functionality (wire it up, not a mockup)
- Multiple simultaneous network connections, each with its own nick, channel
  set, and connection state machine (disconnected → connecting → registering →
  connected).
- Join/part, private messages, topic display + inline edit.
- Composer: `TextField`/`TextEditor` with Tab nick-completion, `/` command
  parsing (`/join /msg /me /nick /topic /whois /part /quit`), Shift+Enter
  multiline, emoji.
- Message rendering: distinct styling for messages, `/me` actions, collapsible
  muted join/part, notices, server messages, and highlighted self-mentions.
  `Text` with `AttributedString` for nick coloring, clickable URLs, and inline
  link/image expansion. Use `LazyVStack` in a `ScrollViewReader` (or `List`) for
  performant scrollback.
- Member list with op/voice SF Symbols (@, +), presence, and context menu
  (`.contextMenu`: whois, op, kick, query).
- Scrollback with unread divider, "jump to latest" pill, and per-channel
  `.searchable`.
- Mentions/DMs → `UserNotifications` (UNUserNotificationCenter) + Dock badge.

## Mac-native details
- Full menu bar via `.commands` (`CommandGroup`, `CommandMenu`) with real
  shortcuts: ⌘K quick-switcher, ⌘N new connection, ⌘F find, ⌘1–9 jump to channel.
- Command palette / fuzzy quick-switcher (⌘K) as a sheet or floating panel.
- First-class light & dark mode, system accent color, SF Pro / SF Mono, SF
  Symbols throughout, standard spacing/corner radii.
- `Settings` scene with `TabView` sections (Accounts, Appearance, Notifications,
  Advanced) in native settings style.
- Restrained, system-standard animations.

## Deliverable
Provide a buildable Xcode project structure (organized files: `App/`, `Models/`,
`ViewModels/`, `Views/`, `Networking/`, `Services/`) with complete, compiling
SwiftUI code. Include a mock/in-memory IRC service that drives the UI with
realistic data (several networks, busy channels, DMs with unread mentions) so
the app is fully interactive without a live server, behind the same protocol
interface the real `NWConnection` client implements — so swapping mock for live
is a one-line change.
