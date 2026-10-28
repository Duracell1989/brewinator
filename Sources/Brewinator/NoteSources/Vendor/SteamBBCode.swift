import Foundation

/// The small BBCode dialect Steam news posts use (`[p]`, `[b]`, `[list]`/`[*]`,
/// `[h1]`..`[h3]`, `[url=...]`, plus `[img]`/`[carousel]` media), reduced to
/// Markdown. Media is dropped; unknown tags are dropped but their text kept.
enum SteamBBCode {
    static func markdown(from bbcode: String) -> String {
        var text = bbcode
        text = replace(text, pattern: #"\[carousel\].*?\[/carousel\]"#)
        text = replace(text, pattern: #"\[img[^\]]*\].*?\[/img\]"#)
        text = replace(text, pattern: #"\[img[^\]]*\]"#)

        var output = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let openIndex = index
            guard text[index] == "[", let close = text[index...].firstIndex(of: "]") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }
            output += rendering(tag: text[text.index(after: openIndex)..<close].lowercased(), depth: &depth)
            index = text.index(after: close)
        }

        let lines = output.components(separatedBy: "\n").map { String($0.reversed().drop { $0 == " " || $0 == "\t" }.reversed()) }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            if line == "-" { continue }
            result.append(line)
        }
        // A blank line between two bullets is an artefact of `[/p]` closing right
        // before a nested `[*]`; it would split one list into two in Markdown.
        let tight = result.enumerated().filter { offset, line in
            guard line.isEmpty, offset > 0, offset + 1 < result.count else { return true }
            return !(isBullet(result[offset - 1]) && isBullet(result[offset + 1]))
        }.map(\.element)
        return tight.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Markdown a single tag contributes, adjusting list `depth` as a side effect.
    private static func rendering(tag: String, depth: inout Int) -> String {
        let name = tag.drop { $0 == "/" }.prefix { $0 != "=" && $0 != " " }
        switch (tag.hasPrefix("/"), name) {
        case (false, "list"): depth += 1
        case (true, "list"): depth = max(0, depth - 1)
        case (false, "*"): return "\n" + String(repeating: "  ", count: max(0, depth - 1)) + "- "
        case (_, "b"), (_, "strong"): return "**"
        case (_, "i"), (_, "em"): return "*"
        case (false, "h1"), (false, "h2"), (false, "h3"): return "\n\n#### "
        case (true, "h1"), (true, "h2"), (true, "h3"), (true, "p"): return "\n"
        default: break
        }
        return ""
    }

    private static func isBullet(_ line: String) -> Bool {
        line.drop { $0 == " " }.hasPrefix("- ")
    }

    private static func replace(_ text: String, pattern: String) -> String {
        text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }
}
