import Foundation

/// How to open the rules file for editing, parsed from the rules file's `editor` setting.
///
/// The rules file is never opened with a plain `open <file>`, which would use whatever app
/// owns `.json` files (often not an editor at all).
public enum EditorSetting: Equatable, Sendable {
    /// No setting: the handler for `public.plain-text` (`open -t`).
    case defaultTextEditor
    /// Reverse-DNS bundle ID such as `com.microsoft.VSCode` (`open -b`).
    case bundleIdentifier(String)
    /// App name such as `Visual Studio Code`, or a path to an `.app` (`open -a`).
    case application(String)

    /// A value containing dots but no spaces or slashes, and not ending in `.app`, is a bundle ID.
    /// Anything else non-empty is an app name or path.
    public init(_ setting: String?) {
        let value = setting?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            self = .defaultTextEditor
        } else if Self.looksLikeBundleIdentifier(value) {
            self = .bundleIdentifier(value)
        } else {
            self = .application(Paths.expandTilde(value))
        }
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        guard !value.lowercased().hasSuffix(".app") else { return false }
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

public enum EditorLauncher {
    public static func command(opening file: URL, with editor: EditorSetting) -> LaunchCommand {
        let selector: [String]
        switch editor {
        case .defaultTextEditor:
            selector = ["-t"]
        case .bundleIdentifier(let identifier):
            selector = ["-b", identifier]
        case .application(let application):
            selector = ["-a", application]
        }
        return LaunchCommand(executable: "/usr/bin/open", arguments: selector + [file.path])
    }
}
