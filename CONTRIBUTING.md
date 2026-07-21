# Contributing to Relay

Thanks for caring about a vibe-coded IRC client. Ground rules — short on purpose.

## Bugs & ideas

Use the [issue templates](https://github.com/csbogdan/irc-mac-client/issues/new/choose). For bugs: Relay version (About window), macOS version, a screenshot, and the server console output (click the network's name in the sidebar) get you a fix fastest.

## Building

```sh
brew install xcodegen
xcodegen generate          # the .xcodeproj is generated, never committed
open Relay.xcodeproj       # ⌘R — or:
xcodebuild -project Relay.xcodeproj -scheme Relay -configuration Release build
swift test                 # parser unit tests
```

Requires Xcode 16+ on macOS 14+. Liquid Glass effects need the macOS 26 SDK but the app builds and runs fine without seeing them.

## Pull requests

- **Small and focused** — one thing per PR. Big rewrites will be closed with affection.
- **Match the house style**: comment density, naming, and idiom of the surrounding code. The codebase favors small SwiftUI views, one `@Observable` model, and an actor per socket.
- **UI changes need screenshots** in the PR (dark mode).
- **If behavior changes, the manual changes** — in both places: `Sources/Views/HelpView.swift` (the in-app ⌘? manual) and the [wiki](https://github.com/csbogdan/irc-mac-client/wiki). PRs that add features without docs aren't done.
- Parser or protocol changes should come with a test in `Tests/`.

## License terms

By submitting a contribution you agree it's licensed under the repository's
[PolyForm Noncommercial 1.0.0](LICENSE) license, with copyright assigned to the
project. Nobody sells Relay — including forks of your contribution.
