# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions before `1.0.0` may change behaviour in a minor bump.

The release workflow reads the section matching the tag it is building, and fails if there isn't one.

## [Unreleased]

### Changed

- The `brewinator-notifier` cask now loads the notifier agent while it installs, instead of leaving it dormant until brewinator next runs. It ships an `install-agent.sh` inside `BrewinatorNotify.zip` and runs it as an `installer script:`, which - unlike the declarative install steps - runs outside Homebrew's sandbox, where launchd accepts job submission (Homebrew/brew#23891). The script also receives the cask's real app directory, so the plist no longer hard-codes `/Applications`. Homebrew runs installer artifacts before it moves the app, so the job first fails with exit 78 and `KeepAlive` picks it up once the app lands, about a throttle interval later. `NotifierAgentActivation` stays as the fallback for installs predating this and for an agent unloaded by hand.

## [0.9.0] - 2026-09-08

### Added

- Release notes for `poppler`, read from its in-tree `NEWS` file. Its forge is now resolved (see below), but gitlab.freedesktop.org publishes zero release objects for the project, so that path can only ever report "No releases published" - the same trade already made for the GnuPG mirrors. The `NEWS` file is the only machine-readable source that carries the notes.
- A `NEWS` heading style for poppler's `Release 26.09.0:` format, including the 2005-era `Release 0.2.0  (Tue Apr  5 12:32:10 EDT 2005)` and `Release 0.1 - no date yet` shapes that are still in the same cumulative file.
- The resident notification agent is now loaded automatically when its plist is on disk but nothing has registered it with launchd. The `brewinator-notifier` cask writes the plist and cannot load it: Homebrew's declarative install steps run inside a sandbox, and launchd refuses job submission from any sandboxed process - even a fully permissive `sandbox-exec -p '(version 1)(allow default)'` profile fails with `Bootstrap failed: 5: Input/output error`. Until now a fresh cask install therefore posted to nobody until the next login, because `ResidentAgentNotifier` drops its banner in silence when the agent isn't running.

### Changed

- Forge repo resolution now also scans the formula's `head` URL, after the stable URL and the homepage. A project that publishes its tarballs and its docs on its own domain names its forge nowhere else, so every one of them archived as "No forge repo detected" - on this machine cairo, ffmpeg, libidn2, libpng, libssh2, libuv, node, pango and poppler. The head URL is checked last because it names the development remote, which for a fork or a mirror need not be where the releases are published.
- `node` and `pango` no longer need hand-written `repoOverrides` entries - head-URL scanning resolves both to the repo the override named. `signal` keeps its override: casks have no head URL at all.

## [0.8.0] - 2026-09-04

### Added

- A last-resort note source that reads the cask's own installed `.app`, for vendors who publish no changelog a forge, feed or vendor page can reach. It takes the requested version's section out of `Contents/Resources/ReleaseNotes.html` (the cumulative changelog Sparkle shows in its update dialog), and otherwise follows `SUFeedURL` from `Contents/Info.plist` to the app's own appcast - discovered from the bundle, with no database entry needed. It runs last, so it can only ever replace the "No forge repo detected" placeholder. On this machine it covers `proton-drive` (bundled changelog; Proton publishes per-version notes nowhere else), `protonvpn` and `telegram` (discovered feeds).
- Sparkle appcasts whose items carry their notes inline in `<description>` as CDATA HTML are now read. Only `sparkle:releaseNotesLink` was understood before, so ProtonVPN, QLMarkdown and Telegram-style feeds resolved to "No release-notes link in the Sparkle feed" even though the notes were right there in the feed.

### Changed

- Sparkle items are also matched on the version published as an `<enclosure>` attribute, not just as a child element. ProtonVPN and Telegram publish it only there, so the match previously fell back to the newest item - which would have archived a beta's notes under the requested version.
- A channel-level `<description>` is no longer read as the first item's notes.
- HTML reduction drops `<style>` and `<script>` sections wherever they appear, not just inside `<head>`. An app's bundled `ReleaseNotes.html` inlines its stylesheet outside `<head>`, and CSS survives tag stripping intact.
- The "nothing in this feed" message is now "No release notes in the Sparkle feed", since a feed can carry notes two ways and neither being present is what it reports.

## [0.7.0] - 2026-09-01

### Added

- Release notes for the whole GnuPG family: gnupg, gpgme, gpgmepp, libassuan, libgcrypt, libgpg-error, libksba, npth and pinentry. They are read from each project's in-tree `NEWS` file, because their canonical host (git.gnupg.org) is intermittently offline behind an anti-scraper 429 and the official `gpg/*` GitHub mirrors publish no releases at all. All nine used to archive as "No forge repo detected".
- Release notes for `nss`, read from the Firefox source docs.

### Changed

- The NEWS-file reader that GitLab packages already used for GNOME-style stub descriptions is now shared, and understands GnuPG's heading format alongside GNOME's. Behaviour for GNOME packages is unchanged.

## [0.6.1] - 2026-08-25

### Fixed

- `BrewinatorNotify.app` (the resident agent from `brewinator-notifier`) crashed on every single launch once installed as a real `KeepAlive` LaunchAgent. Its authorization and notification-post completion handlers were written as closures inline inside an `@MainActor` method, which inferred `@MainActor` isolation from that lexical nesting - but `UNUserNotificationCenter` actually invokes both off the main thread, and Swift 6's runtime isolation check trapped the mismatch every time. Moved both to plain top-level functions, which have no isolation to infer.

