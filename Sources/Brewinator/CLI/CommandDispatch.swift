import ArgumentParser

/// `parseAsRoot()` does not throw for `--help`/`help` - it *returns* an
/// auxiliary command instance (ArgumentParser's internal `HelpCommand`) that
/// the caller is expected to `run()`. v0.1.0 discarded that return value, so
/// `brewinator --help` printed nothing and fell straight through into a full
/// sync against the user's real config and archive.
///
/// `--version` needs no equivalent guard: it throws `.versionRequested` out
/// of the parser, which `exit(withError:)` already handles.
enum CommandDispatch {
    /// Carries the "non-auxiliary means the root command" invariant in the type
    /// rather than a comment. The previous `as? BrewinatorCommand ?? .init()`
    /// would have silently swallowed a failed cast and run with `--update` off.
    enum Dispatch {
        case auxiliary(ParsableCommand)
        case root(BrewinatorCommand)
    }

    static func dispatch(for parsed: ParsableCommand) -> Dispatch {
        guard let root = parsed as? BrewinatorCommand else { return .auxiliary(parsed) }
        return .root(root)
    }
}
