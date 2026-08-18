import ArgumentParser
import Foundation

// Argument parsing stays synchronous (ArgumentParser's own machinery); the
// actual sync work runs via top-level `await` below rather than through
// AsyncParsableCommand.main() — its runtime async-bridging check is broken
// on the current beta Swift 6.4/Xcode 27 toolchain (always reports "needs
// availability annotation" even with the exact annotation it suggests).
let command: BrewinatorCommand
do {
    let parsed = try BrewinatorCommand.parseAsRoot()
    if var auxiliary = CommandDispatch.auxiliaryCommand(for: parsed) {
        // `--help`/`help`: running it throws the help request, which
        // `exit(withError:)` renders and exits 0 on. Discarding it instead
        // is what made v0.1.0's `--help` run a full sync.
        try auxiliary.run()
        BrewinatorCommand.exit()
    }
    // Non-auxiliary is the root command by construction — see CommandDispatch.
    command = parsed as? BrewinatorCommand ?? BrewinatorCommand()
} catch {
    BrewinatorCommand.exit(withError: error)
}

let configStore = FileConfigStore()
let config: UserConfig
do {
    config = try configStore.load()
} catch let error as ConfigStoreError {
    switch error {
    case .notFound:
        print("No config found at \(FileConfigStore.defaultURL.path) — create one first, e.g.:")
    case .invalid(let path, let reason):
        print("Config at \(path) is invalid (\(reason)) — expected JSON like:")
    }
    print(
        """
        {
          "archiveDirectory": "/path/to/your/notes/archive",
          "skipList": [],
          "notify": false
        }
        """
    )
    BrewinatorCommand.exit(withError: ExitCode.failure)
}

let brewClient = ProcessBrewClient()
let logger = StderrLogger()

if command.update {
    print("Updating Homebrew...")
    do {
        try await brewClient.update()
    } catch {
        // Degrade to the pre-flag behaviour — sync against whatever metadata
        // Homebrew already had — rather than losing the whole run to a
        // transient network failure at 09:00.
        logger.warn("brew update failed (\(error)) — continuing with existing metadata")
    }
    print("")
}

let httpFetcher = URLSessionHTTPFetcher()
let database = ResolutionDatabase.live

// Config-map vendor classes first (JetBrains/Sparkle/TagCompare/Markdown),
// then the seven bespoke vendor one-offs, then generic forge resolution.
// Order among the vendor one-offs doesn't matter (each `canHandle` is an
// exact, mutually exclusive name match), and neither does order between the
// two forge sources (mutually exclusive by dialect).
let sync = BrewNotesSync(
    brewClient: brewClient,
    archiveStore: FileArchiveStore(directory: URL(fileURLWithPath: config.archiveDirectory)),
    resolver: Resolver(sources: [
        JetBrainsProducts(httpFetcher: httpFetcher, database: database),
        SparkleAppcast(httpFetcher: httpFetcher, database: database),
        TagCompare(httpFetcher: httpFetcher, database: database),
        MarkdownChangelog(httpFetcher: httpFetcher, database: database),
        FirefoxReleaseNotes(httpFetcher: httpFetcher, database: database),
        FFmpegChangelog(httpFetcher: httpFetcher, database: database),
        DotnetSdkReleaseNotes(httpFetcher: httpFetcher, database: database),
        ClaudeDesktopChangelog(httpFetcher: httpFetcher, database: database),
        ObsidianChangelog(httpFetcher: httpFetcher, database: database),
        WindowsAppChangelog(httpFetcher: httpFetcher, database: database),
        AndroidStudioBlog(httpFetcher: httpFetcher, database: database),
        ForgeReleases(httpFetcher: httpFetcher, database: database),
        GitLabReleases(httpFetcher: httpFetcher, database: database),
    ]),
    config: config,
    logger: logger
)

do {
    let result = try await sync.run()
    print(OutdatedListing.render(result.outdated))

    if !result.newItems.isEmpty {
        print("")
        print("New release notes (\(result.newItems.count)):")
        for item in result.newItems {
            print("  - \(item.name) \(item.version)")
        }
        print("See: \(config.archiveDirectory)")
    } else if !result.outdated.isEmpty {
        print("")
        print("No new release notes.")
    }
} catch {
    BrewinatorCommand.exit(withError: error)
}