## [0.6.0] - 2026-08-24

### Added

- `BrewinatorNotify.app`, a resident notification agent distributed through the separate, opt-in `brewinator-notifier` cask. When it's installed, notifications get a real icon and app name instead of Script Editor's, and clicking one reveals the archive in Finder. Nothing changes for anyone who doesn't install it - `brewinator` falls back to the existing `osascript` banner automatically.

### Notes

- Installing the resident agent requires launching it once so macOS can register it for notification permission - not fully unattended yet on a brand-new install.

## [0.5.0] - 2026-08-19

### Added

- `notify` now works. With it set to `true`, every run posts a desktop notification saying how many release notes were written and for which packages, or how many packages are outdated when there were none to write. A failed run says so instead.
- The notification fires on quiet runs too, deliberately: the point is to confirm the scheduled run happened, so an absent notification means the run did not happen rather than that nothing changed.

### Notes

- The notification carries Script Editor's name and icon. `display notification` offers no way to change either, and the alternative - shipping an application bundle - is the wrong shape for a command-line tool installed through a Homebrew formula.
- macOS can suppress the notification silently. If none appears, check System Settings > Notifications for the Script Editor entry.

## [0.4.1] - 2026-08-19

### Fixed

- Release notes were never fetched for any formula installed from a third-party tap, brewinator itself included. `brew outdated` reports such a formula by its tap-qualified name (`someone/tap/sometool`) while `brew info` reports it short, so the two could not be joined and the formula was left with no source URL to resolve against. Formulae now carry both names.
- A tapped formula's slashes were also taken as real path separators when naming its archive file, so the write landed in a subdirectory that does not exist and failed. Archive filenames use the short name.
- Every failed write leaked one temp file that could never be cleaned up: `prune` only collects `.md` files, and the temp file's extension is the process id. Temp files are now removed whatever the outcome.

## [0.4.0] - 2026-08-18

Acts on a full review of everything released so far. Several of these are user-facing bugs that shipped in `0.3.x`.

### Fixed

- Every `config` verb failed on a machine with no config file, exiting with a raw `notFound` error - while the command's own help promised the file is created automatically. All verbs now create it.
- `config set archiveDirectory '~/Notes'` stored the tilde literally when no shell expanded it (a quoted value, a script, a launchd plist). The path was then resolved against the process working directory, so an unattended run could create a directory named `~` and prune inside it. Tildes are expanded; empty and relative paths are rejected.
- `config skip remove <package>` reported "not in the skip list" for packages skipped by the built-in list, with no hint that brewinator itself was skipping them and no way to find out. It now explains and links the issue tracker. `config skip add` no longer copies a built-in into the user's own list.
- An unwritable config directory crashed the process at top level instead of reporting the problem.
- `brewinator config skip` printed `USAGE: skip <subcommand>`, a command that cannot be typed.
- Errors from the `config` verbs reached the terminal as raw enum cases (`Error: unknownKey("bogus")`); they now read as sentences that name the valid keys.

### Added

- Pruned files are reported. A `Moved to Trash (N):` block lists what was removed from the archive; previously a run could empty the archive in silence.

### Changed

- The outdated listing prints before pruning and before the first network fetch, so it appears immediately instead of after every fetch has finished.
- `prune` reports the archived filenames it moved rather than their renamed paths inside Trash.

## [0.3.1] - 2026-08-18

### Fixed

- The config file was written with escaped slashes (`"\/Volumes\/..."`). It is meant to be hand-edited, so it is now written unescaped.

## [0.3.0] - 2026-08-18

### Added

- `config` subcommand: `config`, `config set <key> <value>`, `config skip add|remove <pattern>`.
- The config file is created automatically on first run, archiving to `~/Brew Release Notes` by default. A malformed config still errors rather than being overwritten.
- A built-in skip list for packages that publish no per-version release notes anywhere (Spotify, Discord, WhatsApp, the Microsoft Office casks). It ships in the code rather than in each user's config so it can be corrected in a release.

### Fixed

- Packages whose version differs only in a build id rendered as a meaningless `X -> X` row.

## [0.2.0] - 2026-08-18

### Fixed

- `brewinator --help` printed nothing and ran a full sync against the real config and archive. `parseAsRoot()` returns an auxiliary command for `--help` rather than throwing, and `0.1.0` discarded it.

### Added

- `--update`, which runs `brew update` before checking what is outdated. Off by default; the daily job wants it.
- `--version`.
- The outdated set is listed on every run, replacing a separate `brew outdated --verbose` call.

## [0.1.0] - 2026-08-17

Initial release: a Swift rewrite of the original `brew-notes.zsh`, distributed through `duracell1989/tap`.

[0.9.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.9.0
[0.8.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.8.0
[0.7.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.7.0
[0.6.1]: https://github.com/Duracell1989/brewinator/releases/tag/v0.6.1
[0.6.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.6.0
[0.5.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.5.0
[0.4.1]: https://github.com/Duracell1989/brewinator/releases/tag/v0.4.1
[0.4.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.4.0
[0.3.1]: https://github.com/Duracell1989/brewinator/releases/tag/v0.3.1
[0.3.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.3.0
[0.2.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.2.0
[0.1.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.1.0
