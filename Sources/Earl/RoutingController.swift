import AppKit
import EarlCore
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
    let engine = Engine()
    private(set) var recent: [RoutedLink] = []
    private var monitor: FileChangeMonitor?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.chan.earl", category: "routing")

    /// Called on the main queue whenever rules are reloaded or a link is routed.
    var onChange: (() -> Void)?

    var rulesURL: URL { engine.rulesURL }

    func start() {
        do {
            if try engine.ensureRulesFile() {
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

    private func run(_ command: LaunchCommand, context: String) {
        CommandRunner.run(command) { [log] error in
            guard let error else { return }
            log.error("\(String(describing: error), privacy: .public)")
            let message = String(describing: error)
            Task { @MainActor in
                Alerts.show(
                    title: "Earl couldn't open Chrome",
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
}
