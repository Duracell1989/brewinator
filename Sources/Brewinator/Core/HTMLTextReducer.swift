import Foundation

/// Reduces HTML to a plain-text digest: drops `<head>`, `<style>` and
/// `<script>` sections, turns block tags and `<li>` into breaks and bullets,
/// strips remaining tags, decodes the handful of entities the Sparkle/JetBrains
/// feeds emit, and squeezes blank lines.
/// Tuned to those specific feeds, not a general-purpose HTML parser.
enum HTMLTextReducer {
    static func reduce(_ html: String) -> String {
        let rawLines = html.components(separatedBy: "\n")
        let joined = joinWrappedTags(rawLines)
        let withoutNoise = dropSections(joined)
        let stripped = withoutNoise.map(stripTags)

        // The substitutions above inserted newlines inside single elements;
        // split those into true per-line records before trimming.
        let expanded = stripped.flatMap { $0.components(separatedBy: "\n") }
        let trimmed = expanded.map { $0.trimmingCharacters(in: .whitespaces) }
        return squeezeBlankLines(trimmed)
    }

    /// Joins lines whose `<` count exceeds their `>` count until they balance -
    /// Blogger pretty-prints anchors across lines, which would otherwise leave
    /// literal fragments after per-line tag stripping.
    private static func joinWrappedTags(_ lines: [String]) -> [String] {
        var result: [String] = []
        var buffer = ""
        for line in lines {
            buffer = buffer.isEmpty ? line : buffer + " " + line
            let opens = countTagOpens(buffer)
            let closes = buffer.filter { $0 == ">" }.count
            if opens > closes { continue }
            result.append(buffer)
            buffer = ""
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
        return result
    }

    /// Counts only `<` that plausibly start a tag: followed by a letter, `/`,
    /// `!` or `?`. A bare `<` in prose ("now <10ms") would otherwise read as an
    /// unclosed tag and merge unrelated lines until the count rebalanced.
    private static func countTagOpens(_ text: String) -> Int {
        let chars = Array(text)
        var count = 0
        for index in chars.indices where chars[index] == "<" {
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            if let next, next.isLetter || next == "/" || next == "!" || next == "?" {
                count += 1
            }
        }
        return count
    }

    /// Content-free sections: their text is markup or code, never release
    /// notes. `<style>` earns its place here because an app's bundled
    /// `ReleaseNotes.html` inlines a stylesheet *outside* any `<head>`, and CSS
    /// survives tag stripping intact (it contains no tags to strip).
    private static let droppedSections = ["head", "style", "script"]

    /// Drops every line from an opening `<tag ...>`/`<tag>` line through its
    /// matching `</tag>` line, inclusive, for each of `droppedSections`. A
    /// section opened and closed on one line drops that line too.
    private static func dropSections(_ lines: [String]) -> [String] {
        var result: [String] = []
        var openTag: String?
        for line in lines {
            if openTag == nil {
                openTag = droppedSections.first { containsOpen(line, tag: $0) }
            }
            guard let tag = openTag else {
                result.append(line)
                continue
            }
            if line.lowercased().contains("</\(tag)>") { openTag = nil }
        }
        return result
    }

    /// True when the line opens `tag` — `<tag>` or `<tag attr=...>`, matched
    /// anywhere in the line, never `<tagfoo>` and never an attribute that
    /// merely shares the name (`<p style="...">` does not open `<style>`).
    private static func containsOpen(_ line: String, tag: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("<\(tag)>") || lower.contains("<\(tag) ") || lower.contains("<\(tag)\t")
    }

    private static func stripTags(_ line: String) -> String {
        var result = line
        result = replace(result, pattern: "<li>|<li [^>]*>", with: "- ", caseInsensitive: true)
        result = replace(result, pattern: "</li>", with: "\n", caseInsensitive: true)
        result = replace(result, pattern: "<br[^>]*>", with: "\n", caseInsensitive: true)
        result = replace(result, pattern: "</h[1-6]>|</p>|</ul>|</div>", with: "\n", caseInsensitive: true)
        result = replace(result, pattern: "<[^>]+>", with: "")

        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = replace(result, pattern: "&#0?39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }

    /// Content lines pass through unchanged; consecutive blank lines collapse
    /// to one.
    private static func squeezeBlankLines(_ lines: [String]) -> String {
        var out: [String] = []
        var previousWasBlank = false
        for line in lines {
            if line.isEmpty {
                if !previousWasBlank { out.append(line) }
                previousWasBlank = true
            } else {
                out.append(line)
                previousWasBlank = false
            }
        }
        return out.joined(separator: "\n")
    }

    private static func replace(_ text: String, pattern: String, with template: String, caseInsensitive: Bool = false) -> String {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
