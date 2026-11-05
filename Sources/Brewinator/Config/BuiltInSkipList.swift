/// Packages that publish no usable per-version notes *anywhere* - a fact about
/// the upstream, not a user preference. In code rather than seeded into a new
/// config so a release can correct it; merely noisy packages go in `skipList`.
enum BuiltInSkipList {
    /// Printed wherever a built-in bites, since a user cannot override the list
    /// locally - a fix has to ship in a release.
    static let issuesURL = "https://github.com/Duracell1989/brewinator/issues"

    struct Entry: Sendable, Equatable {
        let pattern: String
        /// Shown in the no-notes summary file, so keep it to one short clause.
        let reason: String
    }

    static let entries: [Entry] = [
        // A dated regeneration of Mozilla's certdata.txt by a cron on curl.se,
        // not a release - its homepage lists only date, SHA256 and certificate
        // count per bundle (checked 2026-09-25).
        Entry(pattern: "ca-certificates", reason: "a dated regeneration of Mozilla's certificate bundle, not a release"),
        // The Sparkle appcast items carry no `<description>` or notes link, there
        // is no Mac changelog page (`/changelog` and `/release-notes` 404), and
        // the only changelog is for the API (checked 2026-10-22).
        Entry(pattern: "deepl", reason: "no Mac changelog; the only one published covers the API"),
        // No structured per-version changelog exists (checked 2026-08-04).
        Entry(pattern: "discord", reason: "no structured per-version changelog"),
        // GNU publishes `NEWS` only on Savannah, which 502s scrapers; the GitHub
        // mirror has been frozen at 1.0 since 2022 (checked 2026-10-19).
        Entry(pattern: "libunistring", reason: "NEWS only on Savannah, which blocks scrapers; GitHub mirror is frozen"),
        // "What's new" pages don't map to cask versions.
        Entry(pattern: "microsoft-excel", reason: "what's-new pages don't map to cask versions"),
        Entry(pattern: "microsoft-onenote", reason: "what's-new pages don't map to cask versions"),
        Entry(pattern: "microsoft-outlook", reason: "what's-new pages don't map to cask versions"),
        Entry(pattern: "microsoft-powerpoint", reason: "what's-new pages don't map to cask versions"),
        Entry(pattern: "microsoft-word", reason: "what's-new pages don't map to cask versions"),
        // Desktop release notes stopped in 2015.
        Entry(pattern: "spotify", reason: "desktop release notes stopped in 2015"),
        Entry(pattern: "whatsapp", reason: "vendor publishes nothing per version"),
    ]

    static let patterns: [String] = entries.map(\.pattern)

    /// The first entry whose pattern matches `name`, as the skip decision does.
    static func reason(for name: String) -> String? {
        entries.first { SkipMatcher([$0.pattern]).matches(name) }?.reason
    }
}
