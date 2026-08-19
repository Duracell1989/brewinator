![Brewinator](https://raw.githubusercontent.com/Duracell1989/brewinator/main/assets/icon.png)

# Brewinator

Fetches and archives release notes for outdated Homebrew packages, so you never install an update blind.

[![CI](https://github.com/Duracell1989/brewinator/actions/workflows/ci.yml/badge.svg)](https://github.com/Duracell1989/brewinator/actions/workflows/ci.yml)

Brewinator checks `brew outdated` against a curated, in-repo database of where release notes actually live for popular Homebrew formulae and casks - GitHub/GitLab/Gitea releases, Sparkle appcasts, JetBrains, and a handful of bespoke vendor sources (Firefox, ffmpeg, .NET SDK, Claude Desktop, Obsidian, Windows App, Android Studio) - then archives each package's notes as one Markdown file. Designed to run unattended once a day via `launchd`.

---

## Features

- Fetches release notes for outdated packages from GitHub, GitLab, Gitea, Sparkle appcasts, JetBrains, and several vendor-specific sources
- Archives one Markdown file per package (e.g. `node (formula) - 23.0.0.md`)
- Prunes archives for packages that have since been upgraded or added to the skip list - always to Trash, never deleted outright
- Skip list supports exact names and `*` globs
- Existing archive files act as the state store - no separate tracking file, so a package's notes are only fetched once per version
- Built to run unattended once a day via `launchd`; safe to re-run manually too

---

## Installation

Brewinator lives in its own tap, so the plain `brew install brewinator` won't find it. Either install it by its full tap-qualified name:

```
brew install duracell1989/tap/brewinator
```

or add the tap once and use the short name from then on:

```
brew tap duracell1989/tap
brew install brewinator
```

Upgrades follow the usual `brew upgrade` / `brew upgrade brewinator`. What changed in each version is in [CHANGELOG.md](https://github.com/Duracell1989/brewinator/blob/main/CHANGELOG.md).

---

## Configuration

Brewinator reads `~/.config/brewinator/config.json` on every run, and writes a default one on first run - archiving to `~/Brew Release Notes` until you point it somewhere else:

```json
{
  "archiveDirectory": "/path/to/your/notes/archive",
  "skipList": [],
  "notify": false
}
```

- `archiveDirectory` - where release-note Markdown files are written; created automatically if it doesn't exist.
- `skipList` - package names to skip; exact match or `*` glob (e.g. `"proton-*"`).
- `notify` - post a desktop notification at the end of every run, including quiet ones, so an absent notification means the run did not happen. The notification carries Script Editor's name and icon; `display notification` provides no way to change either. If none appears, check System Settings > Notifications for the Script Editor entry.

Edit the JSON directly, or use the CLI:

```
brewinator config                                     # where it lives, what's in it
brewinator config set archiveDirectory ~/Notes/Brew
brewinator config skip add spotify
brewinator config skip remove spotify
```

Packages on the built-in list below are skipped by brewinator itself, so `config skip remove` cannot un-skip them; it will say so and point you at the issue tracker.

### Built-in skips

Some packages publish no per-version release notes anywhere, so brewinator skips them without you configuring anything - `spotify`, `discord`, `whatsapp`, and the Microsoft Office casks. That list ships in the code rather than in your config file, so it can be corrected in a release instead of being frozen on the day you installed. `brewinator config` prints it.

If one of them does publish notes somewhere, or a package you care about isn't resolving, please [open an issue or a pull request](https://github.com/Duracell1989/brewinator/issues) - that's the way the curated database grows.

---

## Usage

Run with no arguments:

```
brewinator
```

It checks `brew outdated`, lists what's outdated, fetches release notes for anything new, archives them, and prunes stale entries:

```
Outdated (2):
  node (formula)   22.0.0 -> 23.0.0
  obsidian (cask)  1.1.0 -> 1.2.0

Moved to Trash (1):
  - ripgrep (formula) - 14.1.0.md

New release notes (2):
  - node 23.0.0
  - obsidian 1.2.0
See: /path/to/your/notes/archive
```

The outdated list prints before any notes are fetched, so it appears immediately rather than after the network round-trips.

A `Moved to Trash` block appears whenever archived notes are pruned - because the package has since been upgraded, or because it was added to the skip list. Pruning happens on every run, including runs where nothing is outdated, so `Nothing outdated.` on its own means the archive was already clean.

### Options

| Flag | Effect |
|---|---|
| `--update` | Run `brew update` first, so the outdated set reflects fresh package metadata. Off by default - a bare run only reads Homebrew state. |
| `--version` | Print the version and exit. |
| `--help` | Print usage and exit. |

Homebrew's metadata is only as fresh as the last `brew update`, so an unattended daily job wants `--update`:

```
brewinator --update
```

That makes the whole workflow one command - no shell wrapper needed around `brew update` and `brew outdated`.

---

## Development

Build and test:

```
swift build
swift test
```

Open `Package.swift` directly in Xcode (`File → Open`, no `.xcodeproj` needed), or use any editor plus the CLI above.

First clone only - wire up the pre-commit hook (git doesn't track `core.hooksPath` automatically):

```
git config core.hooksPath .githooks
```

Quality gate:

```
swiftlint lint --strict
swift format lint --recursive Sources Tests
```

This is the author's first Swift project, built primarily with [Claude Code](https://claude.com/claude-code) as a learning exercise.

---

## License

MIT - see [LICENSE](LICENSE).
