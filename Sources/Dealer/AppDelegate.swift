import AppKit
import DealerCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    private let router = RoutingController()
    private var menuController: StatusMenuController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Load rules before Launch Services delivers the URL that launched us.
        router.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = StatusMenuController(router: router, updates: Updates())
    }

    /// Receives http/https URLs (`kAEGetURL` Apple Events) and HTML files opened with Dealer.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            router.open(url)
        }
    }

    /// Double-clicking Dealer.app while it's running pops the menu so it's discoverable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuController?.showMenu()
        return false
    }
}
