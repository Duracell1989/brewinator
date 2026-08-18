# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions before `1.0.0` may change behaviour in a minor bump.

The release workflow reads the section matching the tag it is building, and fails if there isn't one.

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

[0.4.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.4.0
[0.3.1]: https://github.com/Duracell1989/brewinator/releases/tag/v0.3.1
[0.3.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.3.0
[0.2.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.2.0
[0.1.0]: https://github.com/Duracell1989/brewinator/releases/tag/v0.1.0
