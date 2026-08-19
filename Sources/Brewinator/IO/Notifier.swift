import Foundation

enum NotifierError: Error, Sendable, Equatable {
    case processFailed(exitCode: Int32)
}

/// Posts the desktop banner. Behind a protocol so a run can be exercised
/// without a real Notification Center.
protocol Notifying: Sendable {
    func post(_ content: NotificationContent) throws
}

/// Shells out to `osascript`. `UNUserNotificationCenter` is not available here:
/// a bare SwiftPM executable has no bundle identifier and it aborts without one
/// (verified 2026-08-12). Consequence - the banner carries Script Editor's name
/// and icon, and `display notification` has no parameter to override either.
struct OSAScriptNotifier: Notifying {
    private static let osascriptPath = "/usr/bin/osascript"

    func post(_ content: NotificationContent) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.osascriptPath)
        // Text goes in as `argv` rather than interpolated into the script
        // source, so a version string containing a quote can't break out of it.
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)",
            "-e", "end run",
            content.body,
            content.title,
            content.subtitle,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Exit 0 does not prove a banner appeared - a disabled Notification
        // Center entry for Script Editor exits 0 too. Non-zero is still worth
        // raising: it means osascript itself refused the request.
        guard process.terminationStatus == 0 else {
            throw NotifierError.processFailed(exitCode: process.terminationStatus)
        }
    }
}
