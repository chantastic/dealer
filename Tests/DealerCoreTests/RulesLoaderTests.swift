import XCTest
@testable import DealerCore

final class RulesLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDecodesFullFile() throws {
        let rules = try RulesLoader.decode(Data("""
        {
          "version": 1,
          "defaultProfile": "Personal",
          "browser": { "application": "Google Chrome Beta", "localState": "~/x/Local State" },
          "rules": [
            { "name": "Work", "hosts": ["github.com"], "urls": "*/acme/*", "regex": "^https://x", "profile": "Work", "enabled": false }
          ]
        }
        """.utf8))
        XCTAssertEqual(rules.defaultProfile, "Personal")
        XCTAssertEqual(rules.browser?.application, "Google Chrome Beta")
        XCTAssertEqual(rules.rules, [
            Rule(name: "Work", enabled: false, hosts: ["github.com"], urls: ["*/acme/*"], regex: ["^https://x"], profile: "Work"),
        ])
    }

    func testMinimalFile() throws {
        XCTAssertEqual(try RulesLoader.decode(Data("{}".utf8)), RuleSet(version: nil))
    }

    func testCommentsAndTrailingCommas() throws {
        let rules = try RulesLoader.decode(Data("""
        // leading comment
        {
          /* block
             comment */
          "defaultProfile": "http://not-a-comment//really", // trailing
          "rules": [
            { "hosts": ["a.com", "b.com",], "profile": "W/*x*/", },
          ],
        }
        """.utf8))
        XCTAssertEqual(rules.defaultProfile, "http://not-a-comment//really")
        XCTAssertEqual(rules.rules.first?.hosts, ["a.com", "b.com"])
        XCTAssertEqual(rules.rules.first?.profile, "W/*x*/")
    }

    func testJSONCPreservesEscapedQuotesAndCommasInStrings() {
        let input = #"{"a": "say \"hi\", // ok", "b": ",]"}"#
        XCTAssertEqual(JSONC.strip(input), input)
    }

    func testJSONCKeepsLineNumbers() {
        let input = "{\n/* a\nb */\n\"x\": 1 // c\n}"
        XCTAssertEqual(JSONC.strip(input).filter { $0 == "\n" }.count, 4)
    }

    func testFriendlyErrors() {
        func reason(_ json: String) -> String {
            do {
                _ = try RulesLoader.decode(Data(json.utf8))
                return "no error"
            } catch let error as RulesError {
                guard case .invalid(let reason) = error else { return "wrong case" }
                return reason
            } catch {
                return "unexpected \(error)"
            }
        }
        XCTAssertEqual(reason(#"{ "rules": [{ "hosts": "a.com" }] }"#), #"missing "profile" in rules[0]"#)
        XCTAssertEqual(reason(#"{ "rules": [{ "profile": 3 }] }"#), "rules[0].profile should be a string")
        XCTAssertEqual(reason(#"{ "rules": {} }"#), "rules should be a list")
        XCTAssertTrue(reason("{ nope").hasPrefix("not valid JSON"))
    }

    func testLoadMissingFile() {
        let url = directory.appendingPathComponent("rules.json")
        XCTAssertThrowsError(try RulesLoader.load(from: url)) { error in
            XCTAssertEqual(error as? RulesError, .missing(path: url.path))
        }
    }

    func testStarterTemplateIsValidAndUsesDetectedProfiles() throws {
        let profiles = [
            ChromeProfile(directory: "Default", name: "Personal \"Main\"", email: "me@gmail.com"),
            ChromeProfile(directory: "Profile 2", name: "Work"),
        ]
        let url = directory.appendingPathComponent("nested/dealer/rules.json")
        XCTAssertTrue(try RulesLoader.writeStarterIfMissing(at: url, profiles: profiles))
        XCTAssertFalse(try RulesLoader.writeStarterIfMissing(at: url, profiles: profiles))

        let rules = try RulesLoader.load(from: url)
        XCTAssertEqual(rules.defaultProfile, "Personal \"Main\"")
        XCTAssertEqual(rules.rules, [])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(#""Work"  →  directory "Profile 2""#))
    }

    func testStarterTemplateWithoutProfiles() throws {
        let rules = try RulesLoader.decode(Data(RulesLoader.starterTemplate(profiles: []).utf8))
        XCTAssertEqual(rules.defaultProfile, "Default")
    }
}

final class PathsTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/jane")

    func testRulesFilePriority() {
        XCTAssertEqual(Paths.rulesFile(environment: [:], home: home).path, "/Users/jane/.config/dealer/rules.json")
        XCTAssertEqual(Paths.rulesFile(environment: ["XDG_CONFIG_HOME": "/cfg"], home: home).path, "/cfg/dealer/rules.json")
        XCTAssertEqual(
            Paths.rulesFile(environment: ["XDG_CONFIG_HOME": "/cfg", "DEALER_RULES": "~/my-rules.json"], home: home).path,
            "/Users/jane/my-rules.json"
        )
        XCTAssertEqual(Paths.rulesFile(environment: ["DEALER_RULES": ""], home: home).path, "/Users/jane/.config/dealer/rules.json")
    }

    func testLegacyRulesFile() {
        XCTAssertEqual(Paths.legacyRulesFile(environment: [:], home: home).path, "/Users/jane/.config/earl/rules.json")
        XCTAssertEqual(Paths.legacyRulesFile(environment: ["XDG_CONFIG_HOME": "/cfg", "DEALER_RULES": "/x.json"], home: home).path, "/cfg/earl/rules.json")
    }

    func testExpandTilde() {
        XCTAssertEqual(Paths.expandTilde("~", home: home), "/Users/jane")
        XCTAssertEqual(Paths.expandTilde("~/a/b", home: home), "/Users/jane/a/b")
        XCTAssertEqual(Paths.expandTilde("/abs/~/x", home: home), "/abs/~/x")
        XCTAssertEqual(Paths.expandTilde("~other/x", home: home), "~other/x")
    }
}
