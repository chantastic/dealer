import XCTest
@testable import EarlCore

final class ChromeLocalStateTests: XCTestCase {
    /// Trimmed from a real macOS Chrome `Local State` (values anonymized).
    static let fixture = """
    {
      "browser": { "enabled_labs_experiments": [] },
      "profile": {
        "last_used": "Profile 2",
        "profiles_order": ["Default", "Profile 2", "Missing Profile"],
        "info_cache": {
          "Profile 10": { "name": "Side Project", "user_name": "" },
          "Default": {
            "name": "Personal",
            "gaia_name": "Jane Doe",
            "user_name": "jane@gmail.com",
            "shortcut_name": "Jane",
            "avatar_icon": "chrome://theme/IDR_PROFILE_AVATAR_26"
          },
          "Profile 2": { "name": "Work", "user_name": "jane@acme.com", "gaia_name": "Jane Doe" },
          "Profile 3": { "name": "", "shortcut_name": "Shortcut Only" },
          "Profile 4": { "name": "Ephemeral", "is_ephemeral": true },
          "Guest Profile": { "name": "Guest" },
          "System Profile": { "name": "System" },
          "Profile 9": "not an object"
        }
      }
    }
    """

    func testParsesProfilesInPickerOrderThenNumericDirectoryOrder() throws {
        let profiles = try ChromeLocalState.parseProfiles(from: Data(Self.fixture.utf8))
        XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 2", "Profile 3", "Profile 10"])
    }

    func testParsesFields() throws {
        let profiles = try ChromeLocalState.parseProfiles(from: Data(Self.fixture.utf8))
        XCTAssertEqual(profiles[0], ChromeProfile(directory: "Default", name: "Personal", email: "jane@gmail.com", gaiaName: "Jane Doe"))
        XCTAssertEqual(profiles[1].name, "Work")
        XCTAssertEqual(profiles[2].name, "Shortcut Only")
        XCTAssertNil(profiles[3].email, "empty user_name should be treated as no email")
    }

    func testSortsWithoutProfilesOrder() throws {
        let json = """
        { "profile": { "info_cache": {
            "Profile 11": { "name": "C" }, "Profile 2": { "name": "B" }, "Default": { "name": "A" }
        } } }
        """
        let profiles = try ChromeLocalState.parseProfiles(from: Data(json.utf8))
        XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 2", "Profile 11"])
    }

    func testMissingProfileSectionYieldsNoProfiles() throws {
        XCTAssertEqual(try ChromeLocalState.parseProfiles(from: Data(#"{"browser":{}}"#.utf8)), [])
    }

    func testMalformedInputThrows() {
        XCTAssertThrowsError(try ChromeLocalState.parseProfiles(from: Data("not json".utf8)))
        XCTAssertThrowsError(try ChromeLocalState.parseProfiles(from: Data("[1,2]".utf8)))
    }

    func testLoadFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Local State")
        try Data(Self.fixture.utf8).write(to: file)

        XCTAssertEqual(try ChromeLocalState.loadProfiles(at: file).count, 4)
        XCTAssertThrowsError(try ChromeLocalState.loadProfiles(at: directory.appendingPathComponent("nope")))
    }

    func testPaths() {
        let home = URL(fileURLWithPath: "/Users/jane")
        XCTAssertEqual(
            ChromeLocalState.defaultPath(home: home).path,
            "/Users/jane/Library/Application Support/Google/Chrome/Local State"
        )
        XCTAssertEqual(
            ChromeLocalState.path(for: BrowserConfig(localState: "~/Library/Application Support/BraveSoftware/Brave-Browser/Local State"), home: home).path,
            "/Users/jane/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        )
        XCTAssertEqual(ChromeLocalState.path(for: BrowserConfig(localState: ""), home: home), ChromeLocalState.defaultPath(home: home))
    }

    func testLabel() {
        XCTAssertEqual(ChromeProfile(directory: "Profile 2", name: "Work").label, "Work (Profile 2)")
        XCTAssertEqual(ChromeProfile(directory: "Default", name: "Default").label, "Default")
    }
}
