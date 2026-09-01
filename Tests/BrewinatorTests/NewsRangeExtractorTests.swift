import Foundation
import Testing

@testable import Brewinator

@Suite("NewsHeadingStyle")
struct NewsHeadingStyleTests {
    @Test("gnupg reads the version as the first token, ignoring the date and libtool triple")
    func gnupgHeadings() {
        #expect(NewsHeadingStyle.gnupg.version(of: "Noteworthy changes in version 2.2.0 (2026-08-31)   [C47/A2/R0]") == "2.2.0")
        #expect(NewsHeadingStyle.gnupg.version(of: "Noteworthy changes in version 2.5.22 (2026-08-31)") == "2.5.22")
        #expect(NewsHeadingStyle.gnupg.version(of: "Noteworthy changes in version 1.61 (2026-05-07) [C42/A42/R1]") == "1.61")
        #expect(NewsHeadingStyle.gnupg.version(of: "Noteworthy changes in version 2.2.1 (unreleased)   [C__/A_/R0]") == "2.2.1")
    }

    // Regression guard for lifting this out of GitLabReleases: these three
    // shapes are the ones pango/GLib/poppler actually ship.
    @Test("gnome reads the version as the last token, ignoring a project name and trailing date")
    func gnomeHeadings() {
        #expect(NewsHeadingStyle.gnome.version(of: "Overview of changes in 1.58.2, 05-08-2026") == "1.58.2")
        #expect(NewsHeadingStyle.gnome.version(of: "Overview of Changes in GLib 2.88.0") == "2.88.0")
        #expect(NewsHeadingStyle.gnome.version(of: "Overview of changes leading to 11.0.0") == "11.0.0")
    }

    @Test("neither style matches the other's headings or ordinary prose")
    func stylesDoNotOverlap() {
        #expect(NewsHeadingStyle.gnome.version(of: "Noteworthy changes in version 2.2.0 (2026-08-31)") == nil)
        #expect(NewsHeadingStyle.gnupg.version(of: "Overview of changes in 1.58.2, 05-08-2026") == nil)
        #expect(NewsHeadingStyle.gnupg.version(of: " * Handle the new SIGINFO status line.  [T8368]") == nil)
        #expect(NewsHeadingStyle.gnome.version(of: "------------------------------------------------") == nil)
    }
}

@Suite("NewsRangeExtractor")
struct NewsRangeExtractorTests {
    private let news = """
        Noteworthy changes in version 3.0 (unreleased)
        ----------------------------------------------

         * Not shipped yet.

        Noteworthy changes in version 2.0 (2026-08-31)
        ----------------------------------------------

         * Second.

        Noteworthy changes in version 1.0 (2026-01-01)
        ----------------------------------------------

         * First.
        """

    @Test("the range is half-open: newest inclusive, oldest exclusive")
    func halfOpenRange() {
        let section = NewsRangeExtractor.extract(from: news, newest: "2.0", oldest: "1.0", style: .gnupg)
        #expect(section.contains("Second."))
        #expect(!section.contains("First."))
        #expect(!section.contains("Not shipped yet."))
    }

    @Test("an empty oldest runs to the end of the file")
    func openEndedRange() {
        let section = NewsRangeExtractor.extract(from: news, newest: "2.0", oldest: "", style: .gnupg)
        #expect(section.contains("Second."))
        #expect(section.contains("First."))
        #expect(!section.contains("Not shipped yet."))
    }

    @Test("an empty newest starts at the first heading in the file")
    func openStartedRange() {
        let section = NewsRangeExtractor.extract(from: news, newest: "", oldest: "2.0", style: .gnupg)
        #expect(section.contains("Not shipped yet."))
        #expect(!section.contains("Second."))
    }

    @Test("a newest version absent from the file yields nothing")
    func missingNewestYieldsNothing() {
        let section = NewsRangeExtractor.extract(from: news, newest: "9.9", oldest: "1.0", style: .gnupg)
        #expect(section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("the wrong heading style matches no heading at all")
    func wrongStyleYieldsNothing() {
        let section = NewsRangeExtractor.extract(from: news, newest: "2.0", oldest: "1.0", style: .gnome)
        #expect(section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
