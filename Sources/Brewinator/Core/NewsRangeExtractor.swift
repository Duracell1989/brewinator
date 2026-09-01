import Foundation

/// The heading convention a project's `NEWS` file uses. A case owns both how a
/// heading line is recognised and how the version is read out of it — the two
/// rules are inseparable, and one regex spanning both styles reads worse than
/// two small ones.
enum NewsHeadingStyle: String, Sendable, Equatable, Codable {
    /// GNOME: "Overview of changes in 1.58.2, 05-08-2026", "Overview of
    /// Changes in GLib 2.88.0", "Overview of changes leading to 11.0.0".
    case gnome

    /// GnuPG: "Noteworthy changes in version 2.2.0 (2026-08-31)  [C47/A2/R0]".
    /// Shared by every project on the `gpg/*` mirrors.
    case gnupg

    /// The version a heading line announces, or nil when the line is not a
    /// heading in this style.
    func version(of line: String) -> String? {
        switch self {
        case .gnome:
            return Self.gnomeVersion(of: line)
        case .gnupg:
            return Self.gnupgVersion(of: line)
        }
    }

    /// Headings vary ("...in 1.58.2, 05-08-2026", "...in GLib 2.88.0",
    /// "...leading to 11.0.0"), so the version is the last whitespace-separated
    /// token once the prefix and any trailing ", <date>" are stripped.
    private static func gnomeVersion(of line: String) -> String? {
        guard var rest = suffix(of: line, afterPattern: #"^Overview of [Cc]hanges (in|leading to)[ \t]+"#) else {
            return nil
        }
        if let commaIndex = rest.firstIndex(of: ",") {
            rest = String(rest[rest.startIndex..<commaIndex])
        }
        let tokens = rest.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return tokens.last.map(String.init)
    }

    /// Mirror image of the GNOME rule: the version is the *first* token after
    /// the prefix, because everything after it — the "(2026-08-31)" date, the
    /// optional "[C47/A2/R0]" libtool triple — is trailing noise.
    private static func gnupgVersion(of line: String) -> String? {
        guard let rest = suffix(of: line, afterPattern: #"^Noteworthy changes in version[ \t]+"#) else {
            return nil
        }
        let tokens = rest.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return tokens.first.map(String.init)
    }

    private static func suffix(of line: String, afterPattern pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), let matchRange = Range(match.range, in: line) else {
            return nil
        }
        return String(line[matchRange.upperBound...])
    }
}

/// Extracts a *range* of version sections out of a `NEWS` file, from `newest`
/// down to `oldest` (exclusive). The range matters: pango 1.58.2 says only
/// "No changes" and the substance is in 1.58.1.
///
/// Starting at `newest` rather than at the top of the file is also what keeps
/// an in-development section out of the notes — every GnuPG NEWS file carries
/// an "(unreleased)" heading above the newest shipped one.
enum NewsRangeExtractor {
    static func extract(from text: String, newest: String, oldest: String, style: NewsHeadingStyle) -> String {
        var started = false
        var output: [String] = []

        for line in text.components(separatedBy: "\n") {
            if let version = style.version(of: line) {
                if !started {
                    if newest.isEmpty || version == newest {
                        started = true
                    } else {
                        continue
                    }
                } else if !oldest.isEmpty && version == oldest {
                    break
                }
            }
            if started {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}
