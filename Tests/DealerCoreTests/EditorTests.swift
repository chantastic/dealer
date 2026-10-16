import XCTest
@testable import DealerCore

final class EditorSettingTests: XCTestCase {
    func testUnsetOrBlankUsesDefaultTextEditor() {
        XCTAssertEqual(EditorSetting(nil), .defaultTextEditor)
        XCTAssertEqual(EditorSetting(""), .defaultTextEditor)
        XCTAssertEqual(EditorSetting("  \n"), .defaultTextEditor)
    }

    func testBundleIdentifiers() {
        XCTAssertEqual(EditorSetting("com.microsoft.VSCode"), .bundleIdentifier("com.microsoft.VSCode"))
        XCTAssertEqual(EditorSetting(" com.barebones.bbedit "), .bundleIdentifier("com.barebones.bbedit"))
        XCTAssertEqual(EditorSetting("dev.zed.Zed-Preview"), .bundleIdentifier("dev.zed.Zed-Preview"))
    }

    func testApplicationNamesAndPaths() {
        XCTAssertEqual(EditorSetting("Visual Studio Code"), .application("Visual Studio Code"))
        XCTAssertEqual(EditorSetting("TextEdit"), .application("TextEdit"))
        XCTAssertEqual(EditorSetting("Code.app"), .application("Code.app"))
        XCTAssertEqual(EditorSetting("/Applications/BBEdit.app"), .application("/Applications/BBEdit.app"))
        XCTAssertEqual(EditorSetting("Sublime Text.app"), .application("Sublime Text.app"))
        XCTAssertEqual(EditorSetting("com..broken"), .application("com..broken"))
        XCTAssertEqual(EditorSetting("v1.2 Editor"), .application("v1.2 Editor"))
    }

    func testTildePathsAreExpanded() {
        guard case .application(let path) = EditorSetting("~/Applications/Zed.app") else {
            return XCTFail("expected an application path")
        }
        XCTAssertFalse(path.hasPrefix("~"))
        XCTAssertTrue(path.hasSuffix("/Applications/Zed.app"))
    }
}

final class EditorLauncherTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/Users/jane/.config/dealer/rules.json")

    func testCommandsNeverUsePlainOpen() {
        XCTAssertEqual(
            EditorLauncher.command(opening: file, with: .defaultTextEditor).arguments,
            ["-t", "/Users/jane/.config/dealer/rules.json"]
        )
        XCTAssertEqual(
            EditorLauncher.command(opening: file, with: .bundleIdentifier("com.microsoft.VSCode")).arguments,
            ["-b", "com.microsoft.VSCode", "/Users/jane/.config/dealer/rules.json"]
        )
        let named = EditorLauncher.command(opening: file, with: .application("Visual Studio Code"))
        XCTAssertEqual(named.executable, "/usr/bin/open")
        XCTAssertEqual(named.arguments, ["-a", "Visual Studio Code", "/Users/jane/.config/dealer/rules.json"])
        XCTAssertEqual(named.shellString, "/usr/bin/open -a 'Visual Studio Code' /Users/jane/.config/dealer/rules.json")
    }

    func testEngineUsesEditorFromRules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = directory.appendingPathComponent("rules.json")
        let engine = Engine(rulesURL: rules)

        XCTAssertEqual(engine.editRulesCommand().arguments, ["-t", rules.path], "no rules loaded yet")

        try Data(#"{ "editor": "com.microsoft.VSCode" }"#.utf8).write(to: rules)
        XCTAssertTrue(engine.reload())
        XCTAssertEqual(engine.editorSetting, .bundleIdentifier("com.microsoft.VSCode"))
        XCTAssertEqual(engine.editRulesCommand().arguments, ["-b", "com.microsoft.VSCode", rules.path])
        XCTAssertEqual(engine.editRulesCommand(with: .defaultTextEditor).arguments, ["-t", rules.path])

        try Data("{ broken".utf8).write(to: rules)
        XCTAssertFalse(engine.reload())
        XCTAssertEqual(engine.editorSetting, .bundleIdentifier("com.microsoft.VSCode"), "keeps the last good editor")
    }

    func testEditorDecodingAndStarterTemplate() throws {
        XCTAssertEqual(try RulesLoader.decode(Data(#"{ "editor": "Visual Studio Code" }"#.utf8)).editor, "Visual Studio Code")
        XCTAssertNil(try RulesLoader.decode(Data("{}".utf8)).editor)

        let template = RulesLoader.starterTemplate(profiles: [])
        XCTAssertTrue(template.contains(#"// "editor": "Visual Studio Code","#))
        XCTAssertNil(try RulesLoader.decode(Data(template.utf8)).editor, "the example stays commented out")
    }
}
