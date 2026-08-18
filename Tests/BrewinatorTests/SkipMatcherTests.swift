import Testing

@testable import Brewinator

@Suite("SkipMatcher")
struct SkipMatcherTests {
    @Test("matches an exact name")
    func matchesExactName() {
        #expect(SkipMatcher(["discord"]).matches("discord"))
        #expect(!SkipMatcher(["discord"]).matches("discordia"))
    }

    @Test("matches a `*` glob")
    func matchesGlob() {
        let matcher = SkipMatcher(["proton-*"])

        #expect(matcher.matches("proton-mail"))
        #expect(!matcher.matches("protonmail"))
    }

    @Test("an empty matcher skips nothing")
    func emptyMatchesNothing() {
        #expect(!SkipMatcher.none.matches("anything"))
    }

    /// The whole point of the type: `UserConfig` and `FileArchiveStore` used to
    /// carry their own copy of this predicate, free to drift apart.
    @Test("UserConfig.isSkipped and the matcher handed to prune agree")
    func configAndPruneAgree() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: ["lib*"], notify: false)

        for name in ["libssh2", "spotify", "node"] {
            #expect(config.isSkipped(name) == config.skipMatcher.matches(name))
        }
    }

    @Test("the matcher covers the built-ins, not just the user's own list")
    func matcherIncludesBuiltIns() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: [], notify: false)

        #expect(config.skipMatcher.matches("spotify"))
    }
}
