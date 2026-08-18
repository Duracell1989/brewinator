import ArgumentParser

/// `brewinator config` and its verbs. These are plain synchronous commands —
/// they run through `main.swift`'s auxiliary-command path and exit before any
/// sync work starts, so none of them ever touch Homebrew or the network.
struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show or change brewinator's settings.",
        discussion: """
            With no subcommand, prints the config file's location and current settings.

            The config file is created automatically on first run, so there is nothing to \
            initialise by hand. Editing the JSON directly works too — these verbs exist so \
            you don't have to.

            EXAMPLES:
              brewinator config
              brewinator config set archiveDirectory ~/Notes/Brew
              brewinator config set notify false
              brewinator config skip add spotify
              brewinator config skip remove spotify
            """,
        subcommands: [SetCommand.self, SkipCommand.self]
    )

    func run() throws {
        print(try ConfigEditor(store: FileConfigStore()).show())
    }
}

extension ConfigCommand {
    struct SetCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set a single setting.",
            discussion: """
                Keys: archiveDirectory (a path), notify (true/false).

                The skip list has its own verbs — see `brewinator config skip`.
                """
        )

        @Argument(help: "archiveDirectory or notify.")
        var key: String

        @Argument(help: "The new value.")
        var value: String

        func run() throws {
            print(try ConfigEditor(store: FileConfigStore()).set(key: key, value: value))
        }
    }

    struct SkipCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "skip",
            abstract: "Add or remove a package the sync should ignore.",
            discussion: """
                A pattern is an exact package name or a `*` glob, e.g. `proton-*`.

                Packages that publish no release notes at all are skipped already, \
                without being listed here — `brewinator config` shows which.
                """,
            subcommands: [AddCommand.self, RemoveCommand.self]
        )

        /// Rendered through the *root* command, not `helpMessage()` on this
        /// type: the latter renders `skip` as if it were the root, printing
        /// `USAGE: skip <subcommand>` and pointing at `skip help` - neither of
        /// which the user can type. Going through the root walks the real tree.
        static var usageText: String {
            BrewinatorCommand.helpMessage(for: ConfigCommand.SkipCommand.self)
        }

        func run() throws {
            print(Self.usageText)
        }
    }
}

extension ConfigCommand.SkipCommand {
    struct AddCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Stop fetching release notes for a package."
        )

        @Argument(help: "Package name or `*` glob.")
        var pattern: String

        func run() throws {
            print(try ConfigEditor(store: FileConfigStore()).addSkip(pattern))
        }
    }

    struct RemoveCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Start fetching release notes for a package again."
        )

        @Argument(help: "Package name or `*` glob, exactly as it was added.")
        var pattern: String

        func run() throws {
            print(try ConfigEditor(store: FileConfigStore()).removeSkip(pattern))
        }
    }
}
