import ArgumentParser
import Testing

@testable import Brewinator

@Suite("CommandDispatch")
struct CommandDispatchTests {
    @Test("--help parses to an auxiliary command, not the root — v0.1.0 discarded that result and fell through into a real sync")
    func helpFlagYieldsAuxiliaryCommand() throws {
        let parsed = try BrewinatorCommand.parseAsRoot(["--help"])

        #expect(CommandDispatch.auxiliaryCommand(for: parsed) != nil)
    }

    @Test("no arguments parses to the root command, so the sync proceeds")
    func noArgumentsYieldsRootCommand() throws {
        let parsed = try BrewinatorCommand.parseAsRoot([])

        #expect(CommandDispatch.auxiliaryCommand(for: parsed) == nil)
    }

    @Test("--version throws rather than returning a command, so it can never fall through to the sync")
    func versionFlagThrows() {
        #expect(throws: (any Error).self) {
            _ = try BrewinatorCommand.parseAsRoot(["--version"])
        }
    }

    @Test("--update parses into the flag")
    func updateFlagParses() throws {
        let command = try BrewinatorCommand.parse(["--update"])

        #expect(command.update)
    }

    @Test("the flag defaults off — a bare run must never mutate Homebrew state")
    func updateFlagDefaultsOff() throws {
        let command = try BrewinatorCommand.parse([])

        #expect(!command.update)
    }
}
