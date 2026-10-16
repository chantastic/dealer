import Foundation

/// Matches a URL's host against a glob such as `github.com`, `*.atlassian.net`, or `localhost:3000`.
///
/// - Matching is case-insensitive and ignores a trailing `.` on fully-qualified hosts.
/// - A leading `*.` also matches the bare domain, so `*.google.com` matches `google.com`.
/// - If the pattern contains `:`, it is matched against `host:port` instead of the host alone.
public struct HostPattern: Hashable, Sendable {
    public let pattern: String
    private let glob: Glob
    private let apexGlob: Glob?
    private let includesPort: Bool

    public init(_ pattern: String) {
        var normalized = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        if normalized.hasSuffix(".") { normalized.removeLast() }
        self.pattern = pattern
        self.glob = Glob(normalized)
        self.apexGlob = normalized.hasPrefix("*.") ? Glob(String(normalized.dropFirst(2))) : nil
        self.includesPort = normalized.contains(":")
    }

    public func matches(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        if includesPort {
            guard let port = url.port else { return false }
            host += ":\(port)"
        }
        return glob.matches(host) || apexGlob?.matches(host) == true
    }
}

/// Matches a whole URL against a glob, case-insensitively.
///
/// Patterns that contain `://` are matched against the full URL. Patterns without a scheme
/// (e.g. `github.com/acme/*`) are matched against the URL with its `scheme://` prefix removed.
public struct URLPattern: Hashable, Sendable {
    public let pattern: String
    private let glob: Glob
    private let hasScheme: Bool

    public init(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        self.pattern = pattern
        self.glob = Glob(trimmed)
        self.hasScheme = trimmed.contains("://")
    }

    public func matches(_ url: URL) -> Bool {
        let absolute = url.absoluteString
        if hasScheme { return glob.matches(absolute) }
        guard let separator = absolute.range(of: "://") else { return glob.matches(absolute) }
        return glob.matches(String(absolute[separator.upperBound...]))
    }
}

/// Matches the full URL string against a regular expression. Matching is unanchored and
/// case-sensitive unless the expression says otherwise (use `^`, `$`, and `(?i)`).
public struct RegexPattern {
    public let pattern: String
    private let expression: NSRegularExpression

    public init(_ pattern: String) throws {
        self.pattern = pattern
        self.expression = try NSRegularExpression(pattern: pattern)
    }

    public func matches(_ url: URL) -> Bool {
        let absolute = url.absoluteString
        let range = NSRange(absolute.startIndex..<absolute.endIndex, in: absolute)
        return expression.firstMatch(in: absolute, options: [], range: range) != nil
    }
}
