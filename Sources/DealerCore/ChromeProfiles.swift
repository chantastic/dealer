import Foundation

/// A Chrome profile as described by the browser's `Local State` file.
public struct ChromeProfile: Hashable, Sendable {
    /// Directory name inside the user data dir, e.g. `Default` or `Profile 2`.
    /// This is what `--profile-directory` expects.
    public var directory: String
    /// The name shown in Chrome's profile picker.
    public var name: String
    /// Signed-in account email, if any.
    public var email: String?
    /// Signed-in account's full name, if any.
    public var gaiaName: String?

    public init(directory: String, name: String, email: String? = nil, gaiaName: String? = nil) {
        self.directory = directory
        self.name = name
        self.email = email
        self.gaiaName = gaiaName
    }

    /// `Work (Profile 2)` style label for menus and CLI output.
    public var label: String {
        name == directory ? name : "\(name) (\(directory))"
    }
}

public enum ChromeLocalStateError: Error, CustomStringConvertible {
    case unreadable(path: String, underlying: Error)
    case malformed(String)

    public var description: String {
        switch self {
        case .unreadable(let path, let underlying):
            return "Couldn't read \(path): \(underlying.localizedDescription)"
        case .malformed(let reason):
            return "Chrome's Local State file is malformed: \(reason)"
        }
    }
}

public enum ChromeLocalState {
    /// Chrome's `Local State` on macOS for the given home directory.
    public static func defaultPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
            .appendingPathComponent("Local State")
    }

    /// Resolves the `Local State` location from the rules' browser config, falling back to Chrome's.
    public static func path(for browser: BrowserConfig?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        guard let configured = browser?.localState, !configured.isEmpty else {
            return defaultPath(home: home)
        }
        return URL(fileURLWithPath: Paths.expandTilde(configured, home: home))
    }

    public static func loadProfiles(at url: URL) throws -> [ChromeProfile] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChromeLocalStateError.unreadable(path: url.path, underlying: error)
        }
        return try parseProfiles(from: data)
    }

    /// Extracts profiles from `profile.info_cache`, ordered like Chrome's profile picker
    /// (`profile.profiles_order`) when available.
    public static func parseProfiles(from data: Data) throws -> [ChromeProfile] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ChromeLocalStateError.malformed("not valid JSON")
        }
        guard let object = root as? [String: Any] else {
            throw ChromeLocalStateError.malformed("top level is not an object")
        }
        guard let profileSection = object["profile"] as? [String: Any],
              let infoCache = profileSection["info_cache"] as? [String: Any]
        else {
            return []
        }

        var profiles: [String: ChromeProfile] = [:]
        for (directory, value) in infoCache {
            guard let info = value as? [String: Any] else { continue }
            if isInternalProfile(directory: directory, info: info) { continue }
            let name = nonEmpty(info["name"] as? String)
                ?? nonEmpty(info["shortcut_name"] as? String)
                ?? directory
            profiles[directory] = ChromeProfile(
                directory: directory,
                name: name,
                email: nonEmpty(info["user_name"] as? String),
                gaiaName: nonEmpty(info["gaia_name"] as? String)
            )
        }

        var ordered: [ChromeProfile] = []
        if let order = profileSection["profiles_order"] as? [String] {
            for directory in order {
                if let profile = profiles.removeValue(forKey: directory) {
                    ordered.append(profile)
                }
            }
        }
        ordered += profiles.values.sorted { lhs, rhs in
            directorySortKey(lhs.directory, rhs.directory)
        }
        return ordered
    }

    private static func isInternalProfile(directory: String, info: [String: Any]) -> Bool {
        if directory == "System Profile" || directory == "Guest Profile" { return true }
        if info["is_ephemeral"] as? Bool == true { return true }
        return false
    }

    /// `Default` first, then `Profile 1`, `Profile 2`, …, `Profile 10` in numeric order.
    private static func directorySortKey(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "Default" { return rhs != "Default" }
        if rhs == "Default" { return false }
        return lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}

public enum ProfileResolver {
    /// Maps a user-supplied profile reference to a `--profile-directory` value.
    ///
    /// Resolution order: exact directory, then (case-insensitively) directory, display name,
    /// account email, and account full name. If no profiles are known at all (for example
    /// `Local State` couldn't be read), the reference is assumed to be a directory name.
    /// Returns `nil` when profiles are known but none match.
    public static func resolve(_ reference: String, in profiles: [ChromeProfile]) -> String? {
        let wanted = reference.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        guard !profiles.isEmpty else { return wanted }

        if let exact = profiles.first(where: { $0.directory == wanted }) {
            return exact.directory
        }
        let candidates: [(ChromeProfile) -> String?] = [
            { $0.directory },
            { $0.name },
            { $0.email },
            { $0.gaiaName },
        ]
        for field in candidates {
            if let match = profiles.first(where: { field($0)?.caseInsensitiveCompare(wanted) == .orderedSame }) {
                return match.directory
            }
        }
        return nil
    }
}
