/// Packages that publish no usable per-version notes *anywhere* - a fact about
/// the upstream, not a user preference. In code rather than seeded into a new
/// config so a release can correct it; merely noisy packages go in `skipList`.
enum BuiltInSkipList {
    /// Printed wherever a built-in bites, since a user cannot override the list
    /// locally - a fix has to ship in a release.
    static let issuesURL = "https://github.com/Duracell1989/brewinator/issues"

    /// - `ca-certificates`: a dated regeneration of Mozilla's certdata.txt by a
    ///   cron on curl.se, not a release - its homepage lists only date, SHA256
    ///   and certificate count per bundle (checked 2026-09-25).
    /// - `libunistring`: GNU publishes `NEWS` only on Savannah, which 502s
    ///   scrapers; the GitHub mirror has been frozen at 1.0 since 2022
    ///   (checked 2026-10-19).
    /// - `spotify`: desktop release notes stopped in 2015.
    /// - `discord`: no structured per-version changelog exists (checked 2026-08-04).
    /// - `whatsapp`: vendor publishes nothing per version.
    /// - Microsoft Office casks: "what's new" pages don't map to cask versions.
    static let patterns: [String] = [
        "ca-certificates",
        "discord",
        "libunistring",
        "microsoft-excel",
        "microsoft-onenote",
        "microsoft-outlook",
        "microsoft-powerpoint",
        "microsoft-word",
        "spotify",
        "whatsapp",
    ]
}
