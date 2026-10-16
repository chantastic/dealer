import AppKit

@MainActor
enum DefaultBrowser {
    private static let probe = URL(string: "https://example.com")!

    /// The app currently registered for https links.
    static var currentHandler: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    static var currentHandlerName: String {
        guard let handler = currentHandler else { return "none" }
        return FileManager.default.displayName(atPath: handler.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    static var isDealerDefault: Bool {
        guard let handler = currentHandler, let ours = Bundle.main.bundleIdentifier else { return false }
        return Bundle(url: handler)?.bundleIdentifier == ours
    }

    /// Asks macOS to make Dealer the handler for http and https. macOS shows its own
    /// confirmation dialog and throws if the user declines.
    static func makeDealerDefault() async throws {
        guard Bundle.main.bundleIdentifier != nil else {
            throw NSError(domain: "Dealer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Dealer must be run from Dealer.app (see `make app`) to become the default browser.",
            ])
        }
        let appURL = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
    }
}
