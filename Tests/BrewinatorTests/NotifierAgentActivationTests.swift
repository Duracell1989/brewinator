import Testing

@testable import Brewinator

@Suite("NotifierAgentActivation")
struct NotifierAgentActivationTests {
    private let plistPath = "/Users/someone/Library/LaunchAgents/dev.b89.brewinator.notifier.plist"

    @Test("bootstraps the agent when its plist is present but nothing has loaded it")
    func bootstrapsWhenPlistPresentAndUnloaded() {
        let control = FakeLaunchAgentControl(loaded: false)
        let logger = RecordingLogger()

        let activated = NotifierAgentActivation.activate(
            control: control,
            plistPath: plistPath,
            fileExists: { $0 == self.plistPath },
            logger: logger
        )

        #expect(activated)
        #expect(control.bootstrapped.count == 1)
        #expect(control.bootstrapped.first?.label == "dev.b89.brewinator.notifier")
        #expect(control.bootstrapped.first?.plistPath == plistPath)
        #expect(logger.messages.isEmpty)
    }

    @Test("leaves an already-loaded agent alone")
    func skipsWhenAlreadyLoaded() {
        let control = FakeLaunchAgentControl(loaded: true)
        let logger = RecordingLogger()

        let activated = NotifierAgentActivation.activate(
            control: control,
            plistPath: plistPath,
            fileExists: { _ in true },
            logger: logger
        )

        #expect(!activated)
        #expect(control.bootstrapped.isEmpty)
        #expect(logger.messages.isEmpty)
    }

    @Test("warns instead of bootstrapping when the cask left no plist")
    func warnsWhenPlistMissing() {
        let control = FakeLaunchAgentControl(loaded: false)
        let logger = RecordingLogger()

        let activated = NotifierAgentActivation.activate(
            control: control,
            plistPath: plistPath,
            fileExists: { _ in false },
            logger: logger
        )

        #expect(!activated)
        #expect(control.bootstrapped.isEmpty)
        #expect(logger.messages.count == 1)
        #expect(logger.messages.first?.contains(plistPath) == true)
    }

    @Test("warns and carries on when launchd refuses the bootstrap")
    func warnsWhenBootstrapFails() {
        let control = FakeLaunchAgentControl(
            loaded: false,
            bootstrapError: LaunchAgentError.bootstrapFailed(exitCode: 5)
        )
        let logger = RecordingLogger()

        let activated = NotifierAgentActivation.activate(
            control: control,
            plistPath: plistPath,
            fileExists: { _ in true },
            logger: logger
        )

        #expect(!activated)
        #expect(control.bootstrapped.count == 1)
        #expect(logger.messages.count == 1)
    }
}
