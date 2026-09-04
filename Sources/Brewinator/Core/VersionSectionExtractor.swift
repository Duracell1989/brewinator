import Foundation

/// Pulls one version's section out of a cumulative changelog whose only
/// structure is a version heading per release — the shape a macOS app's
/// bundled `ReleaseNotes.html` has (`<h1>3.0.3</h1>`, its bullets, then the
/// next version) once `HTMLTextReducer` has flattened it to text.
///
/// Distinct from `NewsRangeExtractor`, which spans a *range* of versions in a
/// prose-headed `NEWS` file. Here the newest section is the only one wanted:
/// every earlier release already has its own archived file.
enum VersionSectionExtractor {
    /// Nil when the changelog carries no section for `version` — the normal
    /// case for a cask whose app has not self-updated yet, and the caller's
    /// signal to try another source rather than archive the wrong release.
    static func section(for version: String, in text: String) -> String? {
        var collected: [String] = []
        var started = false

        for line in text.components(separatedBy: "\n") {
            guard let heading = headingVersion(of: line) else {
                if started { collected.append(line) }
                continue
            }
            if started { break }
            started = heading == version
        }

        guard started else { return nil }
        let body = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// The version a heading line announces, or nil when the line is not one.
    ///
    /// Deliberately narrow: the whole line must be the version, optionally
    /// prefixed with "v" or "Version", and it must carry at least one dot. A
    /// bullet keeps its "- " prefix through reduction, so "- Fixes 1.2.3
    /// parsing" cannot be read as a heading, and a bare "2026" in prose cannot
    /// either.
    static func headingVersion(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^(?:[Vv]ersion\s+|v)?\d+(?:\.\d+)+$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let start = trimmed.range(of: #"\d"#, options: .regularExpression) else { return nil }
        return String(trimmed[start.lowerBound...])
    }
}
