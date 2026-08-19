import Foundation
import Testing

@testable import Brewinator

@Suite("NotificationSummary")
struct NotificationSummaryTests {
    private static func package(_ name: String) -> OutdatedPackageInfo {
        OutdatedPackageInfo(name: name, installedVersion: "1.0", currentVersion: "1.1", kind: .formula)
    }

    private static func result(newNames: [String], outdatedCount: Int) -> SyncResult {
        SyncResult(
            outdated: (0..<outdatedCount).map { package("package\($0)") },
            newItems: newNames.map { SyncResult.NewItem(name: $0, version: "1.1") },
            trashedFiles: []
        )
    }

    @Test("titles every banner Brewinator so the run is identifiable")
    func titleIsConstant() {
        #expect(NotificationSummary.render(Self.result(newNames: [], outdatedCount: 0)).title == "Brewinator")
        #expect(NotificationSummary.renderFailure(NotifierError.processFailed(exitCode: 1)).title == "Brewinator")
    }

    @Test("counts new notes in the subtitle")
    func subtitleCountsNewNotes() {
        let content = NotificationSummary.render(Self.result(newNames: ["merve", "simdutf"], outdatedCount: 5))

        #expect(content.subtitle == "2 new release notes")
        #expect(content.body == "merve, simdutf")
    }

    @Test("says note, not notes, for a single one")
    func subtitleIsSingularForOne() {
        #expect(NotificationSummary.render(Self.result(newNames: ["merve"], outdatedCount: 3)).subtitle == "1 new release note")
    }

    @Test("a quiet run still reports how many packages are outdated")
    func quietRunReportsOutdatedCount() {
        let content = NotificationSummary.render(Self.result(newNames: [], outdatedCount: 11))

        #expect(content.subtitle == "No new release notes")
        #expect(content.body == "11 outdated.")
    }

    @Test("a fully up-to-date run still produces a banner")
    func nothingOutdatedStillNotifies() {
        let content = NotificationSummary.render(Self.result(newNames: [], outdatedCount: 0))

        #expect(content.subtitle == "No new release notes")
        #expect(content.body == "Nothing outdated.")
    }

    @Test("lists four names in full")
    func fourNamesAreNotElided() {
        let content = NotificationSummary.render(Self.result(newNames: ["a", "b", "c", "d"], outdatedCount: 4))

        #expect(content.body == "a, b, c, d")
    }

    @Test("elides past four rather than letting Notification Center cut mid-word")
    func moreThanFourNamesAreElided() {
        let content = NotificationSummary.render(Self.result(newNames: ["a", "b", "c", "d", "e", "f"], outdatedCount: 6))

        #expect(content.body == "a, b, c, d +2 more")
    }

    @Test("a failed run is distinguishable from a quiet one")
    func failureIsItsOwnSubtitle() {
        let content = NotificationSummary.renderFailure(BrewClientError.invalidOutdatedOutput)

        #expect(content.subtitle == "Run failed")
        #expect(content.body.contains("invalidOutdatedOutput"))
    }
}
