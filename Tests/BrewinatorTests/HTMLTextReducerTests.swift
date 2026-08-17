import Testing

@testable import Brewinator

@Suite("HTMLTextReducer")
struct HTMLTextReducerTests {
    @Test("drops the head section entirely")
    func dropsHead() {
        // Head open/close must be on their own lines: the drop is line-based,
        // so content sharing a line with "</head>" would be dropped too — not
        // a realistic shape for the real feeds this is tuned to (see the
        // fixture-driven test below).
        let result = HTMLTextReducer.reduce("<head>\n<title>X</title>\n</head>\n<body><p>Hello</p></body>")
        #expect(!result.contains("title"))
        #expect(!result.contains("X"))
        #expect(result.contains("Hello"))
    }

    @Test("li items become bullets, closing li becomes a line break")
    func liToBullets() {
        let result = HTMLTextReducer.reduce("<ul><li>One</li><li>Two</li></ul>")
        #expect(result.contains("- One"))
        #expect(result.contains("- Two"))
    }

    @Test("br and block-closing tags become line breaks")
    func blockTagsToBreaks() {
        let result = HTMLTextReducer.reduce("<p>First<br>Second</p><p>Third</p>")
        let lines = result.components(separatedBy: "\n")
        #expect(lines.contains("First"))
        #expect(lines.contains("Second"))
        #expect(lines.contains("Third"))
    }

    @Test("decodes the entities these feeds emit")
    func decodesEntities() {
        let result = HTMLTextReducer.reduce("<p>A &amp; B &lt;tag&gt; &quot;quoted&quot; &#39;it&#39;s&#39;&nbsp;end</p>")
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "A & B <tag> \"quoted\" 'it's' end")
    }

    @Test("joins a tag whose closing angle bracket wraps to the next line")
    func joinsWrappedTags() {
        let html = "<p>Before <a href=\"x\"\n>Link</a> after</p>"
        let result = HTMLTextReducer.reduce(html)
        #expect(result.contains("Before Link after"))
    }

    @Test("consecutive blank lines collapse to one")
    func squeezesBlankLines() {
        let result = HTMLTextReducer.reduce("<p>One</p>\n\n\n<p>Two</p>")
        #expect(!result.contains("\n\n\n"))
        #expect(!result.contains("\n\n\n\n"))
    }

    @Test("a literal '<' followed by a digit (e.g. 'now <10ms') is prose, not an unclosed tag, and must not swallow later lines")
    func literalLessThanDigitDoesNotSwallowLaterLines() {
        let html = "<p>Latency now <10ms after the fix</p>\n<p>Second paragraph should stay separate</p>"
        let result = HTMLTextReducer.reduce(html)
        #expect(result.contains("Latency now <10ms after the fix"))
        #expect(result.contains("Second paragraph should stay separate"))
    }

    @Test("reduces the frozen Vivaldi release-notes fixture to readable text with no tags left")
    func realFixture() throws {
        let html = try Fixture.string("sparkle-notes-sample", extension: "html")
        let result = HTMLTextReducer.reduce(html)
        #expect(result.contains("Changelog since Vivaldi"))
        #expect(result.contains("- [Chromium] Update to"))
        // The decoded &lt;...&gt; blog-URL callout legitimately contains
        // angle brackets — assert no *tags* remain, not "no '<' anywhere".
        #expect(!result.contains("<h2>"))
        #expect(!result.contains("<li>"))
        #expect(!result.contains("<style"))
        #expect(!result.contains("<ul"))
    }
}
