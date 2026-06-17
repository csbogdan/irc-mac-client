import Foundation

/// A parsed IRC protocol message (RFC 1459/2812, with IRCv3 tags).
struct IRCProtocolMessage: Sendable {
    var tags: [String: String] = [:]
    var prefix: String?          // servername or nick!user@host
    var command: String
    var params: [String]         // includes the trailing param as the last entry

    /// Nick portion of the prefix, if the prefix is a user mask.
    var senderNick: String? {
        guard let prefix else { return nil }
        if let bang = prefix.firstIndex(of: "!") {
            return String(prefix[..<bang])
        }
        return prefix.contains(".") ? nil : prefix
    }
}

/// Stateless line parser. Handles IRCv3 tags, prefixes, command, params and the
/// trailing `:` parameter.
enum IRCProtocolParser {
    static func parse(_ raw: String) -> IRCProtocolMessage? {
        var rest = Substring(raw)
        guard !rest.isEmpty else { return nil }

        var tags: [String: String] = [:]
        if rest.first == "@" {
            rest = rest.dropFirst()
            let segment = rest.prefix(while: { $0 != " " })
            rest = rest.dropFirst(segment.count).drop(while: { $0 == " " })
            for pair in segment.split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                tags[String(kv[0])] = kv.count > 1 ? String(kv[1]) : ""
            }
        }

        var prefix: String?
        if rest.first == ":" {
            rest = rest.dropFirst()
            let segment = rest.prefix(while: { $0 != " " })
            prefix = String(segment)
            rest = rest.dropFirst(segment.count).drop(while: { $0 == " " })
        }

        guard !rest.isEmpty else { return nil }
        let commandSeg = rest.prefix(while: { $0 != " " })
        let command = String(commandSeg).uppercased()
        rest = rest.dropFirst(commandSeg.count).drop(while: { $0 == " " })

        var params: [String] = []
        while !rest.isEmpty {
            if rest.first == ":" {
                params.append(String(rest.dropFirst()))
                break
            }
            let seg = rest.prefix(while: { $0 != " " })
            params.append(String(seg))
            rest = rest.dropFirst(seg.count).drop(while: { $0 == " " })
        }

        return IRCProtocolMessage(tags: tags, prefix: prefix, command: command, params: params)
    }
}
