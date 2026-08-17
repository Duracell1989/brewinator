import ArgumentParser
import Foundation

struct Brewinator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brewinator",
        abstract: "Fetch and archive release notes for outdated Homebrew packages."
    )
}

// Argument parsing stays synchronous (ArgumentParser's own machinery); the
// actual sync work runs via top-level `await` below rather than through
// AsyncParsableCommand.main() — its runtime async-bridging check is broken
// on the current beta Swift 6.4/Xcode 27 toolchain (always reports "needs
// availability annotation" even with the exact annotation it suggests).
do {
    _ = try Brewinator.parseAsRoot()
} catch {
    Brewinator.exit(withError: error)
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
    Brewinator.exit(withError: ExitCode.failure)
}

let httpFetcher = URLSessionHTTPFetcher()
let database = ResolutionDatabase.live

// Config-map vendor classes first (JetBrains/Sparkle/TagCompare/Markdown),
// then the seven bespoke vendor one-offs, then generic forge resolution.
// Order among the vendor one-offs doesn't matter (each `canHandle` is an
// exact, mutually exclusive name match), and neither does order between the
// two forge sources (mutually exclusive by dialect).
let sync = BrewNotesSync(
    brewClient: ProcessBrewClient(),
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
    config: config
)

do {
    let result = try await sync.run()
    if result.newItems.isEmpty {
        print("No new release notes.")
    } else {
        print("New release notes (\(result.newItems.count)):")
        for item in result.newItems {
            print("  - \(item.name) \(item.version)")
        }
        print("See: \(config.archiveDirectory)")
    }
} catch {
    Brewinator.exit(withError: error)
}
