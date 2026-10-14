import Foundation

public struct ProfileSnapshot {
    public var profiles: [ChromeProfile]
    public var localStatePath: URL
    /// Set when `Local State` couldn't be read. Rules then treat profile references as directory names.
    public var error: String?
}

/// Owns the current rules and turns incoming URLs into launch commands.
/// Shared by the menu-bar app and `earlctl` so both route identically.
public final class Engine {
    public let rulesURL: URL
    private let home: URL
    public private(set) var router: Router
    /// The error from the most recent load attempt, or `nil` if it succeeded.
    /// When a reload fails the previously loaded rules stay active.
    public private(set) var loadError: RulesError?
    /// Whether `router` came from the rules file (as opposed to the empty initial state).
    public private(set) var hasLoadedRules = false

    public init(rulesURL: URL = Paths.rulesFile(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.rulesURL = rulesURL
        self.home = home
        self.router = Router(ruleSet: RuleSet())
    }

    public var ruleSet: RuleSet { router.ruleSet }

    @discardableResult
    public func reload() -> Bool {
        do {
            router = Router(ruleSet: try RulesLoader.load(from: rulesURL))
            loadError = nil
            hasLoadedRules = true
            return true
        } catch let error as RulesError {
            loadError = error
        } catch {
            loadError = .invalid(reason: error.localizedDescription)
        }
        return false
    }

    /// Creates a starter rules file (listing detected profiles) if none exists.
    @discardableResult
    public func ensureRulesFile() throws -> Bool {
        try RulesLoader.writeStarterIfMissing(at: rulesURL, profiles: profiles().profiles)
    }

    public func profiles(localStateOverride: URL? = nil) -> ProfileSnapshot {
        let path = localStateOverride ?? ChromeLocalState.path(for: ruleSet.browser, home: home)
        do {
            return ProfileSnapshot(profiles: try ChromeLocalState.loadProfiles(at: path), localStatePath: path)
        } catch {
            return ProfileSnapshot(profiles: [], localStatePath: path, error: String(describing: error))
        }
    }

    public func route(_ url: URL, profiles: [ChromeProfile]? = nil) -> RoutingDecision {
        router.route(url, profiles: profiles ?? self.profiles().profiles)
    }

    public func launchCommand(for decision: RoutingDecision) -> LaunchCommand {
        ChromeLauncher.command(url: decision.url, profileDirectory: decision.profileDirectory, browser: ruleSet.browser)
    }

    public func newWindowCommand(profileDirectory: String) -> LaunchCommand {
        ChromeLauncher.command(url: nil, profileDirectory: profileDirectory, browser: ruleSet.browser)
    }

    /// Everything worth warning the user about: compile issues plus profile names that don't exist.
    public func diagnostics(profiles: [ChromeProfile]) -> [String] {
        var messages = router.issues
        for reference in router.unresolvedProfiles(in: profiles) {
            messages.append("No Chrome profile matches \"\(reference)\".")
        }
        return messages
    }
}
