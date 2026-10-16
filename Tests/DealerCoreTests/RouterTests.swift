import XCTest
@testable import DealerCore

final class RouterTests: XCTestCase {
    private let profiles = [
        ChromeProfile(directory: "Default", name: "Personal", email: "me@gmail.com"),
        ChromeProfile(directory: "Profile 2", name: "Work", email: "me@acme.com", gaiaName: "Me At Acme"),
        ChromeProfile(directory: "Profile 5", name: "Client"),
    ]

    private func url(_ string: String) -> URL { URL(string: string)! }

    private func router(_ json: String) throws -> Router {
        Router(ruleSet: try RulesLoader.decode(Data(json.utf8)))
    }

    func testFirstMatchingRuleWins() throws {
        let router = try router("""
        {
          "defaultProfile": "Personal",
          "rules": [
            { "name": "Client repo", "urls": "github.com/client-co/*", "profile": "Client" },
            { "name": "Work", "hosts": ["github.com", "*.atlassian.net"], "profile": "Work" }
          ]
        }
        """)

        let client = router.route(url("https://github.com/client-co/app/pull/3"), profiles: profiles)
        XCTAssertEqual(client.matchedRule, "Client repo")
        XCTAssertEqual(client.profileDirectory, "Profile 5")

        let work = router.route(url("https://github.com/acme/app"), profiles: profiles)
        XCTAssertEqual(work.matchedRule, "Work")
        XCTAssertEqual(work.profileDirectory, "Profile 2")

        let jira = router.route(url("https://acme.atlassian.net/browse/X-1"), profiles: profiles)
        XCTAssertEqual(jira.profileDirectory, "Profile 2")
    }

    func testUnmatchedURLUsesDefaultProfile() throws {
        let router = try router(#"{ "defaultProfile": "Personal", "rules": [{ "hosts": "github.com", "profile": "Work" }] }"#)
        let decision = router.route(url("https://news.ycombinator.com"), profiles: profiles)
        XCTAssertNil(decision.matchedRule)
        XCTAssertEqual(decision.requestedProfile, "Personal")
        XCTAssertEqual(decision.profileDirectory, "Default")
        XCTAssertTrue(decision.notes.isEmpty)
    }

    func testNoDefaultMeansNoProfileArgument() throws {
        let router = try router(#"{ "rules": [] }"#)
        let decision = router.route(url("https://example.com"), profiles: profiles)
        XCTAssertNil(decision.profileDirectory)
        XCTAssertNil(decision.requestedProfile)
    }

    func testRegexRules() throws {
        let router = try router(#"""
        { "rules": [ { "name": "Meet", "regex": ["^https://meet\\.google\\.com/[a-z]{3}-"], "profile": "Profile 2" } ] }
        """#)
        XCTAssertEqual(router.route(url("https://meet.google.com/abc-defg-hij"), profiles: profiles).profileDirectory, "Profile 2")
        XCTAssertNil(router.route(url("https://meet.google.com/landing"), profiles: profiles).matchedRule)
    }

    func testDisabledRulesAreSkipped() throws {
        let router = try router("""
        { "rules": [
            { "name": "Off", "enabled": false, "hosts": "example.com", "profile": "Work" },
            { "name": "On", "hosts": "example.com", "profile": "Client" }
        ] }
        """)
        XCTAssertEqual(router.route(url("https://example.com"), profiles: profiles).matchedRule, "On")
    }

    func testUnknownRuleProfileFallsBackToDefaultWithNote() throws {
        let router = try router(#"{ "defaultProfile": "Personal", "rules": [{ "name": "Typo", "hosts": "example.com", "profile": "Wrok" }] }"#)
        let decision = router.route(url("https://example.com"), profiles: profiles)
        XCTAssertEqual(decision.matchedRule, "Typo")
        XCTAssertEqual(decision.requestedProfile, "Wrok")
        XCTAssertEqual(decision.profileDirectory, "Default")
        XCTAssertEqual(decision.notes.count, 1)
        XCTAssertEqual(router.unresolvedProfiles(in: profiles), ["Wrok"])
    }

    func testUnknownDefaultProfileMeansNoProfileArgument() throws {
        let router = try router(#"{ "defaultProfile": "Nope" }"#)
        let decision = router.route(url("https://example.com"), profiles: profiles)
        XCTAssertNil(decision.profileDirectory)
        XCTAssertEqual(decision.notes.count, 1)
    }

    func testWithoutKnownProfilesReferencesAreUsedAsDirectories() throws {
        let router = try router(#"{ "defaultProfile": "Default", "rules": [{ "hosts": "example.com", "profile": "Profile 7" }] }"#)
        XCTAssertEqual(router.route(url("https://example.com"), profiles: []).profileDirectory, "Profile 7")
        XCTAssertEqual(router.route(url("https://other.com"), profiles: []).profileDirectory, "Default")
        XCTAssertTrue(router.unresolvedProfiles(in: []).isEmpty)
    }

    func testCompileIssuesAreReportedButDoNotBreakOtherPatterns() throws {
        let router = try router("""
        { "rules": [
            { "name": "Broken", "regex": ["(bad", "good"], "hosts": ["github.com/acme"], "profile": "Work" },
            { "name": "Empty", "profile": "Work" }
        ] }
        """)
        XCTAssertEqual(router.issues.count, 3)
        XCTAssertEqual(router.route(url("https://example.com/good"), profiles: profiles).matchedRule, "Broken")
    }

    func testUnnamedRulesGetPositionalNames() throws {
        let router = try router(#"{ "rules": [{ "hosts": "a.com", "profile": "Work" }, { "hosts": "b.com", "profile": "Work" }] }"#)
        XCTAssertEqual(router.route(url("https://b.com"), profiles: profiles).matchedRule, "rule #2")
    }
}

final class ProfileResolverTests: XCTestCase {
    private let profiles = [
        ChromeProfile(directory: "Default", name: "Personal", email: "me@gmail.com"),
        ChromeProfile(directory: "Profile 2", name: "Work", email: "me@acme.com", gaiaName: "Jane Doe"),
        // A display name that collides with another profile's directory.
        ChromeProfile(directory: "Profile 3", name: "Default"),
    ]

    func testResolutionOrder() {
        XCTAssertEqual(ProfileResolver.resolve("Profile 2", in: profiles), "Profile 2")
        XCTAssertEqual(ProfileResolver.resolve("profile 2", in: profiles), "Profile 2")
        XCTAssertEqual(ProfileResolver.resolve("work", in: profiles), "Profile 2")
        XCTAssertEqual(ProfileResolver.resolve("ME@ACME.COM", in: profiles), "Profile 2")
        XCTAssertEqual(ProfileResolver.resolve("Jane Doe", in: profiles), "Profile 2")
        XCTAssertEqual(ProfileResolver.resolve(" Personal ", in: profiles), "Default")
    }

    func testDirectoryBeatsDisplayName() {
        XCTAssertEqual(ProfileResolver.resolve("Default", in: profiles), "Default")
    }

    func testUnknownAndEmpty() {
        XCTAssertNil(ProfileResolver.resolve("Nobody", in: profiles))
        XCTAssertNil(ProfileResolver.resolve("  ", in: profiles))
        XCTAssertNil(ProfileResolver.resolve("", in: []))
    }
}
