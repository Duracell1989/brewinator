import Foundation

/// A Homebrew version whose last component is a GNU patch level rather than a
/// release component: `8.3.6` is release `8.3` with six patches applied.
/// A two-component version (`8.3`, the freshly-imported tarball) is patch 0.
struct PatchLevelVersion: Sendable, Equatable {
    let release: String
    let patch: Int

    /// `83` — the form the patch filenames use (`readline83-004`).
    var compactRelease: String {
        release.replacingOccurrences(of: ".", with: "")
    }

    init?(_ version: String) {
        let parts = version.split(separator: ".").map(String.init)
        switch parts.count {
        case 2:
            release = parts.joined(separator: ".")
            patch = 0
        case 3:
            guard let level = Int(parts[2]) else { return nil }
            release = parts[0...1].joined(separator: ".")
            patch = level
        default:
            return nil
        }
    }
}

/// GNU projects that ship fixes as numbered patch files rather than point
/// releases — `readline` and `bash`, both Chet Ramey's. Homebrew encodes the
/// applied patch count as the version's last component, so `8.3.3 -> 8.3.6` is
/// not three releases but patches 004, 005 and 006 against one unchanged 8.3
/// tarball: the formula keeps `url` pinned at `readline-8.3.tar.gz` throughout
/// and only gains `patch do` blocks.
///
/// Nothing else in the source list can cover that bump. The stable URL,
/// homepage and (absent) head URL name no forge, so resolution reports "No
/// forge repo detected" — and teaching it one would not help: upstream is
/// Savannah cgit, which publishes no release objects and is not a dialect
/// `ForgeRepoResolver` speaks. The in-tree `NEWS` file is no better, describing
/// 8.3 against 8.2 and never mentioning a patch. The notes exist only as the
/// `Bug-Description` block inside each patch file.
///
/// Claims a package only for a same-release patch bump. A real release bump
/// (`8.3.6 -> 8.4`) is left to fall through deliberately: a patch range is
/// meaningless across it, and `Resolver` hands the first claimant the whole
/// result with no fallback.
struct GNUPatchNotes: NoteSource {
    /// Each report is its own HTTP request, so a long-deferred upgrade would
    /// otherwise fan out unboundedly. The newest are the ones worth reading.
    private static let maxPatches = 12

    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.gnuPatchProjects[package.name] != nil && Self.patchRange(package) != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let spec = database.gnuPatchProjects[package.name], let range = Self.patchRange(package) else {
            return .success(Resolver.noForgeDetected)
        }

        let wanted = Array(range.numbers.suffix(Self.maxPatches))
        var sections: [String] = []
        var missing: [Int] = []
        var directoryURL: URL?

        for number in wanted {
            guard let url = Self.patchURL(spec: spec, release: range.release, number: number) else {
                missing.append(number)
                continue
            }
            directoryURL = url.deletingLastPathComponent()
            guard let report = await fetchReport(url) else {
                missing.append(number)
                continue
            }
            sections.append(report.markdown(number: number, project: package.name, release: range.release))
        }

        guard !sections.isEmpty else {
            let span = "\(Self.padded(wanted.first ?? 0))-\(Self.padded(wanted.last ?? 0))"
            return .failure(.transient(reason: "\(package.name): no patch report fetched for \(span)"))
        }

        // The preamble names what the bump *applies*, never merely what was
        // fetched: ftp.gnu.org throttles, and a dropped report silently
        // narrowing the stated range turns a gap into a false claim about the
        // upgrade. Anything missing is called out instead.
        var markdown = Self.preamble(package: package, release: range.release, numbers: wanted, skipped: range.numbers.count - wanted.count)
        if !missing.isEmpty {
            let list = missing.map(Self.padded).joined(separator: ", ")
            markdown += "_Patch \(missing.count == 1 ? "report" : "reports") \(list) could not be fetched — see the patch directory below._\n\n"
        }
        // Each section already ends in a blank line; joining on one more would double it.
        markdown += sections.joined()
        if let directoryURL {
            // `deletingLastPathComponent()` already leaves the trailing slash on.
            markdown += "[Patch directory](\(directoryURL.absoluteString))\n\n"
        }
        return .success(ReleaseNotes(markdown: markdown))
    }

    private func fetchReport(_ url: URL) async -> GNUPatchReport? {
        guard let (data, status) = try? await httpFetcher.fetch(url), status == 200, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return GNUPatchReport(text)
    }

    /// The patch numbers a bump applies, or nil when this source should not
    /// claim the package at all.
    private static func patchRange(_ package: OutdatedPackageInfo) -> (release: String, numbers: [Int])? {
        guard let installed = PatchLevelVersion(package.cleanInstalledVersion),
            let current = PatchLevelVersion(package.cleanCurrentVersion),
            installed.release == current.release,
            current.patch > installed.patch
        else {
            return nil
        }
        return (current.release, Array((installed.patch + 1)...current.patch))
    }

    private static func patchURL(spec: GNUPatchSpec, release: String, number: Int) -> URL? {
        guard let compact = PatchLevelVersion("\(release).0")?.compactRelease else { return nil }
        let path = spec.urlTemplate
            .replacingOccurrences(of: "%release", with: release)
            .replacingOccurrences(of: "%compact", with: compact)
            .replacingOccurrences(of: "%patch", with: padded(number))
        return URL(string: path)
    }

    private static func padded(_ number: Int) -> String {
        String(format: "%03d", number)
    }

    private static func preamble(package: OutdatedPackageInfo, release: String, numbers: [Int], skipped: Int) -> String {
        let list = numbers.map(padded)
        let applied: String
        switch list.count {
        case 1:
            applied = "patch \(list[0])"
        default:
            applied = "patches \(list.dropLast().joined(separator: ", ")) and \(list[list.count - 1])"
        }

        var text = "Homebrew's `\(release).x` is upstream \(package.name) **\(release)** plus official patches — "
        text += "the last version component is the patch level, not a release. "
        text += "`\(package.cleanInstalledVersion) → \(package.cleanCurrentVersion)` applies \(applied).\n\n"
        if skipped > 0 {
            text += "_\(skipped) older \(skipped == 1 ? "patch is" : "patches are") omitted._\n\n"
        }
        return text
    }
}

