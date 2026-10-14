import XCTest
@testable import EarlCore

final class ChromeLauncherTests: XCTestCase {
    private let url = URL(string: "https://example.com/a?b=c&d=e")!

    func testProfileCommand() {
        let command = ChromeLauncher.command(url: url, profileDirectory: "Profile 2")
        XCTAssertEqual(command.executable, "/usr/bin/open")
        XCTAssertEqual(command.arguments, ["-n", "-a", "Google Chrome", "--args", "--profile-directory=Profile 2", "https://example.com/a?b=c&d=e"])
        XCTAssertEqual(
            command.shellString,
            "/usr/bin/open -n -a 'Google Chrome' --args '--profile-directory=Profile 2' 'https://example.com/a?b=c&d=e'"
        )
    }

    func testNoProfileUsesPlainOpen() {
        XCTAssertEqual(
            ChromeLauncher.command(url: url, profileDirectory: nil).arguments,
            ["-a", "Google Chrome", "https://example.com/a?b=c&d=e"]
        )
    }

    func testNewWindowCommand() {
        XCTAssertEqual(
            ChromeLauncher.command(url: nil, profileDirectory: "Default").arguments,
            ["-n", "-a", "Google Chrome", "--args", "--profile-directory=Default"]
        )
        XCTAssertEqual(
            ChromeLauncher.command(url: nil, profileDirectory: nil).arguments,
            ["-n", "-a", "Google Chrome", "--args", "--new-window"]
        )
    }

    func testBrowserOverrides() {
        XCTAssertEqual(
            ChromeLauncher.command(url: url, profileDirectory: "Default", browser: BrowserConfig(application: "Brave Browser")).arguments[1...2],
            ["-a", "Brave Browser"]
        )
        XCTAssertEqual(
            ChromeLauncher.command(url: url, profileDirectory: "Default", browser: BrowserConfig(application: "X", bundleIdentifier: "com.google.Chrome.beta")).arguments[1...2],
            ["-b", "com.google.Chrome.beta"]
        )
        XCTAssertEqual(
            ChromeLauncher.command(url: url, profileDirectory: nil, browser: BrowserConfig(application: "")).arguments[0...1],
            ["-a", "Google Chrome"]
        )
    }

