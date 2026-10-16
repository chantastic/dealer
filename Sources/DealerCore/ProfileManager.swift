import Foundation

/// Opens Chrome's profile picker (`chrome://profile-picker`, the "Manage Chrome profiles" screen
/// that lists every profile).
///
/// Chrome refuses `chrome://` URLs from outside: command-line URLs are limited to web schemes
/// (plus exactly `chrome://settings/resetProfileSettings`), and URLs from the `open` Apple Event
/// to http(s). Navigating a tab through Chrome's AppleScript `set URL` is browser-initiated and
/// allowed, so this drives Chrome via `osascript`. macOS asks the user once to allow Dealer
/// (or the terminal running `deal`) to control Chrome.
public enum ProfileManagerLauncher {
    public static let pickerURL = "chrome://profile-picker"

    /// AppleScript error number for "Not authorized to send Apple events".
    public static let automationDeniedCode = "-1743"

    public static func command(browser: BrowserConfig? = nil) -> LaunchCommand {
        let lines = [
            "tell \(applicationSpecifier(for: browser))",
            "activate",
            "set pickerWindow to make new window",
            "set URL of active tab of pickerWindow to \(appleScriptString(pickerURL))",
            "end tell",
        ]
        return LaunchCommand(executable: "/usr/bin/osascript", arguments: lines.flatMap { ["-e", $0] })
    }

    /// Whether a failed `command` failed because the user hasn't allowed Automation.
    public static func isAutomationDenied(_ error: Error) -> Bool {
        String(describing: error).contains("(\(automationDeniedCode))")
    }

    /// `application id "…"` for a bundle ID, otherwise `application "…"` by name. App paths are
    /// reduced to their name because AppleScript resolves `tell` targets by name or bundle ID.
    static func applicationSpecifier(for browser: BrowserConfig?) -> String {
        if let bundleIdentifier = browser?.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "application id \(appleScriptString(bundleIdentifier))"
        }
        var name = browser?.application.flatMap { $0.isEmpty ? nil : $0 } ?? ChromeLauncher.defaultApplication
        if name.contains("/") {
            name = URL(fileURLWithPath: Paths.expandTilde(name)).lastPathComponent
        }
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        return "application \(appleScriptString(name))"
    }

    static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