/// One GNU patch report — the plain-text file served from the project's
/// `*-patches/` directory. `readline` and `bash` use byte-identical layouts
/// (only the `Readline-Release:`/`Bash-Release:` key differs, which is not read
/// here), so one parser covers both.
struct GNUPatchReport: Sendable, Equatable {
    /// `readline83-004`, straight from the `Patch-ID:` line.
    let patchID: String?
    /// Reporter names with their `<email>` stripped — the archive is a reading
    /// copy, not a mailing-list mirror.
    let reportedBy: [String]
    let referenceURL: String?
    let description: String

    /// Where the free-text description stops and the diff begins.
    private static let diffMarker = "Patch (apply with"

    init?(_ text: String) {
        var accumulator = Accumulator()
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(Self.diffMarker) {
                break
            }
            if let header = Self.header(in: line) {
                accumulator.apply(header)
            } else {
                accumulator.append(line)
            }
        }

        let body = accumulator.description.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        patchID = accumulator.patchID
        reportedBy = accumulator.reportedBy.filter { !$0.isEmpty }
        referenceURL = accumulator.referenceURL
        description = body
    }

    func markdown(number: Int, project: String, release: String) -> String {
        let heading = patchID ?? "\(project)\(release.replacingOccurrences(of: ".", with: ""))-\(String(format: "%03d", number))"
        var text = "### \(heading)\n\n"
        if !reportedBy.isEmpty {
            text += "_Reported by \(reportedBy.joined(separator: ", "))._\n\n"
        }
        text += description.firstLines(40)
        text += "\n\n"
        if let referenceURL {
            text += "[Bug report](\(referenceURL))\n\n"
        }
        return text
    }

    /// The header lines the parser acts on. Every other header in the block —
    /// `Readline-Release:`, `Bug-Reference-ID:` — is ignored, but still has to
    /// be recognised as a header so that it ends a run of reporter
    /// continuation lines.
    private enum Header {
        case patchID(String)
        case reportedBy(String)
        case referenceURL(String)
        case descriptionStart
    }

    private static func header(in line: String) -> Header? {
        if let value = value(of: "Patch-ID:", in: line) {
            return .patchID(value)
        }
        if let value = value(of: "Bug-Reported-by:", in: line) {
            return .reportedBy(value)
        }
        if let value = value(of: "Bug-Reference-URL:", in: line) {
            return .referenceURL(value)
        }
        if line.hasPrefix("Bug-Description:") {
            return .descriptionStart
        }
        return nil
    }

    /// Fields under construction, plus which multi-line block the parser is
    /// currently inside.
    private enum Collecting {
        case none
        case reporters
        case description
    }

    private struct Accumulator {
        var patchID: String?
        var reportedBy: [String] = []
        var referenceURL: String?
        var description: [String] = []
        var collecting: Collecting = .none

        mutating func apply(_ header: Header) {
            switch header {
            case .patchID(let value):
                patchID = value
                collecting = .none
            case .reportedBy(let value):
                reportedBy.append(GNUPatchReport.stripEmail(value))
                collecting = .reporters
            case .referenceURL(let value):
                // Only the first - a second is the other reporter's thread.
                referenceURL = referenceURL ?? value
                collecting = .none
            case .descriptionStart:
                collecting = .description
            }
        }

        /// A continuation line is indented; every header key starts at column
        /// 0. readline83-005 lists a second reporter that way.
        mutating func append(_ line: String) {
            switch collecting {
            case .reporters where line.hasPrefix(" ") || line.hasPrefix("\t"):
                reportedBy.append(GNUPatchReport.stripEmail(line))
            case .reporters:
                collecting = .none
            case .description:
                description.append(line)
            case .none:
                break
            }
        }
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func stripEmail(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
