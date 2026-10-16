import Foundation

/// The outcome of routing one URL.
public struct RoutingDecision: Equatable, Sendable {
    public var url: URL
    /// Name of the rule that matched, or `nil` if the URL fell through to the default.
    public var matchedRule: String?
    /// The profile reference from the rule or `defaultProfile`, as written in the rules file.
    public var requestedProfile: String?
    /// The resolved `--profile-directory`, or `nil` to let Chrome pick its last-used profile.
    public var profileDirectory: String?
    /// Human-readable explanations for anything surprising (e.g. an unknown profile name).
    public var notes: [String]

    public init(
        url: URL,
        matchedRule: String? = nil,
        requestedProfile: String? = nil,
        profileDirectory: String? = nil,
        notes: [String] = []
    ) {
        self.url = url
        self.matchedRule = matchedRule
        self.requestedProfile = requestedProfile
        self.profileDirectory = profileDirectory
        self.notes = notes
    }
}

public struct CompiledRule {
    public let rule: Rule
    public let displayName: String
    let hostPatterns: [HostPattern]
    let urlPatterns: [URLPattern]
    let regexPatterns: [RegexPattern]

    public func matches(_ url: URL) -> Bool {
        hostPatterns.contains { $0.matches(url) }
            || urlPatterns.contains { $0.matches(url) }
            || regexPatterns.contains { $0.matches(url) }
    }
}

/// Compiles a `RuleSet` once and routes URLs against it.
public struct Router {
    public let ruleSet: RuleSet
    public let rules: [CompiledRule]
    /// Problems found while compiling (invalid regexes, empty rules, suspicious patterns).
    /// Problematic patterns are skipped; the rest of the rules still apply.
    public let issues: [String]

    public init(ruleSet: RuleSet) {
        self.ruleSet = ruleSet
        var compiled: [CompiledRule] = []
        var issues: [String] = []

        for (index, rule) in ruleSet.rules.enumerated() {
            let displayName = rule.name ?? "rule #\(index + 1)"
            guard rule.enabled else { continue }
            if !rule.hasPatterns {
                issues.append("\(displayName) has no hosts, urls, or regex and will never match.")
            }
            for host in rule.hosts where host.contains("/") {
                issues.append("\(displayName): host pattern \"\(host)\" contains '/'; hosts only match the hostname. Use \"urls\" for paths.")
            }
            var regexes: [RegexPattern] = []
            for pattern in rule.regex {
                do {
                    regexes.append(try RegexPattern(pattern))
                } catch {
                    issues.append("\(displayName): invalid regex \"\(pattern)\" was skipped.")
                }
            }
            compiled.append(CompiledRule(
                rule: rule,
                displayName: displayName,
                hostPatterns: rule.hosts.map(HostPattern.init),
                urlPatterns: rule.urls.map(URLPattern.init),
                regexPatterns: regexes
            ))
        }

        self.rules = compiled
        self.issues = issues
    }

    /// Profile references in the rules file that don't correspond to any known profile.
    public func unresolvedProfiles(in profiles: [ChromeProfile]) -> [String] {
        guard !profiles.isEmpty else { return [] }
        var references = rules.map(\.rule.profile)
        if let fallback = ruleSet.defaultProfile { references.append(fallback) }
        var seen = Set<String>()
        return references.filter { reference in
            guard seen.insert(reference).inserted else { return false }
            return ProfileResolver.resolve(reference, in: profiles) == nil
        }
    }

    public func route(_ url: URL, profiles: [ChromeProfile]) -> RoutingDecision {
        var decision = RoutingDecision(url: url)

        if let rule = rules.first(where: { $0.matches(url) }) {
            decision.matchedRule = rule.displayName
            decision.requestedProfile = rule.rule.profile
            if let directory = ProfileResolver.resolve(rule.rule.profile, in: profiles) {
                decision.profileDirectory = directory
                return decision
            }
            decision.notes.append("\(rule.displayName) matched, but no Chrome profile is named \"\(rule.rule.profile)\"; using the default profile instead.")
        }

        guard let fallback = ruleSet.defaultProfile, !fallback.isEmpty else {
            return decision
        }
        if decision.matchedRule == nil { decision.requestedProfile = fallback }
        if let directory = ProfileResolver.resolve(fallback, in: profiles) {
            decision.profileDirectory = directory
        } else {
            decision.notes.append("No Chrome profile is named \"\(fallback)\" (defaultProfile); Chrome will use its last-used profile.")
        }
        return decision
    }
}
