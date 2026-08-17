import Foundation

/// Windows App: a Microsoft Learn vendor page, multi-platform/tabbed. The
/// macOS section is `<section id="tabpanel_2_macos">`, bounded by the next
/// `tabpanel_2_*` sibling. Headings read "Version X.Y.Z (build)" and the
/// build number isn't in the cask version, so matching is by prefix, newest
/// block as fallback.
struct WindowsAppChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "windows-app"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let url = database.windowsAppURL

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }

        guard let macSection = Self.macOSSection(of: html), !macSection.isEmpty else {
            return .success(ReleaseNotes(markdown: "_Could not locate the macOS version-history section — \(url.absoluteString)_\n\n"))
        }

        var block = Self.extractBlock(target: "Version \(package.cleanCurrentVersion)", from: macSection)
        if block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block = Self.extractBlock(target: "", from: macSection)
        }
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No changelog entry found — \(url.absoluteString)_\n\n"))
        }

        let text = HTMLTextReducer.reduce(block)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Changelog block had no readable text — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(text, maxLines: 40, link: url.absoluteString, linkLabel: "Full changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Lines from `<section id="tabpanel_2_macos"` up to (not including) the
    /// next `<section id="tabpanel_2_` sibling.
    private static func macOSSection(of html: String) -> String? {
        var capturing = false
        var output: [String] = []
        for line in html.components(separatedBy: "\n") {
            if line.contains(#"<section id="tabpanel_2_macos"#) {
                capturing = true
                output.append(line)
                continue
            }
            if capturing, line.contains(#"<section id="tabpanel_2_"#) {
                break
            }
            if capturing {
                output.append(line)
            }
        }
        return output.isEmpty ? nil : output.joined(separator: "\n")
    }

    /// Single-pass state machine over `<h3 ` boundary lines: each one closes
    /// whatever was being captured and, if its title has the target prefix
    /// (first match only, or any title when `target` is empty), starts a new
    /// capture. The `<h3>` line itself is never part of the captured body.
    private static func extractBlock(target: String, from section: String) -> String {
        var capturing = false
        var done = false
        var output: [String] = []

        for line in section.components(separatedBy: "\n") {
            if let title = h3Title(of: line) {
                capturing = false
                if !done, target.isEmpty || title.hasPrefix(target) {
                    capturing = true
                    done = true
                }
                continue
            }
            if capturing {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    /// Extracts the title text from an `<h3 ...>Title</h3>` line, or nil if
    /// the line isn't an `<h3 ` opener. Strips up to the first `>`, then
    /// drops everything from `</h3>` onward — assumes a single-line heading.
    private static func h3Title(of line: String) -> String? {
        guard line.contains("<h3 ") else { return nil }
        guard let openEnd = line.firstIndex(of: ">") else { return nil }
        var title = String(line[line.index(after: openEnd)...])
        if let closeRange = title.range(of: "</h3>") {
            title = String(title[title.startIndex..<closeRange.lowerBound])
        }
        return title
    }
}
