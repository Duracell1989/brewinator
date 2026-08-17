import Testing

@testable import Brewinator

@Suite("VersionMatcher.cleanVersion")
struct VersionMatcherCleanVersionTests {
    @Test("plain version passes through unchanged")
    func plainVersion() {
        #expect(VersionMatcher.cleanVersion("10.0.400") == "10.0.400")
    }

    @Test("formula revision suffix is stripped")
    func revisionSuffix() {
        #expect(VersionMatcher.cleanVersion("1.2.3_1") == "1.2.3")
    }

    @Test("cask build-number suffix after a comma is stripped")
    func caskBuildSuffix() {
        #expect(VersionMatcher.cleanVersion("2026.1.3.7,quail3,AI-261") == "2026.1.3.7")
    }

    @Test("both comma and revision suffix can coexist")
    func commaThenRevision() {
        #expect(VersionMatcher.cleanVersion("1.2.3_1,extra") == "1.2.3")
    }

    @Test("a legitimate underscore-digit segment before the true end is not truncated")
    func underscoreDigitMidStringIsPreserved() {
        #expect(VersionMatcher.cleanVersion("3.9_1.2.3") == "3.9_1.2.3")
    }

    @Test("a trailing revision suffix after a non-numeric underscore segment is still stripped")
    func revisionSuffixAfterNonNumericSegment() {
        #expect(VersionMatcher.cleanVersion("1.2.3_beta_2") == "1.2.3_beta")
    }
}

@Suite("VersionMatcher.versionChannel")
struct VersionMatcherChannelTests {
    @Test("three-part version keeps first two fields")
    func threePart() {
        #expect(VersionMatcher.versionChannel("10.0.400") == "10.0")
    }

    @Test("two-part version passes through unchanged")
    func twoPart() {
        #expect(VersionMatcher.versionChannel("9.0") == "9.0")
    }

    @Test("single-field version passes through unchanged")
    func singlePart() {
        #expect(VersionMatcher.versionChannel("9") == "9")
    }
}

private struct FakeRelease: VersionTagged {
    let tagName: String
}

@Suite("VersionMatcher.matchRelease")
struct VersionMatcherMatchReleaseTests {
    @Test("exact tag match wins")
    func exactMatch() {
        let releases = [FakeRelease(tagName: "v2.0.0"), FakeRelease(tagName: "v1.0.0")]
        #expect(VersionMatcher.matchRelease(in: releases, version: "1.0.0")?.tagName == "v1.0.0")
    }

    @Test("match is case-insensitive with optional v prefix on either side")
    func caseInsensitiveVPrefix() {
        let releases = [FakeRelease(tagName: "V1.0.0")]
        #expect(VersionMatcher.matchRelease(in: releases, version: "v1.0.0")?.tagName == "V1.0.0")
    }

    @Test("no match falls back to the first (newest) release")
    func fallsBackToFirst() {
        let releases = [FakeRelease(tagName: "v2.0.0"), FakeRelease(tagName: "v1.0.0")]
        #expect(VersionMatcher.matchRelease(in: releases, version: "9.9.9")?.tagName == "v2.0.0")
    }

    @Test("empty list returns nil")
    func emptyList() {
        #expect(VersionMatcher.matchRelease(in: [FakeRelease](), version: "1.0.0") == nil)
    }
}
