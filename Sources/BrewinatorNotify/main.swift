import AppKit
import NotifierIPC
import UserNotifications
import os

// Resident notification agent. Not `brewinator` itself - the CLI's own run is
// short-lived (launchd fires it once daily and it exits), which cannot catch
// a click that lands minutes or hours later from Notification Center. This
// process is kept alive instead (LaunchAgent with KeepAlive, installed by the
// brewinator-notifier cask) so it is still around whenever that click happens.
// Confirmed necessary, not just convenient - see the Phase 8 spike write-up
// in the plan doc: a banner from an already-exited process surfaces
// "app is not open anymore" instead of delivering the click.

private let logger = Logger(subsystem: "dev.b89.brewinator.notifier", category: "agent")

@MainActor
final class NotifierAgent: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // Keyed by notification request identifier so a click can be traced back
    // to the archive path it should reveal, without smuggling that path
    // through UNNotificationContent's userInfo (which round-trips through
    // the system and isn't needed for display).
    private var openPathByRequestID: [String: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("launched, bundle id \(Bundle.main.bundleIdentifier ?? "nil", privacy: .public)")

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            logger.info("authorization granted=\(granted, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: NotifierIPC.notificationName,
            object: nil
        )
    }

    @objc
    private func handleDistributedNotification(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let content = UNMutableNotificationContent()
        content.title = userInfo[NotifierIPC.Key.title] as? String ?? "Brewinator"
        content.subtitle = userInfo[NotifierIPC.Key.subtitle] as? String ?? ""
        content.body = userInfo[NotifierIPC.Key.body] as? String ?? ""

        let requestID = UUID().uuidString
        if let openPath = userInfo[NotifierIPC.Key.openPath] as? String {
            openPathByRequestID[requestID] = openPath
        }

        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            logger.error("failed to post notification: \(String(describing: error), privacy: .public)")
        }
    }

    // `nonisolated` rather than the isolated-conformance shorthand
    // (`@MainActor UNUserNotificationCenterDelegate` on the class line): that
    // syntax only exists on the local beta toolchain (Xcode 27 beta) and
    // fails to parse at all on CI's stable one ("unknown attribute
    // 'MainActor'"). This older pattern - nonisolated delegate methods,
    // hopping to the actor via `Task` only where actor state is touched -
    // compiles on both.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Clicking the banner reveals the archive in Finder - the concrete fix
    // for "clicking activates Script Editor" (the third of the three
    // `osascript` limitations the companion app exists to fix; see the plan
    // doc's Phase 7/8 notes).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestID = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        // completionHandler isn't @Sendable, so it's called here rather than
        // captured into the Task below - it only signals "response handled",
        // it doesn't need to wait on the Finder-opening side effect.
        Task { @MainActor in
            guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
            guard let path = self.openPathByRequestID.removeValue(forKey: requestID) else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        completionHandler()
    }
}

let app = NSApplication.shared
let agent = NotifierAgent()
app.delegate = agent
app.setActivationPolicy(.accessory)
app.run()
