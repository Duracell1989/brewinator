import ArgumentParser
import Testing

@testable import Brewinator

@Suite("ConfigCommand help")
struct ConfigCommandTests {
    /// `SkipCommand.helpMessage()` renders help as if `skip` were the root
    /// command, so `brewinator config skip` printed `USAGE: skip <subcommand>`
    /// and told the user to run `skip help` - neither of which is a command
    /// that exists. Rendering through the root walks the real command tree.
    @Test("skip usage shows the full invocation path, not a bare `skip`")
    func skipUsageShowsFullPath() {
        let usage = ConfigCommand.SkipCommand.usageText

        #expect(usage.contains("brewinator config skip"))
        #expect(!usage.contains("USAGE: skip"))
    }
}
