import ArgumentParser

/// `parseAsRoot()` does not throw for `--help`/`help` - it *returns* an
/// auxiliary command the caller must `run()`. Discarding it (v0.1.0) made
/// `--help` print nothing and fall through into a full sync. `--version` needs
/// no equivalent guard: it throws `.versionRequested`, which the parser handles.
enum CommandDispatch {
    /// Keeps "non-auxiliary means the root command" in the type, where a failed
    /// cast can't be silently swallowed into a default-constructed command.
    enum Dispatch {
        case auxiliary(ParsableCommand)
        case root(BrewinatorCommand)
    }

    static func dispatch(for parsed: ParsableCommand) -> Dispatch {
        guard let root = parsed as? BrewinatorCommand else { return .auxiliary(parsed) }
        return .root(root)
    }
}
