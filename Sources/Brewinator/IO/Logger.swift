import Foundation

/// Surfaces per-package failures that must not abort the sync, but also must
/// not vanish leaving only a silently missing archive file.
protocol SyncLogger: Sendable {
    func warn(_ message: String)
}

final class StderrLogger: SyncLogger {
    func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
