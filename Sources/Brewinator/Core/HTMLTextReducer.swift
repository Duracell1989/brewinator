import Foundation

/// Reduces HTML to a plain-text digest: drops `<head>`, turns block tags and
/// `<li>` into breaks and bullets, strips remaining tags, decodes the handful
/// of entities the Sparkle/JetBrains feeds emit, and squeezes blank lines.
/// Tuned to those specific feeds, not a general-purpose HTML parser.
enum HTMLTextReducer {
    static func reduce(_ html: String) -> String {
        let rawLines = html.components(separatedBy: "\n")
        let joined = joinWrappedTags(rawLines)
        let withoutHead = dropHeadSection(joined)
        let stripped = withoutHead.map(stripTags)

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

    /// Drops every line from a `<head ...>`/`<head>` line through its
    /// matching `</head>` line, inclusive.
    private static func dropHeadSection(_ lines: [String]) -> [String] {
        var result: [String] = []
        var inHead = false
        for line in lines {
            if isHeadOpen(line) { inHead = true }
            if inHead {
                if isHeadClose(line) { inHead = false }
                continue
            }
            result.append(line)
        }
        return result
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

    /// True while inside `<head>...</head>` (case-insensitive, matched
    /// anywhere in the line — not anchored). Content in this section is
    /// dropped entirely.
    private static func isHeadOpen(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("<head ") || lower.contains("<head>")
    }

    private static func isHeadClose(_ line: String) -> Bool {
        line.lowercased().contains("</head>")
    }
}
