import Testing

@testable import Brewinator

private let changelog = """
    3.0.3
    - Fixes sync after a long period of inactivity
    3.0.2
    - Fixes a crash during app launch if not connected online
    3.0.1
    - Fixes several rare crashes when syncing
    - Improves support for users with custom domain addresses
    """

@Suite("VersionSectionExtractor")
struct VersionSectionExtractorTests {
    @Test("takes only the requested version's section, stopping at the next heading")
    func takesOneSection() {
        #expect(VersionSectionExtractor.section(for: "3.0.2", in: changelog) == "- Fixes a crash during app launch if not connected online")
    }

    @Test("the newest and the oldest sections are bounded correctly")
    func firstAndLastSection() {
        #expect(VersionSectionExtractor.section(for: "3.0.3", in: changelog) == "- Fixes sync after a long period of inactivity")
        #expect(
            VersionSectionExtractor.section(for: "3.0.1", in: changelog)
                == "- Fixes several rare crashes when syncing\n- Improves support for users with custom domain addresses"
        )
    }

    // The whole point of returning nil: a bundle that predates the upgrade must
    // not archive the previous release's notes under the new version.
    @Test("a version the changelog does not carry is nil, not the nearest section")
    func missingVersionIsNil() {
        #expect(VersionSectionExtractor.section(for: "3.1.0", in: changelog) == nil)
    }

    @Test("a heading with no content under it is nil rather than an empty section")
    func emptySectionIsNil() {
        #expect(VersionSectionExtractor.section(for: "2.0.0", in: "2.0.0\n1.9.0\n- Something") == nil)
    }

    @Test("headings accept a v or Version prefix")
    func headingPrefixes() {
        #expect(VersionSectionExtractor.headingVersion(of: "  3.0.3 ") == "3.0.3")
        #expect(VersionSectionExtractor.headingVersion(of: "v3.0.3") == "3.0.3")
        #expect(VersionSectionExtractor.headingVersion(of: "Version 6.5.1") == "6.5.1")
    }

    @Test("prose, bullets and bare numbers are not headings")
    func nonHeadings() {
        #expect(VersionSectionExtractor.headingVersion(of: "- Fixes 1.2.3 parsing") == nil)
        #expect(VersionSectionExtractor.headingVersion(of: "Released 2026") == nil)
        #expect(VersionSectionExtractor.headingVersion(of: "2026") == nil)
        #expect(VersionSectionExtractor.headingVersion(of: "3.0.3 - sync fixes") == nil)
    }
}
