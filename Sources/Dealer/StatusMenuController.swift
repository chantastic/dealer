import AppKit
import DealerCore

/// The menu-bar item. The menu is rebuilt each time it opens so profiles, rule status,
/// and the default-browser check are always current.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let router: RoutingController
    private let updates: Updates
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(router: RoutingController, updates: Updates) {
        self.router = router
        self.updates = updates
        super.init()

        if let button = statusItem.button {
            // MenuBarIconTemplate{,@2x}.png ship in Contents/Resources; running outside the
            // app bundle (e.g. `swift run Dealer`) has no resources, so fall back to a title.
            if let image = NSImage(named: "MenuBarIconTemplate") {
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                image.accessibilityDescription = "Dealer"
                button.image = image
            } else {
                button.title = "Dealer"
            }
            button.toolTip = "Dealer"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        router.onChange = { [weak self] in
            self?.updateButton()
        }
        updateButton()
        rebuild()
    }

    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func updateButton() {
        statusItem.button?.appearsDisabled = router.engine.loadError != nil && !router.engine.hasLoadedRules
    }

    // MARK: - Building

    private func rebuild() {
        menu.removeAllItems()
        let engine = router.engine
        let snapshot = router.profiles()

        menu.addItem(header(Self.versionTitle))
        menu.addItem(statusLine(engine: engine, profiles: snapshot.profiles))
        if let error = engine.loadError {
            menu.addItem(disabled(Self.truncate(String(describing: error), to: 90), small: true))
        }

        if DefaultBrowser.isDealerDefault {
            menu.addItem(disabled("Dealer is the default browser"))
        } else {
            menu.addItem(disabled("Default browser: \(DefaultBrowser.currentHandlerName)"))
            menu.addItem(item("Set Dealer as Default Browser…", action: #selector(makeDefault)))
        }

        menu.addItem(.separator())
        menu.addItem(header("Chrome Profiles"))
        if let error = snapshot.error {
            menu.addItem(disabled("Couldn't read Local State"))
            menu.addItem(disabled("  " + error, small: true))
        } else if snapshot.profiles.isEmpty {
            menu.addItem(disabled("No profiles found"))
        }
        let fallback = engine.ruleSet.defaultProfile.flatMap { ProfileResolver.resolve($0, in: snapshot.profiles) }
        for profile in snapshot.profiles {
            var title = profile.label
            if profile.directory == fallback { title += " — default" }
            let open = item(title, action: #selector(openProfile(_:)))
            open.representedObject = profile.directory
            open.toolTip = [profile.email, "Click to open a new window. Hold ⌥ to copy the directory name."]
                .compactMap { $0 }
                .joined(separator: "\n")
            menu.addItem(open)

            let copy = item("Copy “\(profile.directory)”", action: #selector(copyDirectory(_:)))
            copy.representedObject = profile.directory
            copy.isAlternate = true
            copy.keyEquivalentModifierMask = .option
            menu.addItem(copy)
        }
        let manage = item("Manage Profiles…", action: #selector(manageProfiles))
        manage.toolTip = "Open Chrome's profile picker to add, edit, or remove profiles."
        menu.addItem(manage)

        if !router.recent.isEmpty {
            menu.addItem(.separator())
            let recentItem = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for link in router.recent {
                let title = "\(Self.truncate(link.url.absoluteString, to: 60))  →  \(link.profileLabel)"
                let entry = item(title, action: #selector(copyLink(_:)))
                entry.representedObject = link.url.absoluteString
                entry.toolTip = "\(link.url.absoluteString)\nRule: \(link.ruleName ?? "default")\nClick to copy."
                submenu.addItem(entry)
            }
            recentItem.submenu = submenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Rules File", action: #selector(openRules), key: "o"))
        menu.addItem(item("Reveal Rules in Finder", action: #selector(revealRules)))
        menu.addItem(item("Reload Rules", action: #selector(reloadRules), key: "r"))
        menu.addItem(.separator())
        if updates.isAvailable {
            let check = item("Check for Updates…", action: #selector(checkForUpdates))
            check.isEnabled = updates.canCheckForUpdates
            menu.addItem(check)
        }
        menu.addItem(item("Quit Dealer", action: #selector(quit), key: "q"))
    }

    private func statusLine(engine: Engine, profiles: [ChromeProfile]) -> NSMenuItem {
        if let error = engine.loadError {
            let prefix = engine.hasLoadedRules ? "Reload failed — using previous rules" : "Rules not loaded"
            let line = disabled(prefix)
            line.toolTip = String(describing: error)
            return line
        }
        let count = engine.router.rules.count
        let warnings = engine.diagnostics(profiles: profiles)
        var title = count == 1 ? "1 rule active" : "\(count) rules active"
        if !warnings.isEmpty {
            title += " · \(warnings.count) warning" + (warnings.count == 1 ? "" : "s")
        }
        let line = disabled(title)
        line.toolTip = warnings.isEmpty ? router.rulesURL.path : warnings.joined(separator: "\n")
        return line
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        return disabled(title)
    }

    private func disabled(_ title: String, small: Bool = false) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        if small {
            menuItem.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        return menuItem
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private static var versionTitle: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Dealer"
        }
        return "Dealer \(version)"
    }

    private static func truncate(_ text: String, to length: Int) -> String {
        text.count <= length ? text : String(text.prefix(length - 1)) + "…"
    }

    // MARK: - Actions

    @objc private func makeDefault() {
        Task {
            do {
                try await DefaultBrowser.makeDealerDefault()
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
                Alerts.show(title: "Couldn't set Dealer as the default browser", message: error.localizedDescription)
            }
        }
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? String else { return }
        router.openNewWindow(profileDirectory: directory)
    }

    @objc private func manageProfiles() {
        router.openProfileManager()
    }

    @objc private func copyDirectory(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? String else { return }
        copy(directory)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? String else { return }
        copy(link)
    }

    @objc private func openRules() {
        do {
            if try router.engine.ensureRulesFile() { router.reload() }
        } catch {
            Alerts.show(title: "Couldn't create the rules file", message: error.localizedDescription)
            return
        }
        router.openRulesForEditing()
    }

    @objc private func revealRules() {
        _ = try? router.engine.ensureRulesFile()
        NSWorkspace.shared.activateFileViewerSelecting([router.rulesURL])
    }

    @objc private func reloadRules() {
        router.reload()
        if let error = router.engine.loadError {
            Alerts.show(title: "Couldn't load rules", message: String(describing: error))
        }
    }

    @objc private func checkForUpdates() {
        updates.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
