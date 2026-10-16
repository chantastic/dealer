import XCTest
@testable import DealerCore

final class ProfileManagerLauncherTests: XCTestCase {
    private func script(_ browser: BrowserConfig?) -> [String] {
        let command = ProfileManagerLauncher.command(browser: browser)
        XCTAssertEqual(command.executable, "/usr/bin/osascript")
        let pairs = stride(from: 0, to: command.arguments.count, by: 2).map {
            (command.arguments[$0], command.arguments[$0 + 1])
        }
        XCTAssertTrue(pairs.allSatisfy { $0.0 == "-e" }, "every line is passed with -e")
        return pairs.map(\.1)
    }

    func testDefaultTargetsGoogleChromeProfilePicker() {
        XCTAssertEqual(script(nil), [
            #"tell application "Google Chrome""#,
            "activate",
            "set pickerWindow to make new window",
            #"set URL of active tab of pickerWindow to "chrome://profile-picker""#,
            "end tell",
        ])
    }

    func testRespectsConfiguredBrowser() {
        XCTAssertEqual(script(BrowserConfig(application: "Brave Browser")).first, #"tell application "Brave Browser""#)
        XCTAssertEqual(
            script(BrowserConfig(application: "Ignored", bundleIdentifier: "com.google.Chrome.beta")).first,
            #"tell application id "com.google.Chrome.beta""#
        )
        XCTAssertEqual(
            script(BrowserConfig(application: "/Applications/Google Chrome Canary.app")).first,
            #"tell application "Google Chrome Canary""#
        )
        XCTAssertEqual(script(BrowserConfig(application: "Chromium.app")).first, #"tell application "Chromium""#)
        XCTAssertEqual(script(BrowserConfig(application: "", bundleIdentifier: "")).first, #"tell application "Google Chrome""#)
    }

    func testAppleScriptStringsAreEscaped() {
        XCTAssertEqual(ProfileManagerLauncher.appleScriptString(#"a "b" \c"#), #""a \"b\" \\c""#)
        XCTAssertEqual(script(BrowserConfig(application: #"Odd "Name""#)).first, #"tell application "Odd \"Name\"""#)
    }

    func testAutomationDeniedDetection() {
        let denied = CommandRunnerError.failed(
            command: "osascript",
            status: 1,
            stderr: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"
        )
        let missing = CommandRunnerError.failed(
            command: "osascript",
            status: 1,
            stderr: "syntax error: Can’t get application \"Nope\". (-2700)"
        )
        XCTAssertTrue(ProfileManagerLauncher.isAutomationDenied(denied))
        XCTAssertFalse(ProfileManagerLauncher.isAutomationDenied(missing))
    }

    func testEngineUsesBrowserFromRules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = directory.appendingPathComponent("rules.json")
        try Data(#"{ "browser": { "bundleIdentifier": "com.brave.Browser" } }"#.utf8).write(to: rules)

        let engine = Engine(rulesURL: rules)
        XCTAssertEqual(engine.manageProfilesCommand().arguments[1], #"tell application "Google Chrome""#, "before loading")
        XCTAssertTrue(engine.reload())
        XCTAssertEqual(engine.manageProfilesCommand().arguments[1], #"tell application id "com.brave.Browser""#)
    }
}