    func testShellQuoting() {
        XCTAssertEqual(LaunchCommand.shellQuote("plain-arg"), "plain-arg")
        XCTAssertEqual(LaunchCommand.shellQuote("it's"), #"'it'\''s'"#)
        XCTAssertEqual(LaunchCommand.shellQuote(""), "''")
    }

    func testAllowedSchemes() {
        XCTAssertTrue(ChromeLauncher.canOpen(URL(string: "HTTPS://example.com")!))
        XCTAssertTrue(ChromeLauncher.canOpen(URL(string: "file:///tmp/a.html")!))
        XCTAssertFalse(ChromeLauncher.canOpen(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(ChromeLauncher.canOpen(URL(string: "mailto:a@b.c")!))
    }

    func testCommandRunnerReportsFailures() {
        let finished = expectation(description: "finished")
        CommandRunner.run(LaunchCommand(executable: "/bin/sh", arguments: ["-c", "echo boom >&2; exit 3"])) { error in
            XCTAssertTrue(String(describing: error ?? "nil" as Any).contains("status 3: boom"))
            finished.fulfill()
        }
        let missing = expectation(description: "missing")
        CommandRunner.run(LaunchCommand(executable: "/nonexistent/binary", arguments: [])) { error in
            XCTAssertNotNil(error)
            missing.fulfill()
        }
        wait(for: [finished, missing], timeout: 10)
    }
}

final class EngineTests: XCTestCase {
    private var directory: URL!
    private var rulesURL: URL { directory.appendingPathComponent("rules.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(ChromeLocalStateTests.fixture.utf8).write(to: directory.appendingPathComponent("Local State"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeRules(_ json: String) throws {
        let localState = directory.appendingPathComponent("Local State").path
        try Data(json.replacingOccurrences(of: "$LOCAL_STATE", with: localState).utf8).write(to: rulesURL)
    }

    func testEndToEndRouting() throws {
        try writeRules("""
        {
          "defaultProfile": "Personal",
          "browser": { "localState": "$LOCAL_STATE" },
          "rules": [ { "name": "Work", "hosts": "*.acme.com", "profile": "jane@acme.com" } ]
        }
        """)
        let engine = Engine(rulesURL: rulesURL)
        XCTAssertTrue(engine.reload())

        let decision = engine.route(URL(string: "https://wiki.acme.com/page")!)
        XCTAssertEqual(decision.profileDirectory, "Profile 2")
        XCTAssertEqual(engine.launchCommand(for: decision).arguments, [
            "-n", "-a", "Google Chrome", "--args", "--profile-directory=Profile 2", "https://wiki.acme.com/page",
        ])
        XCTAssertEqual(engine.route(URL(string: "https://example.org")!).profileDirectory, "Default")
        XCTAssertTrue(engine.diagnostics(profiles: engine.profiles().profiles).isEmpty)
    }

    func testFailedReloadKeepsPreviousRules() throws {
        try writeRules(#"{ "rules": [{ "hosts": "a.com", "profile": "Work" }] }"#)
        let engine = Engine(rulesURL: rulesURL)
        XCTAssertTrue(engine.reload())

        try writeRules("{ broken")
        XCTAssertFalse(engine.reload())
        XCTAssertNotNil(engine.loadError)
        XCTAssertEqual(engine.router.rules.count, 1)

        try writeRules(#"{ "rules": [] }"#)
        XCTAssertTrue(engine.reload())
        XCTAssertNil(engine.loadError)
        XCTAssertEqual(engine.router.rules.count, 0)
    }

    func testMissingLocalStateIsReportedNotFatal() throws {
        try writeRules(#"{ "browser": { "localState": "/nonexistent/Local State" }, "defaultProfile": "Profile 3" }"#)
        let engine = Engine(rulesURL: rulesURL)
        XCTAssertTrue(engine.reload())
        let snapshot = engine.profiles()
        XCTAssertTrue(snapshot.profiles.isEmpty)
        XCTAssertNotNil(snapshot.error)
        XCTAssertEqual(engine.route(URL(string: "https://x.com")!).profileDirectory, "Profile 3")
    }

    func testDiagnosticsIncludeUnknownProfiles() throws {
        try writeRules(#"{ "browser": { "localState": "$LOCAL_STATE" }, "defaultProfile": "Nobody", "rules": [{ "profile": "Work" }] }"#)
        let engine = Engine(rulesURL: rulesURL)
        engine.reload()
        let diagnostics = engine.diagnostics(profiles: engine.profiles().profiles)
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertTrue(diagnostics.contains { $0.contains("\"Nobody\"") })
    }

    func testEnsureRulesFileCreatesStarterOnce() throws {
        let engine = Engine(rulesURL: directory.appendingPathComponent("sub/rules.json"))
        XCTAssertTrue(try engine.ensureRulesFile())
        XCTAssertFalse(try engine.ensureRulesFile())
        XCTAssertTrue(engine.reload())
    }
}

final class FileChangeMonitorTests: XCTestCase {
    func testDetectsCreateModifyReplaceAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rules.json")

        var changes = 0
        let monitor = FileChangeMonitor(url: file) { changes += 1 }
        XCTAssertFalse(monitor.checkNow())

        try Data("{}".utf8).write(to: file)
        XCTAssertTrue(monitor.checkNow())
        XCTAssertFalse(monitor.checkNow())

        try Data("{ }".utf8).write(to: file)
        XCTAssertTrue(monitor.checkNow())

        // Atomic save: new inode, possibly the same size and timestamp.
        try Data("{ }".utf8).write(to: file, options: .atomic)
        XCTAssertTrue(monitor.checkNow())

        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(monitor.checkNow())
        XCTAssertEqual(changes, 4)
    }

    func testTimerFires() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let changed = expectation(description: "changed")
        let monitor = FileChangeMonitor(url: file, interval: 0.1, queue: DispatchQueue(label: "test")) {
            changed.fulfill()
        }
        monitor.start()
        try Data("{}".utf8).write(to: file)
        wait(for: [changed], timeout: 5)
        monitor.stop()
    }
}
