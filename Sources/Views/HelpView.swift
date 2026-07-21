import SwiftUI

/// The user guide — complete but plain-spoken. One scrollable page, no jargon,
/// written for people who have never used IRC.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Relay Help").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Everything you need, nothing you don't.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }

                section("Getting started", "power") {
                    step("1.", "Open Settings (⌘,) and add a server — or use the built-in Undernet one.")
                    step("2.", "Pick a nickname. That's your name on the network.")
                    step("3.", "Press Connect next to the network's name in the sidebar. Green dot = you're on.")
                    note("Relay reconnects by itself if the connection drops — it waits a little longer between each try.")
                }

                section("Channels — the group chats", "number") {
                    bullet("A channel is a public room. Names start with #, like #music.")
                    bullet("Join one: type /join #music in the message box, or use the sliders button (top right) → List Channels to browse.")
                    bullet("Leave one: right-click it in the sidebar → Leave Channel.")
                    bullet("The sidebar always shows channels first, then private chats.")
                    note("If a channel refuses you (full, invite-only, banned, or it needs a password), Relay tells you why and offers a fix button.")
                }

                section("Talking", "bubble.left.and.bubble.right") {
                    bullet("Type and press Return. Shift+Return makes a new line.")
                    bullet("/me waves — sends an action line: ✶ you waves.")
                    bullet("Private chat: right-click a person → Message, or type /msg name hello.")
                    bullet("Double-click a private chat in the sidebar to see who the person really is.")
                    bullet("Hover a link in chat for a moment — a little preview pops up.")
                    bullet("The 🎨 button (or right-click a person → Send ASCII Art) sends colourful old-school art.")
                }

                section("Speed tricks", "bolt") {
                    bullet("Tab completes names: type fr, press Tab — press Tab again to cycle matches.")
                    bullet("↑ and ↓ bring back things you typed before.")
                    bullet("⌘K opens the quick switcher; ⌘1–9 jump straight to a conversation.")
                    bullet("Type / to see the command list with hints.")
                }

                section("Badges & notifications", "bell.badge") {
                    bullet("Red badge: someone said your name (or a keyword you set in Settings).")
                    bullet("Blue badge: other new activity.")
                    bullet("When Relay is in the background, mentions and private messages appear in Notification Center. Click one to jump right to it.")
                    bullet("Too noisy? Right-click a channel → Quiet Channel: no badges, no notifications from it. Unquiet any time.")
                }

                section("Dealing with annoying people", "hand.raised") {
                    bullet("/ignore name — Relay hides everything they say (only on your side).")
                    bullet("/unignore name — undo it.")
                    bullet("/silence name — the server itself stops delivering their messages to you (works on Undernet).")
                    bullet("Both are also in the right-click menu on any person.")
                }

                section("Privacy", "eye.slash") {
                    bullet("Private Session (right-click a network's name): reconnects you with a random name into a fresh secret room. No auto-joins, no saved commands run.")
                    bullet("Change your name any time: /nick newname.")
                    note("Relay also paces what it sends so the server never kicks you for \"flooding\" — long pastes go out slowly on purpose.")
                }

                section("Common commands", "terminal") {
                    cmd("/join #room", "enter a channel")
                    cmd("/part", "leave the current channel")
                    cmd("/msg name text", "private message")
                    cmd("/me action", "action line")
                    cmd("/nick newname", "change your name")
                    cmd("/whois name", "who is this person (shows idle & away too)")
                    cmd("/topic text", "set the channel topic")
                    cmd("/list", "browse all channels")
                    cmd("/ignore name", "hide someone (local)")
                    cmd("/silence name", "block someone (server)")
                    cmd("/invite name", "invite someone here")
                }

                section("The X bot (Undernet)", "gearshape.2") {
                    bullet("X is Undernet's channel-service robot. Registered channels use it for ops, bans and invites.")
                    bullet("You'll find X actions in right-click menus — on people (Channel Service submenu) and on channels in the sidebar.")
                    note("No setup needed — if a channel uses X and you have access, the menu items just work.")
                }

                Text("Made by Rufus · Relay is an homage to mIRC 🐟")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 640)
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section(_ title: String, _ icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.leading, 2)
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(n).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12.5))
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("•").foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12.5))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    private func cmd(_ command: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 170, alignment: .leading)
            Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
