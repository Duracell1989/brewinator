@testable import Brewinator

/// Records `warn()` calls for assertion instead of printing them. `@unchecked
/// Sendable` is safe here: `BrewNotesSync.run()` awaits sequentially in a
/// single `for` loop, never calling `warn()` from concurrent tasks.
final class RecordingLogger: SyncLogger, @unchecked Sendable {
    private(set) var messages: [String] = []

    func warn(_ message: String) {
        messages.append(message)
    }
}
