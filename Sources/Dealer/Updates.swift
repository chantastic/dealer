import AppKit
import Sparkle

/// Sparkle 2 auto-updates. Updates are verified with the EdDSA key in Info.plist
/// (`SUPublicEDKey`), so they work without an Apple Developer ID.
///
/// Builds without an `SUPublicEDKey` or `SUFeedURL` (or running outside an app bundle) don't
/// start Sparkle at all: Sparkle refuses to install unsigned updates, so there's nothing useful
/// it could do, and the menu simply omits "Check for Updates…".
@MainActor
final class Updates {
    private let controller: SPUStandardUpdaterController?

    init() {
        controller = Self.isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    static var isConfigured: Bool {
        let info = Bundle.main
        func value(_ key: String) -> String {
            (info.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        return info.bundleIdentifier != nil && !value("SUPublicEDKey").isEmpty && !value("SUFeedURL").isEmpty
    }

    var isAvailable: Bool { controller != nil }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
