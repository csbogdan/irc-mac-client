import SwiftUI

/// The user manual: a topic sidebar + detail pages. Complete coverage of every
/// feature and option, written plainly for people who have never used IRC.
struct HelpView: View {
    @State private var topic: HelpTopic = .welcome

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: Binding(get: { topic }, set: { topic = $0 ?? .welcome })) { t in
                Label(t.title, systemImage: t.icon).tag(t)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(topic.title).font(.system(size: 22, weight: .bold, design: .rounded))
                    topic.page
                }
                .padding(26)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 540, idealHeight: 640)
    }
}

// MARK: - Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case welcome, gettingStarted, settings, connecting, sidebar, channels, talking, composerTricks,
         directMessages, notifications, blocking, privateSessions, xService, asciiArt,
         commands, shortcuts, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:         return "Welcome"
        case .gettingStarted:  return "Getting Started"
        case .settings:        return "Settings Explained"
        case .connecting:      return "Connecting & Reconnecting"
        case .sidebar:         return "The Sidebar"
        case .channels:        return "Channels"
        case .talking:         return "Talking"
        case .composerTricks:  return "Composer Tricks"
        case .directMessages:  return "Private Messages"
        case .notifications:   return "Notifications & Quiet"
        case .blocking:        return "Blocking People"
        case .privateSessions: return "Private Sessions"
        case .xService:        return "The X Service (Undernet)"
        case .asciiArt:        return "ASCII Art"
        case .commands:        return "All Commands"
        case .shortcuts:       return "Keyboard Shortcuts"
        case .troubleshooting: return "Troubleshooting"
        }
    }

    var icon: String {
        switch self {
        case .welcome:         return "hand.wave"
        case .gettingStarted:  return "power"
        case .settings:        return "gearshape"
        case .connecting:      return "bolt.horizontal"
        case .sidebar:         return "sidebar.left"
        case .channels:        return "number"
        case .talking:         return "bubble.left.and.bubble.right"
        case .composerTricks:  return "keyboard"
        case .directMessages:  return "person.2"
        case .notifications:   return "bell.badge"
        case .blocking:        return "hand.raised"
        case .privateSessions: return "eye.slash"
        case .xService:        return "gearshape.2"
        case .asciiArt:        return "paintpalette"
        case .commands:        return "terminal"
        case .shortcuts:       return "command"
        case .troubleshooting: return "wrench.and.screwdriver"
        }
    }

    @ViewBuilder var page: some View {
        switch self {
        case .welcome: HelpPage {
            P("Relay is a chat app for IRC — the internet's original group chat, running since the late '80s and still alive. You connect to a network (like Undernet), join channels (public rooms whose names start with #), and talk.")
            P("Nobody makes an account for you. You just pick a nickname, connect, and you exist. When you leave, you're gone. That simplicity is the charm.")
            Note("Everything in Relay is reachable two ways: type a /command in the message box, or right-click things — people, channels, network names. When in doubt, right-click it.")
        }

        case .gettingStarted: HelpPage {
            H("First run")
            Step("1.", "Open Settings (⌘,) → Connections. A server entry for Undernet is already there — or press + to add your own.")
            Step("2.", "Fill in a Nickname. That's your name on the network.")
            Step("3.", "Press Connect. The dot next to the network name turns green when you're on.")
            H("Server settings, field by field")
            Field("Name", "just a label for your own sidebar.")
            Field("Host / Port", "the server's address. Undernet: irc.undernet.org, port 6667 (or 6697 with TLS).")
            Field("Use TLS / SSL", "encrypts the connection to the server. Turn on if the network supports it.")
            Field("Nickname", "your name in chat. Letters, digits, and a few symbols.")
            Field("Alternate nickname", "used automatically if your first choice is taken.")
            Field("Username", "the technical login name shown in your address (nick!username@host). Leave blank to reuse your nickname.")
            Field("Real name", "free text shown when someone looks you up with /whois. Doesn't have to be real.")
            Field("Server password", "only if your server requires one. Most don't.")
            Field("Authenticate with SASL", "logs you into your registered account (if the network supports it) during connect — before anyone can see you.")
            Field("Connect on launch", "opens this connection automatically when Relay starts.")
            Field("Reconnect automatically", "if the line drops, Relay redials it for you (see Connecting & Reconnecting).")
            Note("Every other switch — user modes, perform commands, auto-join, art, notifications — is covered field by field in Settings Explained (next page).")
        }

        case .settings: HelpPage {
            P("Everything in Settings (⌘,), tab by tab, switch by switch.")

            H("Connections — the server list")
            Bullet("Left side: your servers. + adds one, − deletes the selected one. The dot shows its live state; Connect/Disconnect sits at the top of the editor.")
            P("The Server, Identity and Authentication fields are covered in Getting Started. Below are the rest:")

            H("User Modes (set on connect)")
            P("Switches the server flips on you automatically, right after every connect:")
            Field("+i Invisible", "hides you from /who and /names for people not in a channel with you.")
            Field("+w Wallops", "receive network-wide announcements from IRC operators.")
            Field("+d Deaf", "stop receiving channel chat; you still see joins, parts, topics and modes.")
            Field("+x Hidden host", "masks your address as account.users.undernet.org — needs an X login (put it in On Connect below). Recommended.")

            H("On Connect — the perform list")
            P("Commands Relay types for you after every connect, top to bottom. This is where logins go.")
            Bullet("Each row is one command plus a delay in seconds. The delay is a wait BEFORE that command is sent — use it to let the connection settle or a previous login land.")
            Bullet("Write commands exactly as you'd type them in the message box (/msg x@channels.undernet.org login name pass) or as raw IRC (MODE %nick% +x).")
            Bullet("%nick% is replaced with your current nickname — useful because your nick can change on collision.")
            Bullet("Drag rows to reorder; the − removes one. The whole list always finishes before any channel is joined.")
            Note("Classic Undernet setup: row 1 = your X login. Combined with the +x user mode, your real address is hidden before you enter a single room.")

            H("Delay before joining channels")
            P("An extra pause (seconds) between the last perform command and the channel joins — give a login a moment to take effect so you join rooms with your host already masked.")

            H("Auto-join Channels")
            P("The rooms Relay enters for you on every connect (after the performs and the delay). Type a name and press Add — the # is optional, Relay adds it. The − removes one. After an automatic reconnect, Relay also rejoins whatever else was open in your sidebar.")

            H("Options")
            Field("Connect on launch", "this network dials as soon as Relay starts.")
            Field("Reconnect automatically", "redial with growing pauses when the connection drops unexpectedly.")

            H("ASCII Art tab")
            Bullet("Your personal art lines, available under 🎨 → My Art and in right-click menus.")
            Bullet("Name = the menu label. Template = the actual line; put %nick% where a name should go.")
            Bullet("Colours are mIRC codes (the \\u{3} control character + a colour number 0–15). The dark strip under each row previews exactly what will be sent.")

            H("Appearance tab")
            Field("Appearance", "System, Light or Dark — follows or overrides macOS.")
            Field("Show timestamps", "the small clock next to names in chat. Off = cleaner, denser look.")

            H("Notifications tab")
            Field("Notify on mentions", "a Notification Center banner when someone says your name (or a keyword) in a channel — only while Relay is in the background.")
            Field("Notify on direct messages", "same, for private messages.")
            Field("Dock icon count", "the total unread number on Relay's Dock icon.")
            Field("Highlight keywords", "extra words that count as mentions — red badge, highlight and notification. Your nickname always counts; add project names, your real name, topics you care about.")

            Note("Channel-specific settings (modes, bans, topic) live on the channel itself: double-click the topic bar. X service options (AUTOJOIN, AUTOTOPIC, floating limits…) are under the toolbar sliders → Channel Settings (X) — see The X Service page.")
        }

        case .connecting: HelpPage {
            H("What the colored dot means")
            Bullet("Green — connected. Yellow — connecting or registering. Grey — offline.")
            H("If the connection drops")
            P("With \"Reconnect automatically\" on, Relay redials by itself: it waits 2 seconds, then 4, 8, 16… up to 5 minutes between tries, and tells you what it's doing in the server console. Your channels are rejoined automatically once you're back.")
            P("Pressing Disconnect yourself stops the redialing — Relay only reconnects when the drop wasn't your idea.")
            H("On Connect — things Relay does for you each time")
            Bullet("User modes: toggles like +x (hide your internet address on Undernet — recommended). Set once in Settings, applied every connect.")
            Bullet("Commands: a list of things to run on every connect — for example logging into the X service. Each command can wait a few seconds before running; they always finish before any channel is joined. Use %nick% to mean your current nickname.")
            Bullet("Delay before joining: an extra pause between the commands and the channel joins — useful when a login needs a moment to take effect.")
            Bullet("Auto-join channels: the rooms Relay enters for you on every connect.")
            Note("The same order applies after an automatic reconnect: modes → commands → pause → channels. Your login always happens before you re-enter rooms.")
        }

        case .sidebar: HelpPage {
            P("The left column lists everything, per network: the server console first (the terminal icon — raw server messages live there), then all channels, then all private chats.")
            H("Badges")
            Bullet("Red badge — someone said your name (or one of your highlight keywords) in that channel.")
            Bullet("Blue badge — other new activity you haven't seen.")
            Bullet("Bell-with-slash icon — the conversation is quiet (see Notifications & Quiet).")
            H("Things to click")
            Bullet("Click a row to open it. Double-click a private chat to look the person up (/whois).")
            Bullet("Right-click a row for its menu: mark as read, quiet, leave/close, X service actions.")
            Bullet("Right-click the network's name: Connect/Disconnect and Private Session.")
            Bullet("Click the network's name to open the server console.")
            H("The Dock icon")
            P("The total unread count appears on Relay's Dock icon. Turn it off in Settings → Notifications.")
        }

        case .channels: HelpPage {
            H("Joining")
            Bullet("Type /join #channelname — or browse: toolbar sliders button → List Channels shows every public channel with its member count.")
            Bullet("Channel names aren't case-sensitive: #Music and #music are the same room. Relay shows the official casing.")
            H("The topic bar")
            P("The line under the toolbar is the channel's topic. Double-click it to open Channel Modes — a sheet with the topic editor, channel switches, and the ban list.")
            H("Channel modes, in plain words")
            Field("+i", "invite-only — you need an invitation to enter.")
            Field("+k", "a password (\"key\") is required to enter.")
            Field("+l", "a maximum number of people.")
            Field("+m", "moderated — only ops and voiced people can talk.")
            Field("+s", "secret — the channel doesn't appear in /list.")
            Field("+t", "only ops can change the topic.")
            H("People & roles")
            Bullet("@ green — operator (op): can kick, ban, set modes, change topic.")
            Bullet("+ blue — voiced: may talk even when the channel is moderated.")
            Bullet("The member list on the right groups people by role. Click to select, right-click for actions: whois, message, art, op/voice, kick/ban, ignore, X commands.")
            Bullet("A hollow dot and grey italic name means the person is marked away.")
            H("Leaving")
            P("Right-click the channel → Leave Channel, or type /part while in it.")
        }

        case .talking: HelpPage {
            Bullet("Type and press Return to send. Shift+Return makes a new line without sending.")
            Bullet("/me waves → shows as \"✶ yourname waves\" — the classic action line.")
            Bullet("Messages from the same person group together; the coloured circle shows who's talking.")
            Bullet("A message that mentions you gets a blue edge marker and your name in a pill.")
            Bullet("Old-style colour codes from other clients (mIRC colours) are rendered properly.")
            Bullet("Hover a message containing a link for a second — a small preview card pops up. Click it to open the page.")
            Bullet("Click a name in chat to find that person in the member list; right-click the name for the full member menu (message, op, kick, X, …).")
            Bullet("Select text with the mouse and copy as usual; right-click a message for Copy Message and per-person actions.")
            H("Finding things")
            Bullet("⌘F searches inside the current channel. Matching lines only; press the ✕ to go back.")
            Bullet("If you scrolled up, a Jump to latest pill appears bottom-right.")
            Bullet("A \"NEW MESSAGES\" line marks where you left off.")
        }

        case .composerTricks: HelpPage {
            Bullet("Tab completion: type the first letters of a name and press Tab. Press Tab again to cycle through everyone that matches. At the start of a line you get \"name: \", mid-sentence just the name.")
            Bullet("The same works for channels: type #mu + Tab.")
            Bullet("↑ and ↓ recall everything you've sent this session — walk up through history, edit, resend. Whatever you were typing is kept and comes back when you walk down past the newest entry.")
            Bullet("Type / to open the command list with argument hints — arrow keys or Tab pick one.")
            Bullet("The 🎨 button sends ASCII art (see the ASCII Art page).")
            Bullet("Long pastes are sent at a polite pace on purpose — servers disconnect people who send too fast. Relay never lets that happen (see Troubleshooting).")
        }

        case .directMessages: HelpPage {
            H("Starting one")
            Bullet("Right-click a person anywhere → Message.")
            Bullet("Or type /msg theirname hello — it opens the chat and sends the first line.")
            Bullet("If someone messages you first, the chat simply appears in your sidebar.")
            Bullet("Nicknames aren't case-sensitive — x and X are the same person, one chat.")
            H("Who is this person?")
            P("Double-click any private chat in the sidebar — Relay runs /whois and prints who they are: their address, server, how long they've been idle, when they signed on, and whether they're marked away.")
            Note("Anyone can message you. If someone is a pest, see Blocking People.")
        }

        case .notifications: HelpPage {
            H("What notifies")
            P("When Relay is in the background, two things reach Notification Center: someone saying your name in a channel, and any private message. Clicking a notification brings you straight to that conversation. While you're actively using Relay, nothing pops — the sidebar badges cover it.")
            H("The switches (Settings → Notifications)")
            Field("Notify on mentions", "channel messages that contain your name or a keyword.")
            Field("Notify on direct messages", "private messages.")
            Field("Show unread count on Dock icon", "the little number on the Dock.")
            H("Highlight keywords")
            P("Add words like \"deploy\" or your project's name — messages containing them count as mentions: red badge, highlight, notification. Your nickname always counts.")
            H("Quiet")
            P("Right-click any channel or chat → Quiet. A quiet conversation collects no badges and sends no notifications — it just sits there until you open it. A small bell-with-slash marks it. Unquiet the same way.")
        }

        case .blocking: HelpPage {
            H("Two tools, different strength")
            Field("/ignore name", "Relay hides everything from that person — on your Mac only. They don't know. /unignore name undoes it; /ignore alone lists who you're ignoring. Survives restarts.")
            Field("/silence name", "the server itself stops delivering their messages to you (Undernet feature). Works even before the messages reach Relay. /silence -name!*@* lifts it; /silence alone lists the server's masks.")
            P("Both are also in the right-click menu on any person in the member list.")
            Note("Rule of thumb: /ignore is enough for noise. /silence is for harassment — it blocks them at the source, including private messages.")
        }

        case .privateSessions: HelpPage {
            H("Starting one")
            Bullet("Right-click the network's name in the sidebar → Private Session.")
            Bullet("Or File → New Private Session (⇧⌘N) for the current network.")
            H("What happens, step by step")
            Step("1.", "Your current connection is closed.")
            Step("2.", "Relay reconnects under a random, unremarkable nickname (e.g. quietowl42).")
            Step("3.", "None of your usual on-connect commands or auto-joins run — nothing identifies you.")
            Step("4.", "Relay creates a random empty channel (like #k3x9w2qa) and joins it.")
            Step("5.", "The channel is set +s (secret): it appears in no channel list and no whois.")
            H("Using it")
            P("Invite people with /invite theirname — they're the only ones who can find it. You have ops, so the room is yours.")
            H("Leaving")
            P("Press Disconnect, then Connect — you're back to your normal nickname, commands, and channels.")
        }

        case .xService: HelpPage {
            P("X is Undernet's channel-service robot. Registered channels use it as the referee: it remembers who has access, hands out ops, and enforces bans — even when no human op is around.")
            H("Logging in")
            P("If you have an X account (username + password from undernet.org), add your login as an On-Connect command in Settings, e.g.: /msg x@channels.undernet.org login yourname yourpass — with +x enabled, your address is hidden before you join any channel.")
            H("On a person (right-click in the member list → Channel Service)")
            Bullet("Op / Deop / Voice / Devoice via X — X changes their role.")
            Bullet("Kick / Ban / Unban via X — with a popup for reason, duration and ban level.")
            Bullet("Access level, Add to userlist, Suspend, Remove — manage who's on the channel's list.")
            H("On a channel (right-click it in the sidebar → Channel Service)")
            Bullet("Channel Info, Access List, Ban List — ask X what it knows.")
            Bullet("Set Topic, Invite Me, Op Me, Deop Me, Clear Modes.")
            H("X channel settings (toolbar sliders → Channel Settings (X))")
            P("For channels you manage, a sheet drives X's per-channel options: AUTOJOIN (X rejoins after downtime), AUTOTOPIC (reset topic every 30 min), NOOP / STRICTOP (who may be opped), the floating user limit (FLOATLIM and friends), MASSDEOPPRO (anti-takeover), plus DESCRIPTION, URL and KEYWORDS. Each control explains itself in the sheet.")
            P("Your personal X options are there too: INVISIBLE (hide your X status), NOADDUSER (nobody can add you to channel lists), LANG (X's reply language).")

            H("When a channel won't let you in")
            P("Relay recognises the four refusals and offers the fix in a dialog:")
            Field("Full (+l)", "a Try Again button.")
            Field("Invite-only (+i)", "Ask X for an Invite — then rejoins for you.")
            Field("Banned (+b)", "Ask X to Unban Me — then rejoins for you.")
            Field("Needs a key (+k)", "type the key right in the dialog and join.")
            Note("The X buttons work when you have access on that channel's userlist. If X ignores you, you're not on the list — ask a channel manager.")
        }

        case .asciiArt: HelpPage {
            P("The 🎨 button in the composer holds a catalog of colourful one-liners — greetings, table flips, trout slaps and other IRC folklore. Click one to send it to the current conversation.")
            Bullet("Right-click a person → Send ASCII Art aims it at them: every %nick% in the art becomes their name.")
            Bullet("In a private chat, art from the palette automatically addresses the person you're talking to.")
            H("Your own art")
            P("Settings → ASCII Art: add your own lines. Use %nick% where a name should go. Colours use mIRC codes (Ctrl-style \\u{3} followed by a colour number) — the live preview under the field shows exactly how it will look.")
        }

        case .commands: HelpPage {
            P("Type these in the message box. Things in ⟨⟩ are yours to fill in.")
            H("Everyday")
            Cmd("/join ⟨#room⟩", "enter a channel")
            Cmd("/part", "leave the current channel")
            Cmd("/msg ⟨name⟩ ⟨text⟩", "private message (also: /query)")
            Cmd("/me ⟨does something⟩", "action line")
            Cmd("/nick ⟨newname⟩", "change your nickname")
            Cmd("/whois ⟨name⟩", "who is this person — includes idle time & away")
            Cmd("/topic ⟨text⟩", "set the channel topic")
            Cmd("/list", "browse all channels (add a pattern to filter)")
            Cmd("/invite ⟨name⟩", "invite someone to the current channel")
            H("Peace & quiet")
            Cmd("/ignore ⟨name⟩", "hide someone locally (alone: show the list)")
            Cmd("/unignore ⟨name⟩", "stop hiding them")
            Cmd("/silence ⟨name⟩", "server-side block, Undernet (alone: show the list)")
            H("Channel management")
            Cmd("/ban ⟨name⟩ · /unban ⟨name⟩", "quick ban as name!*@* in the current channel")
            Cmd("/mode ⟨#room⟩ ⟨+/-modes⟩", "set modes by hand")
            Cmd("/kick ⟨#room⟩ ⟨name⟩", "kick (you need ops)")
            H("Anything else")
            Cmd("/ctcp ⟨name⟩ ⟨COMMAND⟩", "client-to-client query, e.g. VERSION or PING")
            P("Any command Relay doesn't recognise is sent to the server as-is — /away, /who, /names and friends all work exactly as on any IRC client.")
        }

        case .shortcuts: HelpPage {
            Key("⌘K", "Quick Switcher — jump to any conversation by typing")
            Key("⌘1 … ⌘9", "jump to conversation 1–9")
            Key("⌘F", "find in the current conversation")
            Key("⌘N", "new connection")
            Key("⇧⌘N", "new private session")
            Key("⌥⌘M", "show/hide the member list")
            Key("⌘,", "Settings")
            Key("⌘?", "this manual")
            Key("Tab", "complete names & channels (again: cycle matches)")
            Key("↑ / ↓", "input history")
            Key("⇧↩", "new line without sending")
        }

        case .troubleshooting: HelpPage {
            H("\"Nickname is already in use\"")
            P("Someone else has it. Relay tries your alternate nickname automatically, then variations with underscores. Get your own back later with /nick yourname.")
            H("I can't join a channel")
            P("The channel is full, invite-only, banned you, or wants a key. Relay shows which one it is and offers the fix — see The X Service page.")
            H("My messages send slowly when I paste a lot")
            P("On purpose. IRC servers disconnect people who send too many lines at once (\"Excess Flood\"). Relay lets a short burst through, then paces itself at about one line per second. Everything arrives; nobody gets kicked.")
            H("The connection keeps dropping")
            P("Relay redials with growing pauses (2s, 4s, 8s… up to 5 minutes) and rejoins your channels. Watch the server console — the terminal icon at the top of each network — for what the server says. \"Reconnect automatically\" must be on in Settings → Connections.")
            H("Someone is flooding a channel with junk")
            P("/ignore their name (local) or /silence them (server). Ops can right-click → Kick or Ban. Registered channels: use the X commands.")
            H("A notification didn't appear")
            P("Check: Settings → Notifications switches on? The channel isn't quiet (bell-slash icon)? macOS System Settings → Notifications allows Relay? Notifications only pop while Relay is in the background — when it's frontmost, badges do the job.")
            H("Where do server messages go?")
            P("Every network's raw traffic lives in its server console — click the network's name in the sidebar. When something acts odd, the explanation is usually printed there.")
        }
        }
    }
}

// MARK: - Page building blocks

private struct HelpPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
    }
}

private func H(_ text: String) -> some View {
    Text(text).font(.system(size: 14.5, weight: .semibold)).padding(.top, 8)
}

private func P(_ text: String) -> some View {
    Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
}

private func Bullet(_ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text("•").foregroundStyle(.tertiary)
        Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
    }
}

private func Step(_ n: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(n).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.secondary)
        Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
    }
}

private func Field(_ name: String, _ desc: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(name)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 150, alignment: .trailing)
        Text(desc).font(.system(size: 12.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func Cmd(_ command: String, _ desc: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(command)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 210, alignment: .leading)
        Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func Key(_ key: String, _ desc: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(key)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.5)))
            .frame(width: 110, alignment: .leading)
        Text(desc).font(.system(size: 12.5))
    }
}

private func Note(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11.5)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
}
