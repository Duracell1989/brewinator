extension String {
    /// The first `n` newline-delimited lines, joined back together.
    func firstLines(_ count: Int) -> String {
        components(separatedBy: "\n").prefix(count).joined(separator: "\n")
    }

    var lineCount: Int {
        components(separatedBy: "\n").count
    }
}

/// Builds a note body in the common shape most handlers use: capped
/// content, a blank line, an optional link line, a trailing blank line.
enum MarkdownSection {
    static func body(_ content: String, maxLines: Int, link: String? = nil, linkLabel: String? = nil) -> String {
        var text = content.firstLines(maxLines)
        text += "\n\n"
        if let link, let linkLabel {
            text += "[\(linkLabel)](\(link))\n\n"
        }
        return text
    }
}
