@testable import Brewinator

/// Hand-written protocol fake for `LaunchAgentControlling` — no Moq
/// equivalent in Swift. Records what it was asked to bootstrap so a test can
/// assert the label and plist path without touching the real launchd session.
final class FakeLaunchAgentControl: LaunchAgentControlling, @unchecked Sendable {
    var loaded: Bool
    var bootstrapError: (any Error)?
    private(set) var bootstrapped: [(label: String, plistPath: String)] = []

    init(loaded: Bool = false, bootstrapError: (any Error)? = nil) {
        self.loaded = loaded
        self.bootstrapError = bootstrapError
    }

    func isLoaded(label: String) -> Bool { loaded }

    func bootstrap(label: String, plistPath: String) throws {
        bootstrapped.append((label: label, plistPath: plistPath))
        if let bootstrapError {
            throw bootstrapError
        }
    }
}
