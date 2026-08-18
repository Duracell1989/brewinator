import ArgumentParser
import Testing

@testable import Brewinator

@Suite("CommandDispatch")
struct CommandDispatchTests {
    @Test("--help parses to an auxiliary command, not the root — v0.1.0 discarded that result and fell through into a real sync")
    func helpFlagYieldsAuxiliaryCommand() throws {
        let parsed = try BrewinatorCommand.parseAsRoot(["--help"])

        guard case .auxiliary = CommandDispatch.dispatch(for: parsed) else {
            Issue.record("expected an auxiliary command")
            return
        }
    }

    @Test("no arguments parses to the root command, so the sync proceeds")
    func noArgumentsYieldsRootCommand() throws {
        let parsed = try BrewinatorCommand.parseAsRoot([])

        guard case .root = CommandDispatch.dispatch(for: parsed) else {
            Issue.record("expected the root command")
            return
        }
    }

    @Test("--version throws rather than returning a command, so it can never fall through to the sync")
    func versionFlagThrows() {
        #expect(throws: (any Error).self) {
            _ = try BrewinatorCommand.parseAsRoot(["--version"])
        }
    }

    /// The dispatch used to end in `parsed as? BrewinatorCommand ?? .init()`,
    /// which would have swallowed a failed cast and run with `--update` off -
    /// syncing against stale Homebrew metadata with no error and no warning.
    @Test("--update survives dispatch rather than being replaced by a default command")
    func updateFlagSurvivesDispatch() throws {
        let parsed = try BrewinatorCommand.parseAsRoot(["--update"])

        guard case .root(let root) = CommandDispatch.dispatch(for: parsed) else {
            Issue.record("expected the root command")
            return
        }
        #expect(root.update)
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
