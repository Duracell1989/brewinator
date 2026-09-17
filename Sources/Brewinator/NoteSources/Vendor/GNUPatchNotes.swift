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

/// What came back for one patch report. The three cases are kept apart because
/// they want opposite handling: `unreachable` is worth retrying tomorrow,
/// `unparseable` never will be, and conflating them either retries forever or
/// archives a gap permanently.
private enum PatchReportFetch {
    case parsed(GNUPatchReport)
    case unparseable
    case unreachable(String)
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
    private static let maxDescriptionLines = 40

    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    /// `kind` is part of the predicate because a formula and a cask can share a
    /// bare name — the same collision `ArchivePackageIdentity` exists for. A
    /// cask claimed here would be fetched from ftp.gnu.org and never reach its
    /// real notes, since the first claimant takes the whole result.
    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.kind == .formula && database.gnuPatchProjects[package.name] != nil && Self.patchRange(package) != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard package.kind == .formula, let spec = database.gnuPatchProjects[package.name], let range = Self.patchRange(package) else {
            return .success(Resolver.noForgeDetected)
        }

        let wanted = Array(range.numbers.suffix(Self.maxPatches))
        var sections: [String] = []
        var directoryURL: URL?

        for number in wanted {
            let identifier = Self.patchIdentifier(project: package.name, version: range.version, number: number)
            guard let url = Self.patchURL(spec: spec, version: range.version, number: number) else {
                return .failure(.transient(reason: "\(package.name): \(spec.urlTemplate) does not render a valid URL for \(identifier)"))
            }
            directoryURL = url.deletingLastPathComponent()

            switch await fetchReport(url) {
            case .parsed(let report):
                sections.append(report.markdown(fallbackIdentifier: identifier, maxLines: Self.maxDescriptionLines))
            case .unparseable:
                // Archived rather than retried: the layout will not change back
                // by tomorrow, and a note naming the report beats a warning
                // logged every morning with nothing written.
                sections.append(Self.unreadableSection(identifier: identifier, url: url))
            case .unreachable(let reason):
                // Stop at the first unreachable report instead of grinding
                // through a throttle. `BrewNotesSync` writes an archive file
                // once and never revisits that version, so a partial note would
                // be permanent - and 12 reports against a hung host would add
                // minutes to an unattended run. A transient failure costs only
                // a retry on the next run.
                return .failure(.transient(reason: "\(package.name) \(url.absoluteString): \(reason)"))
            }
        }

        guard !sections.isEmpty else {
            return .failure(.transient(reason: "\(package.name): no patch reports in range"))
        }

