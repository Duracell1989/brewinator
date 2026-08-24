import Testing

@testable import Brewinator

@Suite("NotifierSelection")
struct NotifierSelectionTests {
    @Test("picks the resident agent when its app bundle is present")
    func picksResidentAgentWhenPresent() {
        let notifier = NotifierSelection.resolve(
            archiveDirectoryPath: "/notes",
            agentBundlePath: "/Applications/BrewinatorNotify.app",
            fileExists: { $0 == "/Applications/BrewinatorNotify.app" }
        )

        #expect(notifier is ResidentAgentNotifier)
    }

    @Test("falls back to osascript when the app bundle is absent")
    func fallsBackToOSAScriptWhenAbsent() {
        let notifier = NotifierSelection.resolve(
            archiveDirectoryPath: "/notes",
            agentBundlePath: "/Applications/BrewinatorNotify.app",
            fileExists: { _ in false }
        )

        #expect(notifier is OSAScriptNotifier)
    }
}
