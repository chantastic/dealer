import AppKit
import DealerCore
import os

struct RoutedLink {
    var date: Date
    var url: URL
    var profileLabel: String
    var ruleName: String?
}

/// App-side wrapper around `Engine`: watches the rules file, launches Chrome, and keeps a
/// short history for the menu.
final class RoutingController {
    let engine = Engine(legacyRulesURL: Paths.legacyRulesFile())
    private(set) var recent: [RoutedLink] = []
    private var monitor: FileChangeMonitor?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.chan.dealer", category: "routing")

    /// Called on the main queue whenever rules are reloaded or a link is routed.
    var onChange: (() -> Void)?

    var rulesURL: URL { engine.rulesURL }

    func start() {
        do {
            if try engine.migrateLegacyRulesIfNeeded() {
                log.notice("Copied rules from \(self.engine.legacyRulesURL?.path ?? "", privacy: .public) to \(self.rulesURL.path, privacy: .public)")
            } else if try engine.ensureRulesFile() {
                log.info("Created starter rules at \(self.rulesURL.path, privacy: .public)")
            }
        } catch {
            log.error("Couldn't create rules file: \(error.localizedDescription, privacy: .public)")
        }
        reload()

        let monitor = FileChangeMonitor(url: rulesURL) { [weak self] in
            self?.reload()
        }
        monitor.start()
        self.monitor = monitor
    }

    func reload() {
        if engine.reload() {
            log.info("Loaded \(self.engine.router.rules.count) rule(s) from \(self.rulesURL.path, privacy: .public)")
        } else if let error = engine.loadError {
            log.error("\(String(describing: error), privacy: .public)")
        }
        onChange?()
    }

    func profiles() -> ProfileSnapshot {
        engine.profiles()
    }

    func open(_ url: URL) {
        guard ChromeLauncher.canOpen(url) else {
            log.error("Refusing to open URL with scheme \(url.scheme ?? "(none)", privacy: .public)")
            return
        }

        let profiles = engine.profiles().profiles
        let decision = engine.route(url, profiles: profiles)
        let command = engine.launchCommand(for: decision)
        for note in decision.notes {
            log.notice("\(note, privacy: .public)")
        }
        log.info("\(url.absoluteString, privacy: .private) → \(decision.profileDirectory ?? "(last used)", privacy: .public) via \(decision.matchedRule ?? "default", privacy: .public)")

        let label = decision.profileDirectory.map { directory in
            profiles.first { $0.directory == directory }?.label ?? directory
        } ?? "Last-used profile"
        recent.insert(RoutedLink(date: Date(), url: url, profileLabel: label, ruleName: decision.matchedRule), at: 0)
        if recent.count > 10 { recent.removeLast(recent.count - 10) }
        onChange?()

        run(command, context: url.absoluteString)
    }

    func openNewWindow(profileDirectory: String) {
        run(engine.newWindowCommand(profileDirectory: profileDirectory), context: profileDirectory)
    }

    /// Opens the rules file in the configured `editor`, or the default text editor. If the
    /// configured editor can't be launched, falls back to the default text editor and says why.
    func openRulesForEditing() {
        let setting = engine.editorSetting
        let fallback = engine.editRulesCommand(with: .defaultTextEditor)
        CommandRunner.run(engine.editRulesCommand()) { [log] error in
            guard let error else { return }
            let message = String(describing: error)
            log.error("\(message, privacy: .public)")
            guard setting != .defaultTextEditor else {
                Task { @MainActor in
                    Alerts.show(title: "Couldn't open the rules file", message: message)
                }
                return
            }
            CommandRunner.run(fallback) { fallbackError in
                let detail = fallbackError.map { "\n\nThe default text editor also failed: \($0)" }
                    ?? "\n\nOpened it in the default text editor instead."
                Task { @MainActor in
                    Alerts.show(
                        title: "Couldn't open the rules file with the configured editor",
                        message: "Check the \"editor\" setting in rules.json.\n\n\(message)\(detail)"
                    )
                }
            }
        }
    }

    /// Shows Chrome's profile picker, which lists every profile and lets the user add, edit,
    /// or remove them. Needs macOS Automation permission for Dealer to control the browser.
    func openProfileManager() {
        CommandRunner.run(engine.manageProfilesCommand()) { [log] error in
            guard let error else { return }
            let message = String(describing: error)
            log.error("\(message, privacy: .public)")
            let denied = ProfileManagerLauncher.isAutomationDenied(error)
            Task { @MainActor in
                if denied {
                    Alerts.showAutomationDenied()
                } else {
                    Alerts.show(title: "Couldn't open Chrome's profile manager", message: message)
                }
            }
        }
    }

    private func run(_ command: LaunchCommand, context: String) {
        CommandRunner.run(command) { [log] error in
            guard let error else { return }
            log.error("\(String(describing: error), privacy: .public)")
            let message = String(describing: error)
            Task { @MainActor in
                Alerts.show(
                    title: "Dealer couldn't open Chrome",
                    message: "\(message)\n\n\(context)",
                    copyText: context
                )
            }
        }
    }
}

@MainActor
enum Alerts {
    static func show(title: String, message: String, copyText: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if copyText != nil { alert.addButton(withTitle: "Copy Link") }
        if alert.runModal() == .alertSecondButtonReturn, let copyText {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
        }
    }

    static func showAutomationDenied() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Dealer isn't allowed to control Chrome"
        alert.informativeText = """
        Chrome only opens its profile manager when asked through AppleScript. \
        Turn on Google Chrome under Dealer in System Settings → Privacy & Security → Automation, \
        then choose Manage Profiles… again.
        """
        alert.addButton(withTitle: "Open Automation Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(settings)
        }
    }
}
