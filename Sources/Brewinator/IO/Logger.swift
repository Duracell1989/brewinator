import Foundation

/// Surfaces failures that must not abort the sync but also must not vanish
/// silently — a fetch or write failure for one package out of N should be
/// visible somewhere, not just missing from the archive with no trace.
protocol SyncLogger: Sendable {
    func warn(_ message: String)
}

/// Writes to stderr — no logging framework decided yet for Swift (see
/// CLAUDE.md's Swift section), and a CLI tool's warnings belong on stderr by
/// convention regardless of what framework eventually lands.
final class StderrLogger: SyncLogger {
    func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
