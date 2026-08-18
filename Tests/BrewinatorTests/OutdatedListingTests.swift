import Testing

@testable import Brewinator

@Suite("OutdatedListing")
struct OutdatedListingTests {
    private func package(_ name: String, _ installed: String, _ current: String, _ kind: PackageKind) -> OutdatedPackageInfo {
        OutdatedPackageInfo(name: name, installedVersion: installed, currentVersion: current, kind: kind)
    }

    @Test("renders a count header and one aligned row per package, replacing `brew outdated --verbose` in brewcheck")
    func rendersAlignedRows() {
        let rendered = OutdatedListing.render([
            package("claude-code", "2.1.220", "2.1.226", .cask),
            package("nss", "3.126.1", "3.127", .formula),
        ])

        #expect(
            rendered == """
                Outdated (2):
                  claude-code (cask)  2.1.220 -> 2.1.226
                  nss (formula)       3.126.1 -> 3.127
                """
        )
    }

    @Test("an empty set renders a single line, not an empty header")
    func rendersEmptySet() {
        #expect(OutdatedListing.render([]) == "Nothing outdated.")
    }

    @Test("Homebrew revision suffixes are stripped, matching the archive filenames")
    func stripsRevisionSuffixes() {
        let rendered = OutdatedListing.render([package("nss", "3.126.1_1", "3.127_2", .formula)])

        #expect(rendered.contains("3.126.1 -> 3.127"))
    }
}
