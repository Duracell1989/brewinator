import Foundation

/// Sparkle-appcast notes for a cask whose feed is registered in
/// `ResolutionDatabase.sparkleFeeds`. Everything about reading a feed lives in
/// `SparkleAppcastReader`, shared with the feeds `AppBundleReleaseNotes`
/// discovers from an installed app.
struct SparkleAppcast: NoteSource {
    private let database: ResolutionDatabase
    private let reader: SparkleAppcastReader

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.database = database
        reader = SparkleAppcastReader(httpFetcher: httpFetcher)
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.sparkleFeeds[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let feed = database.sparkleFeeds[package.name] else {
            return .success(Resolver.noForgeDetected)
        }
        return await reader.notes(feed: feed, targetVersion: package.cleanCurrentVersion)
    }
}
