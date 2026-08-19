import ArgumentParser
import Foundation

// Sync work runs via top-level `await` below rather than through
// AsyncParsableCommand.main(): its runtime async-bridging check is broken on
// the beta Swift 6.4/Xcode 27 toolchain, demanding an availability annotation
// it already has.
let command: BrewinatorCommand
do {
    switch CommandDispatch.dispatch(for: try BrewinatorCommand.parseAsRoot()) {
    case .auxiliary(var auxiliary):
        // Running it throws the help request, which `exit(withError:)` renders
        // and exits 0 on. `validate()` first, matching the order
        // `ParsableCommand.main()` uses, since this dispatch replaces it.
        try auxiliary.validate()
        try auxiliary.run()
        BrewinatorCommand.exit()
    case .root(let root):
        command = root
    }
} catch {
    BrewinatorCommand.exit(withError: error)
}

let configStore = FileConfigStore()
let config: UserConfig
do {
    let loaded = try configStore.loadOrCreate(default: UserConfig.default)
    config = loaded.config
    if loaded.created {
        print("First run - wrote a default config to \(configStore.path)")
        print("Archiving to \(config.archiveDirectory) - change it with:")
        print("  brewinator config set archiveDirectory <path>")
        print("")
    }
} catch {
    // Only a malformed or unwritable config reaches here, and it is never
    // overwritten - the user's skip list outweighs a self-healing file.
    // Untyped catch: `save` failures arrive as raw `CocoaError`s, and an
    // unmatched error at top level traps the process instead of printing.
    print(error)
    if let configError = error as? ConfigStoreError, case .invalid = configError {
        print("")
        print("Expected JSON like:")
        print(
            """
            {
              "archiveDirectory": "/path/to/your/notes/archive",
              "skipList": [],
              "notify": false
            }
            """
        )
    }
    BrewinatorCommand.exit(withError: ExitCode.failure)
}

let brewClient = ProcessBrewClient()
let logger = StderrLogger()

if command.update {
    print("Updating Homebrew...")
    do {
        try await brewClient.update()
    } catch {
        // Degrade to syncing against whatever metadata Homebrew already had,
        // rather than losing the whole 09:00 run to a transient network failure.
        logger.warn("brew update failed (\(error)) - continuing with existing metadata")
    }
    print("")
}

let httpFetcher = URLSessionHTTPFetcher()
let database = ResolutionDatabase.live

// Config-map vendor classes first, then the bespoke vendor one-offs, then
// generic forge resolution. Order within each group is irrelevant - every
// `canHandle` is an exact, mutually exclusive match.
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
    // The listing prints from inside the sync, before prune and the first
    // fetch - see `BrewNotesSync.run(onOutdated:)`.
    let result = try await sync.run { print(OutdatedListing.render($0)) }

    if !result.trashedFiles.isEmpty {
        print("")
        print("Moved to Trash (\(result.trashedFiles.count)):")
        for file in result.trashedFiles {
            print("  - \(file.lastPathComponent)")
        }
    }

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
