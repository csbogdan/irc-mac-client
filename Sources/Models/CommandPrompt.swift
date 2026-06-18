import Foundation

/// One input in a command popup (a reason, mask, duration, level, …).
struct CommandField: Identifiable {
    enum Kind: Equatable { case text, number, choice([String]) }
    let id = UUID()
    var label: String
    var prompt: String = ""      // placeholder / hint
    var value: String = ""       // current value (edited in the popup)
    var required: Bool = false
    var kind: Kind = .text
}

/// A command that needs parameters before it can be sent. The popup collects
/// the fields, then `build` turns them into the wire command (for X commands
/// the inner text; for normal commands a raw IRC line).
struct CommandPrompt: Identifiable {
    let id = UUID()
    var title: String
    var note: String = ""
    var isX: Bool = false
    var networkID: String
    var echoConvID: String
    var fields: [CommandField]
    var build: ([CommandField]) -> String?
}
