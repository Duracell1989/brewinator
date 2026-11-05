import Foundation
import Testing

@testable import Brewinator

@Suite("NoNotesSummary")
struct NoNotesSummaryTests {
    private func package(_ name: String, _ installed: String, _ current: String, kind: PackageKind = .cask) -> OutdatedPackageInfo {
        OutdatedPackageInfo(name: name, installedVersion: installed, currentVersion: current, kind: kind)
    }

    private func config(skipList: [String] = []) -> UserConfig {
        UserConfig(archiveDirectory: "/notes", skipList: skipList, notify: false)
    }

    @Test("is nil when no outdated package is skipped, so no file is written")
    func nilWhenNothingSkipped() {
        let markdown = NoNotesSummary.markdown(for: [package("node", "23.0.0", "23.1.0", kind: .formula)], config: config())

        #expect(markdown == nil)
    }

    @Test("lists a built-in skipped package with its versions and the built-in reason")
    func listsBuiltInWithReason() throws {
        let markdown = try #require(NoNotesSummary.markdown(for: [package("discord", "0.0.420", "0.0.421")], config: config()))

        #expect(markdown.contains("- discord (cask) 0.0.420 → 0.0.421 - no structured per-version changelog"))
    }

    @Test("lists a package skipped through the user's own list, saying so")
    func listsUserSkipped() throws {
        let markdown = try #require(
            NoNotesSummary.markdown(for: [package("nspr", "4.36", "4.37", kind: .formula)], config: config(skipList: ["nspr"]))
        )

        #expect(markdown.contains("- nspr (formula) 4.36 → 4.37 - on your skip list"))
    }

    @Test("a user glob is credited to the user, a built-in to its own reason")
    func globsAndBuiltInsMixed() throws {
        let markdown = try #require(
            NoNotesSummary.markdown(
                for: [package("proton-mail", "1.15.1", "1.16.0"), package("spotify", "1", "2")],
                config: config(skipList: ["proton-*"])
            )
        )

        #expect(markdown.contains("- proton-mail (cask) 1.15.1 → 1.16.0 - on your skip list"))
        #expect(markdown.contains("- spotify (cask) 1 → 2 - desktop release notes stopped in 2015"))
    }

    @Test("leaves out packages that are not skipped and sorts the rest by name")
    func sortedAndFiltered() throws {
        let markdown = try #require(
            NoNotesSummary.markdown(
                for: [package("whatsapp", "1", "2"), package("obsidian", "1.14.5", "1.15.0"), package("deepl", "1", "2")],
                config: config()
            )
        )

        #expect(!markdown.contains("obsidian"))
        let deepl = try #require(markdown.range(of: "- deepl"))
        let whatsapp = try #require(markdown.range(of: "- whatsapp"))
        #expect(deepl.lowerBound < whatsapp.lowerBound)
    }

    @Test("a formula and a cask with the same name keep a fixed order")
    func sameNameOrderIsStable() throws {
        let markdown = try #require(
            NoNotesSummary.markdown(
                for: [package("nspr", "1", "2", kind: .formula), package("nspr", "1", "2", kind: .cask)],
                config: config(skipList: ["nspr"])
            )
        )

        let cask = try #require(markdown.range(of: "- nspr (cask)"))
        let formula = try #require(markdown.range(of: "- nspr (formula)"))
        #expect(cask.lowerBound < formula.lowerBound)
    }

    @Test("every built-in entry has a non-empty reason")
    func builtInReasonsAreFilled() {
        for entry in BuiltInSkipList.entries {
            #expect(!entry.reason.isEmpty, "\(entry.pattern) has no reason")
        }
    }
}
