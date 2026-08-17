import Foundation

/// Claude Desktop (the `claude` cask, distinct from `claude-code`): no
/// forge, and Squirrel's own `RELEASES.json` `notes` field ships empty. The
/// real source is the docs changelog, titled "Release notes for Claude
/// Desktop" but nested under the Cowork docs path, appended with `.md`
/// (Mintlify) for clean `<Update label="vX" description="DATE">` blocks.
struct ClaudeDesktopChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "claude"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let url = database.claudeDesktopChangelogURL

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, let page = String(data: data, encoding: .utf8), !page.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }

        var block = Self.extractUpdateBlock(target: "v\(package.cleanCurrentVersion)", from: page)
        if block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block = Self.extractUpdateBlock(target: "", from: page)
        }
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No changelog entry found — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(block, maxLines: 60, link: url.absoluteString, linkLabel: "Full changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Extracts one `<Update label="vX" description="DATE">...</Update>`
    /// block, prefixed with a `**vX** — DATE` header. `target` empty takes
    /// the first (newest) block.
    private static func extractUpdateBlock(target: String, from text: String) -> String {
        var capturing = false
        var done = false
        var output: [String] = []

        for line in text.components(separatedBy: "\n") {
            if let (label, description) = updateOpenTag(line) {
                capturing = false
                if !done, target.isEmpty || label == target {
                    capturing = true
                    done = true
                    output.append("**\(label)** — \(description)")
                    output.append("")
                }
                continue
            }
            if line.contains("</Update>") {
                capturing = false
                continue
            }
            if capturing {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    /// Extracts `label`/`description` from an `<Update label="..."
    /// description="...">` opening tag, or nil if the line isn't one.
    private static func updateOpenTag(_ line: String) -> (label: String, description: String)? {
        guard line.contains(#"<Update label=""#) else { return nil }
        guard let label = attribute("label", in: line), let description = attribute("description", in: line) else { return nil }
        return (label, description)
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange])
    }
}
