import Foundation

enum LaunchAgentError: Error, Sendable, Equatable {
    case bootstrapFailed(exitCode: Int32)
}

/// Registers the resident agent with launchd. Behind a protocol so activation
/// can be exercised without touching the real launchd session.
protocol LaunchAgentControlling: Sendable {
    func isLoaded(label: String) -> Bool
    func bootstrap(label: String, plistPath: String) throws
}

/// Shells out to `launchctl` against the caller's GUI domain. The domain
/// target has to name a numeric uid - `gui/ben` is rejected, only `gui/501`
/// is accepted - so it is built from `getuid()` rather than the user name.
struct LaunchctlAgentControl: LaunchAgentControlling {
    private static let launchctlPath = "/bin/launchctl"

    func isLoaded(label: String) -> Bool {
        status(of: ["print", "\(Self.guiDomain)/\(label)"]) == 0
    }

    func bootstrap(label: String, plistPath: String) throws {
        let exitCode = status(of: ["bootstrap", Self.guiDomain, plistPath])
        guard exitCode == 0 else {
            throw LaunchAgentError.bootstrapFailed(exitCode: exitCode)
        }
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
    }

    /// `launchctl` reports everything through its exit code; its output is
    /// noise here (`print` dumps the whole job description on success, and
    /// `bootstrap` prints "Try re-running the command as root" on failure).
    private func status(of arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.launchctlPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Loads the resident agent when its plist is on disk but nothing has
/// registered it with launchd yet.
///
/// The `brewinator-notifier` cask writes the plist but cannot load it:
/// Homebrew runs cask install steps inside a sandbox, and launchd refuses job
/// submission from any sandboxed process - verified 2026-09-08, where even
/// `sandbox-exec -p '(version 1)(allow default)'` fails with `Bootstrap
/// failed: 5: Input/output error`. So the bootstrap belongs here, in a process
/// that runs unsandboxed in the user's own session. Without it a fresh install
/// posts to nobody until the next login, because `ResidentAgentNotifier` drops
/// its banner in silence when the agent isn't running.
enum NotifierAgentActivation {
    static let label = "dev.b89.brewinator.notifier"

    /// `homeDirectoryForCurrentUser` reads the passwd entry rather than
    /// `$HOME`, which is what the cask's own `base: :home` resolves to.
    static var defaultPlistPath: String {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            .path
    }

    /// Returns whether a bootstrap was issued and succeeded. Best-effort: a
    /// missing plist or a launchd refusal costs this run its banner, never the
    /// sync itself.
    @discardableResult
    static func activate(
        control: LaunchAgentControlling = LaunchctlAgentControl(),
        plistPath: String = defaultPlistPath,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        logger: SyncLogger
    ) -> Bool {
        guard fileExists(plistPath) else {
            logger.warn("notifier agent not loaded and \(plistPath) is missing - reinstall the brewinator-notifier cask")
            return false
        }
        guard !control.isLoaded(label: label) else { return false }

        do {
            try control.bootstrap(label: label, plistPath: plistPath)
            return true
        } catch {
            logger.warn("could not load the notifier agent - \(error)")
            return false
        }
    }
}
