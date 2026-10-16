import Foundation

/// A minimal shell-style glob: `*` matches any run of characters (including `/` and `.`),
/// `?` matches exactly one character, and `\` escapes the next character.
public struct Glob: Hashable, Sendable {
    public let pattern: String
    public let caseSensitive: Bool

    private enum Token: Hashable, Sendable {
        case literal(Character)
        case single
        case star
    }

    private let tokens: [Token]

    public init(_ pattern: String, caseSensitive: Bool = false) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive

        let source = caseSensitive ? pattern : pattern.lowercased()
        var tokens: [Token] = []
        var escaping = false
        for character in source {
            if escaping {
                tokens.append(.literal(character))
                escaping = false
                continue
            }
            switch character {
            case "\\":
                escaping = true
            case "*":
                // Collapse runs of `*` so `**` behaves like `*`.
                if tokens.last != .star { tokens.append(.star) }
            case "?":
                tokens.append(.single)
            default:
                tokens.append(.literal(character))
            }
        }
        if escaping { tokens.append(.literal("\\")) }
        self.tokens = tokens
    }

    public func matches(_ candidate: String) -> Bool {
        let input = Array(caseSensitive ? candidate : candidate.lowercased())
        var p = 0
        var s = 0
        var starToken = -1
        var starInput = 0

        func isStar(_ index: Int) -> Bool {
            index < tokens.count && tokens[index] == .star
        }

        while s < input.count {
            if isStar(p) {
                starToken = p
                starInput = s
                p += 1
                continue
            }
            if p < tokens.count {
                switch tokens[p] {
                case .single:
                    p += 1
                    s += 1
                    continue
                case .literal(let character) where character == input[s]:
                    p += 1
                    s += 1
                    continue
                default:
                    break
                }
            }
            guard starToken >= 0 else { return false }
            p = starToken + 1
            starInput += 1
            s = starInput
        }

        while isStar(p) { p += 1 }
        return p == tokens.count
    }
}
