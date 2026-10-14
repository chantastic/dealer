import XCTest
@testable import EarlCore

final class GlobTests: XCTestCase {
    func testLiteralMatchIsCaseInsensitiveByDefault() {
        XCTAssertTrue(Glob("GitHub.com").matches("github.com"))
        XCTAssertFalse(Glob("github.com").matches("github.co"))
        XCTAssertFalse(Glob("github.com").matches("github.com.evil"))
    }

    func testCaseSensitiveOption() {
        XCTAssertFalse(Glob("ABC", caseSensitive: true).matches("abc"))
        XCTAssertTrue(Glob("ABC", caseSensitive: true).matches("ABC"))
    }

    func testStarMatchesAnyRunIncludingEmpty() {
        let glob = Glob("a*c")
        XCTAssertTrue(glob.matches("ac"))
        XCTAssertTrue(glob.matches("abc"))
        XCTAssertTrue(glob.matches("a/b.c/c"))
        XCTAssertFalse(glob.matches("ab"))
    }

    func testBacktracking() {
        XCTAssertTrue(Glob("*ab*ab").matches("xabyabab"))
        XCTAssertTrue(Glob("*a*b*c*").matches("zzazzbzzczz"))
        XCTAssertFalse(Glob("*a*b*c*").matches("zzczzbzzazz"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertTrue(Glob("a?c").matches("abc"))
        XCTAssertFalse(Glob("a?c").matches("ac"))
        XCTAssertFalse(Glob("a?c").matches("abbc"))
    }

    func testEscapes() {
        XCTAssertTrue(Glob("what\\?").matches("what?"))
        XCTAssertFalse(Glob("what\\?").matches("whatx"))
        XCTAssertTrue(Glob("a\\*b").matches("a*b"))
        XCTAssertFalse(Glob("a\\*b").matches("axxb"))
    }

    func testDoubleStarBehavesLikeStar() {
        XCTAssertTrue(Glob("a**b").matches("a/x/y/b"))
    }

    func testEmptyPattern() {
        XCTAssertTrue(Glob("").matches(""))
        XCTAssertFalse(Glob("").matches("x"))
        XCTAssertTrue(Glob("*").matches(""))
    }
}

final class HostPatternTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func testExactHost() {
        let pattern = HostPattern("github.com")
        XCTAssertTrue(pattern.matches(url("https://github.com/acme")))
        XCTAssertTrue(pattern.matches(url("https://GITHUB.com")))
        XCTAssertFalse(pattern.matches(url("https://gist.github.com")))
        XCTAssertFalse(pattern.matches(url("https://notgithub.com")))
    }

    func testWildcardSubdomainAlsoMatchesApex() {
        let pattern = HostPattern("*.google.com")
        XCTAssertTrue(pattern.matches(url("https://docs.google.com/document/d/1")))
        XCTAssertTrue(pattern.matches(url("https://a.b.google.com")))
        XCTAssertTrue(pattern.matches(url("https://google.com")))
        XCTAssertFalse(pattern.matches(url("https://evilgoogle.com")))
        XCTAssertFalse(pattern.matches(url("https://google.com.evil.net")))
    }

    func testMidPatternWildcard() {
        let pattern = HostPattern("acme-*.atlassian.net")
        XCTAssertTrue(pattern.matches(url("https://acme-eng.atlassian.net/browse/X-1")))
        XCTAssertFalse(pattern.matches(url("https://other.atlassian.net")))
    }

    func testTrailingDotIsIgnored() {
        XCTAssertTrue(HostPattern("example.com.").matches(url("https://example.com/")))
        XCTAssertTrue(HostPattern("example.com").matches(url("https://example.com./")))
    }

    func testPortPatterns() {
        let pattern = HostPattern("localhost:3000")
        XCTAssertTrue(pattern.matches(url("http://localhost:3000/app")))
        XCTAssertFalse(pattern.matches(url("http://localhost:8080/app")))
        XCTAssertFalse(pattern.matches(url("http://localhost/app")))
        XCTAssertTrue(HostPattern("localhost").matches(url("http://localhost:8080/")))
        XCTAssertTrue(HostPattern("localhost:*").matches(url("http://localhost:8080/")))
    }

    func testURLsWithoutHostNeverMatch() {
        XCTAssertFalse(HostPattern("*").matches(url("file:///tmp/a.html")))
    }

    func testUserInfoDoesNotSpoofHost() {
        XCTAssertFalse(HostPattern("github.com").matches(url("https://github.com@evil.example/")))
    }
}

final class URLPatternTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func testSchemelessPatternIgnoresScheme() {
        let pattern = URLPattern("github.com/acme/*")
        XCTAssertTrue(pattern.matches(url("https://github.com/acme/widgets/pull/1")))
        XCTAssertTrue(pattern.matches(url("http://github.com/acme/x")))
        XCTAssertFalse(pattern.matches(url("https://github.com/other/acme/x")))
        XCTAssertFalse(pattern.matches(url("https://github.com/acme")))
    }

    func testPatternWithSchemeMatchesFullURL() {
        let pattern = URLPattern("https://docs.google.com/*/d/*")
        XCTAssertTrue(pattern.matches(url("https://docs.google.com/spreadsheets/d/abc/edit")))
        XCTAssertFalse(pattern.matches(url("http://docs.google.com/spreadsheets/d/abc/edit")))
    }

    func testQueryStringsAreIncluded() {
        XCTAssertTrue(URLPattern("*?authuser=1*").matches(url("https://mail.google.com/mail/u/0/?authuser=1#inbox")))
    }
}

final class RegexPatternTests: XCTestCase {
    func testUnanchoredMatch() throws {
        let pattern = try RegexPattern(#"\.atlassian\.net/"#)
        XCTAssertTrue(pattern.matches(URL(string: "https://acme.atlassian.net/browse/A-1")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://acme.atlassian.com/")!))
    }

    func testCaseSensitiveUnlessFlagged() throws {
        XCTAssertFalse(try RegexPattern("/PULL/").matches(URL(string: "https://github.com/a/b/pull/1")!))
        XCTAssertTrue(try RegexPattern("(?i)/PULL/").matches(URL(string: "https://github.com/a/b/pull/1")!))
    }

    func testInvalidRegexThrows() {
        XCTAssertThrowsError(try RegexPattern("(unclosed"))
    }
}