        // The preamble names what the bump *applies* - the full range, not the
        // capped subset that gets bodies. Narrowing this sentence to whatever
        // was fetched turns a retrieval or capping decision into a false claim
        // about the upgrade itself.
        var markdown = Self.preamble(package: package, version: range.version, numbers: range.numbers, omitted: range.numbers.count - wanted.count)
        // Each section already ends in a blank line; joining on one more would double it.
        markdown += sections.joined()
        if let directoryURL {
            // `deletingLastPathComponent()` already leaves the trailing slash on.
            markdown += "[Patch directory](\(directoryURL.absoluteString))\n\n"
        }
        return .success(ReleaseNotes(markdown: markdown))
    }

    private func fetchReport(_ url: URL) async -> PatchReportFetch {
        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .unreachable("\(error)")
        }
        guard status == 200 else {
            return .unreachable("HTTP \(status)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .unparseable
        }
        guard let report = GNUPatchReport(text) else {
            return .unparseable
        }
        return .parsed(report)
    }

    /// The patch numbers a bump applies, or nil when this source should not
    /// claim the package at all.
    private static func patchRange(_ package: OutdatedPackageInfo) -> (version: PatchLevelVersion, numbers: [Int])? {
        guard let installed = PatchLevelVersion(package.cleanInstalledVersion),
            let current = PatchLevelVersion(package.cleanCurrentVersion),
            installed.release == current.release,
            current.patch > installed.patch
        else {
            return nil
        }
        return (current, Array((installed.patch + 1)...current.patch))
    }

    private static func patchURL(spec: GNUPatchSpec, version: PatchLevelVersion, number: Int) -> URL? {
        let path = spec.urlTemplate
            .replacingOccurrences(of: "%release", with: version.release)
            .replacingOccurrences(of: "%compact", with: version.compactRelease)
            .replacingOccurrences(of: "%patch", with: padded(number))
        return URL(string: path)
    }

    /// `readline83-004` — what the report's own `Patch-ID:` line should say,
    /// used as the heading when the file does not carry one.
    private static func patchIdentifier(project: String, version: PatchLevelVersion, number: Int) -> String {
        "\(project)\(version.compactRelease)-\(padded(number))"
    }

    private static func padded(_ number: Int) -> String {
        String(format: "%03d", number)
    }

    private static func unreadableSection(identifier: String, url: URL) -> String {
        var text = "### \(identifier)\n\n"
        text += "_The report was fetched but could not be read — its layout is unfamiliar._\n\n"
        text += "[Patch report](\(url.absoluteString))\n\n"
        return text
    }

    private static func preamble(package: OutdatedPackageInfo, version: PatchLevelVersion, numbers: [Int], omitted: Int) -> String {
        let list = numbers.map(padded)
        let applied: String
        switch list.count {
        case 1:
            applied = "patch \(list[0])"
        default:
            applied = "patches \(list.dropLast().joined(separator: ", ")) and \(list[list.count - 1])"
        }

        var text = "Homebrew's `\(version.release).x` is upstream \(package.name) **\(version.release)** plus official patches — "
        text += "the last version component is the patch level, not a release. "
        text += "`\(package.cleanInstalledVersion) → \(package.cleanCurrentVersion)` applies \(applied).\n\n"
        if omitted > 0 {
            let noun = omitted == 1 ? "report is" : "reports are"
            text += "_Only the newest \(numbers.count - omitted) are reproduced below; \(omitted) older \(noun) omitted._\n\n"
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

    /// Where the free-text description stops and the diff begins. The unified
    /// header lines are a second anchor: if upstream ever reformats the primary
    /// marker, the description ends at the first diff line instead of swallowing
    /// the entire patch and archiving it as release notes.
    private static let diffMarker = "Patch (apply with"
    private static let diffHeaderMarkers = ["*** ", "--- "]

    init?(_ text: String) {
        var accumulator = Accumulator()
        // Normalised up front so a CRLF-served report cannot leak a carriage
        // return into a heading, a reporter name or a bug-report URL.
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if Self.endsDescription(line, started: accumulator.collecting == .description) {
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

    func markdown(fallbackIdentifier: String, maxLines: Int) -> String {
        var text = "### \(patchID ?? fallbackIdentifier)\n\n"
        if !reportedBy.isEmpty {
            text += "_Reported by \(reportedBy.joined(separator: ", "))._\n\n"
        }
        text += MarkdownSection.body(description, maxLines: maxLines, link: referenceURL, linkLabel: "Bug report")
        return text
    }

    private static func endsDescription(_ line: String, started: Bool) -> Bool {
        if line.hasPrefix(diffMarker) {
            return true
        }
        return started && diffHeaderMarkers.contains { line.hasPrefix($0) }
    }

    /// The header lines the parser acts on. Every other header in the block —
    /// `Readline-Release:`, `Bug-Reference-ID:` — is ignored, but still has to
    /// be recognised as a header so that it ends a run of reporter
    /// continuation lines.
    private enum Header {
        case patchID(String)
        case reportedBy(String)
        case referenceURL(String)
        case descriptionStart(String)
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
        if let value = value(of: "Bug-Description:", in: line) {
            return .descriptionStart(value)
        }
        return nil
    }

    private enum Collecting {
        case none
        case reporters
        case description
    }

    /// Fields under construction, plus which multi-line block the parser is
    /// currently inside.
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
            case .descriptionStart(let value):
                // Usually empty, the text starting on the next line - but a
                // report that puts its whole description on the key's own line
                // would otherwise be read as having none at all.
                if !value.isEmpty {
                    description.append(value)
                }
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
        return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripEmail(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
