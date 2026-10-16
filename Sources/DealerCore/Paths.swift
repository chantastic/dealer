import Foundation

public enum Paths {
    public static func expandTilde(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }

    /// Where Dealer looks for its rules, in priority order:
    /// `$DEALER_RULES`, `$XDG_CONFIG_HOME/dealer/rules.json`, then `~/.config/dealer/rules.json`.
    ///
    /// Apps launched from Finder or by Launch Services don't inherit shell environment
    /// variables, so in practice the menu-bar app uses `~/.config/dealer/rules.json`.
    public static func rulesFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let explicit = environment["DEALER_RULES"], !explicit.isEmpty {
            return URL(fileURLWithPath: expandTilde(explicit, home: home))
        }
        return configHome(environment: environment, home: home)
            .appendingPathComponent("dealer", isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    /// Rules location used before the project was renamed from Earl to Dealer.
    /// Only read by the one-time migration in `Engine.migrateLegacyRulesIfNeeded()`.
    public static func legacyRulesFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        configHome(environment: environment, home: home)
            .appendingPathComponent("earl", isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    private static func configHome(environment: [String: String], home: URL) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: expandTilde(xdg, home: home), isDirectory: true)
        }
        return home.appendingPathComponent(".config", isDirectory: true)
    }
}
