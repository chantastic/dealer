import Foundation

public enum Paths {
    public static func expandTilde(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }

    /// Where Earl looks for its rules, in priority order:
    /// `$EARL_RULES`, `$XDG_CONFIG_HOME/earl/rules.json`, then `~/.config/earl/rules.json`.
    ///
    /// Apps launched from Finder or by Launch Services don't inherit shell environment
    /// variables, so in practice the menu-bar app uses `~/.config/earl/rules.json`.
    public static func rulesFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let explicit = environment["EARL_RULES"], !explicit.isEmpty {
            return URL(fileURLWithPath: expandTilde(explicit, home: home))
        }
        let configHome: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configHome = URL(fileURLWithPath: expandTilde(xdg, home: home), isDirectory: true)
        } else {
            configHome = home.appendingPathComponent(".config", isDirectory: true)
        }
        return configHome
            .appendingPathComponent("earl", isDirectory: true)
            .appendingPathComponent("rules.json")
    }
}
