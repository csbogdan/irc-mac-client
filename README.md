# Relay — native macOS IRC client (SwiftUI)

A first-party-feeling IRC client for macOS 14+ (Sonoma/Sequoia/Tahoe), Swift 5.9+.
SwiftUI-first with AppKit bridging only where SwiftUI falls short. Ships with an
in-memory mock service so the app is **fully interactive offline**, behind the
same `IRCClient` protocol the real `NWConnection` transport implements — swapping
mock for live is a one-line change.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen]
(`brew install xcodegen`) — the `.xcodeproj` is not committed.

```sh
xcodegen generate          # writes Relay.xcodeproj
open Relay.xcodeproj        # then ⌘R, or:
xcodebuild -project Relay.xcodeproj -scheme Relay -configuration Debug \
           -destination 'platform=macOS' build
```

The app target is sandboxed with the **Outgoing Connections (Client)** entitlement
(`Relay.entitlements`) so the live client can open TLS sockets.

> The provided `Package.swift` builds the modules and runs the parser tests from
> the command line (`swift build`, `swift test`) but does **not** produce a `.app`
> bundle — use the Xcode project above to run the GUI.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen

## Architecture

```
Sources/
  App/
    RelayApp.swift          WindowGroup + Settings scene; .commands menu bar (⌘K/⌘N/⌘F/⌘1–9)
  Models/
    Models.swift            Network, Conversation, Message, Member, enums, NickColor
  Networking/
    IRCClient.swift         IRCClient protocol + IRCEvent stream (the swap seam)
    IRCParser.swift         RFC 1459/2812 + IRCv3 message-tag parser/serializer (pure, testable)
    LiveIRCClient.swift     NWConnection TLS transport actor — parses & emits IRCEvents
  Services/
    MockIRCService.swift    In-memory client + seed data + live chatter timer
  ViewModels/
    AppModel.swift          @MainActor @Observable; consumes IRCEvent, exposes intents
  Views/
    Theme.swift             Design tokens + AttributedString rich text (links, mentions)
    MessageGrouper.swift    Pure transform: messages → grouped display rows
    ContentView.swift       NavigationSplitView 3-column shell + unified toolbar
    SidebarView.swift       Source list: networks → channels/DMs, badges, context menus
    ConversationView.swift  Topic bar, scrollback, connecting/offline states, jump-to-latest
    MessageRowView.swift    Avatar + name/time grouped rows, /me, notices, previews, events
    ComposerView.swift      Slash autocomplete, Tab nick-completion, command parsing
    MemberListView.swift    Op/voice groups, presence, per-member context menu
    QuickSwitcherView.swift ⌘K fuzzy switcher
    SettingsView.swift      TabView: Accounts / Appearance / Notifications / Advanced
Tests/
    IRCParserTests.swift    Parser unit tests
```

### The swap seam (mock → live)

`AppModel` talks only to an `IRCClient`. To go live, change one line in `AppModel`:

```swift
// let client: IRCClient = MockIRCService()
let client: IRCClient = LiveIRCClient(networkID: "undernet",
                                      host: "irc.undernet.org", port: 6697,
                                      nick: "mcimpeanu")
```

Both conform to `IRCClient` and emit the same `IRCEvent` stream; the view model
and every view are unchanged.

## What's implemented

- **3-column `NavigationSplitView`** with min/ideal/max column widths, unified
  toolbar (`.toolbarRole(.editor)` via `.windowToolbarStyle(.unified)`), collapsible member list.
- **Multiple networks** each with their own nick, channel set, and a
  `disconnected → connecting → registering → connected` state machine. Connecting
  shows a streaming server log; offline shows a Connect button.
- **Sidebar** source list with per-network sections, connection-state dots,
  unread badges, blue mention badges, muted dimming, and channel/DM context menus
  (Mark as Read, Set Topic, Mute, Copy Name, Leave / Close).
- **Modern grouped message list**: circular nick-colored avatars, name + time
  headers, grouped follow-ons, `/me` actions, notices, monospace server/whois
  lines, coalesced + expandable join/part/quit, self-mention highlight, unread
  divider, clickable URLs + self-mention pills (`AttributedString`), link & image
  preview cards, jump-to-latest pill, per-channel find.
- **Composer**: `/join /part /me /nick /topic /whois /msg /query /quit` parsing,
  Tab nick-completion with cycling candidate chips, `/` slash autocomplete popover
  (↑/↓/Tab/Return), Shift+Return newline.
- **Member list**: Operators / Voiced / Members groups, presence dots, mode
  glyphs, context menu (whois, message, op, voice, kick, ignore).
- **Menu bar `.commands`**: ⌘K quick switcher, ⌘N, ⌘F, ⌘1–9 jump.
- **Settings scene** TabView (Accounts, Appearance, Notifications, Advanced) with
  accent / density / timestamp prefs via `@AppStorage`; light/dark/system.

## Notes / next steps

- **SwiftData**: the brief calls for SwiftData persistence. State currently lives
  in the `@Observable` `AppModel` (sufficient for the mock and a clean MVVM seam).
  To persist, back `Conversation`/`Message` with `@Model` types and load/save in
  `AppModel`; the view layer won't change.
- **UserNotifications / Dock badge**: hook `UNUserNotificationCenter` in
  `AppModel.appendMessage` where `mentions`/DM increments happen (TODO marked).
- **SASL**: the `LiveIRCClient` registers with CAP negotiation; wire the
  `AUTHENTICATE PLAIN` exchange in `handleState`/`handle` to finish SASL.
- The interactive HTML design reference this was built from is in
  `../design_handoff_irc_client/Relay.dc.html` — open it in a browser to see the
  intended look and motion.
```
