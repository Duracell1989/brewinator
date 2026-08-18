/// Packages that publish no usable per-version release notes *anywhere* —
/// skipping them is a fact about the upstream, not a user preference, so it
/// ships with the tool instead of landing in everyone's config file. Kept in
/// code (not seeded into a new config) so a release can correct it; a config
/// seeded once would freeze this list on the day of install.
///
/// Entries only belong here when there is genuinely nothing to fetch. A
/// package a user finds merely noisy goes in their own `skipList`.
enum BuiltInSkipList {
    /// - `spotify`: desktop release notes stopped in 2015.
    /// - `discord`: no structured per-version changelog exists (checked 2026-08-04).
    /// - `whatsapp`: vendor publishes nothing per version.
    /// - Microsoft Office casks: "what's new" pages don't map to cask versions.
    static let patterns: [String] = [
        "discord",
        "microsoft-excel",
        "microsoft-onenote",
        "microsoft-outlook",
        "microsoft-powerpoint",
        "microsoft-word",
        "spotify",
        "whatsapp",
    ]
}
