import ArgumentParser

/// Named `BrewinatorCommand`, not `Brewinator`, so it can't collide with the
/// module name when the test target refers to it.
struct BrewinatorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brewinator",
        abstract: "Fetch and archive release notes for outdated Homebrew packages.",
        discussion: """
            Run with no subcommand to list what's outdated and archive release notes for \
            anything new. The config file is created on first run; `brewinator config` \
            shows where it lives and what's in it.
            """,
        version: "0.9.2",
        subcommands: [ConfigCommand.self]
    )

    @Flag(
        name: .long,
        help: "Refresh Homebrew's package metadata (`brew update`) before checking what's outdated."
    )
    var update: Bool = false
}
