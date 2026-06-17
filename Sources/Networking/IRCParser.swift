import Foundation

// MARK: - Parsed IRC line (RFC 1459/2812 + IRCv3 message tags)

/// A single parsed IRC protocol line.
///
/// Wire format:  `@tag=value;tag2 :nick!user@host COMMAND param1 param2 :trailing`
struct IRCMessage {
    var tags: [String: String] = [:]
    var prefix: String?          // raw source: "nick!user@host" or "server.name"
    var command: String          // "PRIVMSG", "JOIN", "001", …
    var params: [String] = []    // includes the trailing param as the last element

    /// nick portion of the prefix, if the prefix is a user mask.
    var sourceNick: String? {
        guard let p = prefix, let bang = p.firstIndex(of: "!") else {
            // Could be a server prefix or a bare nick.
            return prefix?.contains(".") == true ? nil : prefix
        }
        return String(p[p.startIndex..<bang])
    }

    var trailing: String? { params.last }
}

// MARK: - Parser

/// Stateless IRC line parser. Pure function so it is trivially testable and
/// can run off the main actor inside the transport actor.
enum IRCParser {

    static func parse(_ raw: String) -> IRCMessage? {
        var line = Substring(raw)
        // Strip trailing CR/LF
        while let last = line.last, last == "\r" || last == "\n" { line = line.dropLast() }
        guard !line.isEmpty else { return nil }

        var msg = IRCMessage(command: "")

        // 1. IRCv3 message tags
        if line.first == "@" {
            let end = line.firstIndex(of: " ") ?? line.endIndex
            let tagBlob = line[line.index(after: line.startIndex)..<end]
            for pair in tagBlob.split(separator: ";") {
                if let eq = pair.firstIndex(of: "=") {
                    let key = String(pair[pair.startIndex..<eq])
                    let value = String(pair[pair.index(after: eq)...])
                    msg.tags[key] = unescapeTagValue(value)
                } else {
                    msg.tags[String(pair)] = ""
                }
            }
            line = line[end...].drop { $0 == " " }
        }

        // 2. Prefix
        if line.first == ":" {
            let end = line.firstIndex(of: " ") ?? line.endIndex
            msg.prefix = String(line[line.index(after: line.startIndex)..<end])
            line = line[end...].drop { $0 == " " }
        }

        // 3. Command
        let cmdEnd = line.firstIndex(of: " ") ?? line.endIndex
        msg.command = String(line[line.startIndex..<cmdEnd]).uppercased()
        line = line[cmdEnd...].drop { $0 == " " }

        // 4. Params (trailing begins at ':')
        while !line.isEmpty {
            if line.first == ":" {
                msg.params.append(String(line.dropFirst()))
                break
            }
            let end = line.firstIndex(of: " ") ?? line.endIndex
            msg.params.append(String(line[line.startIndex..<end]))
            line = line[end...].drop { $0 == " " }
        }

        return msg.command.isEmpty ? nil : msg
    }

    private static func unescapeTagValue(_ v: String) -> String {
        v.replacingOccurrences(of: "\\:", with: ";")
         .replacingOccurrences(of: "\\s", with: " ")
         .replacingOccurrences(of: "\\r", with: "\r")
         .replacingOccurrences(of: "\\n", with: "\n")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: Serialization (client → server)

    static func serialize(command: String, params: [String], tags: [String: String] = [:]) -> String {
        var out = ""
        if !tags.isEmpty {
            let blob = tags.map { $0.value.isEmpty ? $0.key : "\($0.key)=\($0.value)" }.joined(separator: ";")
            out += "@\(blob) "
        }
        out += command
        for (i, p) in params.enumerated() {
            let isLast = i == params.count - 1
            if isLast && (p.contains(" ") || p.hasPrefix(":") || p.isEmpty) {
                out += " :\(p)"
            } else {
                out += " \(p)"
            }
        }
        return out + "\r\n"
    }
}
