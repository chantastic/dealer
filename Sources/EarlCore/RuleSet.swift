import Foundation

/// The contents of `rules.json`.
public struct RuleSet: Codable, Equatable, Sendable {
    /// Schema version. Only `1` exists today; it is reserved for future migrations.
    public var version: Int?
    /// Profile (display name, email, or directory) for URLs no rule matches.
    /// When omitted, unmatched URLs open in whichever profile Chrome used last.
    public var defaultProfile: String?
    public var browser: BrowserConfig?
    public var rules: [Rule]

    public init(
        version: Int? = 1,
        defaultProfile: String? = nil,
        browser: BrowserConfig? = nil,
        rules: [Rule] = []
    ) {
        self.version = version
        self.defaultProfile = defaultProfile
        self.browser = browser
        self.rules = rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        defaultProfile = try container.decodeIfPresent(String.self, forKey: .defaultProfile)
        browser = try container.decodeIfPresent(BrowserConfig.self, forKey: .browser)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

/// Which Chromium-based browser to launch and where to find its profile list.
public struct BrowserConfig: Codable, Equatable, Sendable {
    /// Application name or path passed to `open -a`. Defaults to `Google Chrome`.
    public var application: String?
    /// Bundle identifier passed to `open -b`. Takes precedence over `application`.
    public var bundleIdentifier: String?
    /// Path to the browser's `Local State` file. `~` is expanded.
    public var localState: String?

    public init(application: String? = nil, bundleIdentifier: String? = nil, localState: String? = nil) {
        self.application = application
        self.bundleIdentifier = bundleIdentifier
        self.localState = localState
    }
}

/// A single routing rule. A rule matches when *any* of its patterns match; rules are
/// evaluated top to bottom and the first match wins.
public struct Rule: Codable, Equatable, Sendable {
    public var name: String?
    public var enabled: Bool
    /// Host globs, e.g. `github.com`, `*.corp.example.com`.
    public var hosts: [String]
    /// URL globs, e.g. `github.com/acme/*` or `https://docs.google.com/*/d/*`.
    public var urls: [String]
    /// Regular expressions matched against the full URL.
    public var regex: [String]
    /// Profile display name, account email, or profile directory (e.g. `Profile 2`).
    public var profile: String

    public init(
        name: String? = nil,
        enabled: Bool = true,
        hosts: [String] = [],
        urls: [String] = [],
        regex: [String] = [],
        profile: String
    ) {
        self.name = name
        self.enabled = enabled
        self.hosts = hosts
        self.urls = urls
        self.regex = regex
        self.profile = profile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        hosts = try container.decodeIfPresent(OneOrMany.self, forKey: .hosts)?.values ?? []
        urls = try container.decodeIfPresent(OneOrMany.self, forKey: .urls)?.values ?? []
        regex = try container.decodeIfPresent(OneOrMany.self, forKey: .regex)?.values ?? []
        profile = try container.decode(String.self, forKey: .profile)
    }

    public var hasPatterns: Bool {
        !(hosts.isEmpty && urls.isEmpty && regex.isEmpty)
    }
}

/// Accepts either `"value"` or `["a", "b"]` so single-pattern rules stay terse.
private struct OneOrMany: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = try container.decode([String].self)
        }
    }
}
