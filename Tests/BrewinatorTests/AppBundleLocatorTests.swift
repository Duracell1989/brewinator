import Foundation
import Testing

@testable import Brewinator

/// Builds a throwaway Caskroom: `<root>/<token>/<version>/<App>.app` as a
/// *symlink* to an app bundle elsewhere, which is exactly how Homebrew leaves
/// a staged cask once the app artifact has been moved to /Applications.
private struct FakeCaskroom {
    let root: URL
    let appsDirectory: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("Caskroom")
        appsDirectory = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)
    }

    /// Returns the real (linked-to) bundle path, which is what the locator is
    /// expected to report.
    @discardableResult
    func stage(token: String, version: String, appName: String, infoPlist: String?, releaseNotes: String?) throws -> String {
        let app = appsDirectory.appendingPathComponent(appName)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        if let infoPlist {
            try infoPlist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        }
        if let releaseNotes {
            try releaseNotes.write(to: contents.appendingPathComponent("Resources/ReleaseNotes.html"), atomically: true, encoding: .utf8)
        }

        let staged = root.appendingPathComponent(token).appendingPathComponent(version)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: staged.appendingPathComponent(appName), withDestinationURL: app)
        return app.resolvingSymlinksInPath().path
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}

private func plist(feed: String?) -> String {
    let feedEntry = feed.map { "<key>SUFeedURL</key><string>\($0)</string>" } ?? ""
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict><key>CFBundleShortVersionString</key><string>3.0.3</string>\(feedEntry)</dict>
        </plist>
        """
}

@Suite("CaskroomAppBundleLocator")
struct CaskroomAppBundleLocatorTests {
    @Test("reads the changelog and the Sparkle feed through the Caskroom symlink")
    func readsBothSignals() throws {
        let caskroom = try FakeCaskroom()
        defer { caskroom.remove() }
        let realPath = try caskroom.stage(
            token: "proton-drive",
            version: "3.0.3",
            appName: "Proton Drive.app",
            infoPlist: plist(feed: "https://proton.me/download/drive/macos/appcast.xml"),
            releaseNotes: "<h1>3.0.3</h1>"
        )

        let bundle = CaskroomAppBundleLocator(caskroomPath: caskroom.root.path).bundle(forCask: "proton-drive", installedVersion: "3.0.3")

        #expect(bundle?.path == realPath)
        #expect(bundle?.releaseNotesHTML == "<h1>3.0.3</h1>")
        #expect(bundle?.sparkleFeedURL?.absoluteString == "https://proton.me/download/drive/macos/appcast.xml")
    }

    @Test("an app with neither signal resolves to nil rather than an empty bundle")
    func noSignalsIsNil() throws {
        let caskroom = try FakeCaskroom()
        defer { caskroom.remove() }
        try caskroom.stage(token: "plain", version: "1.0", appName: "Plain.app", infoPlist: plist(feed: nil), releaseNotes: nil)

        #expect(CaskroomAppBundleLocator(caskroomPath: caskroom.root.path).bundle(forCask: "plain", installedVersion: "1.0") == nil)
    }

    @Test("a cask that stages no app at all is nil, not a crash")
    func missingCaskIsNil() throws {
        let caskroom = try FakeCaskroom()
        defer { caskroom.remove() }

        #expect(CaskroomAppBundleLocator(caskroomPath: caskroom.root.path).bundle(forCask: "absent", installedVersion: "1.0") == nil)
    }

    // An interrupted upgrade can leave the reported installed version without a
    // staging directory; the app is still on disk under the other one.
    @Test("another staged version is used when the installed one has no app")
    func fallsBackToAnotherVersionDirectory() throws {
        let caskroom = try FakeCaskroom()
        defer { caskroom.remove() }
        try caskroom.stage(
            token: "telegram", version: "12.9", appName: "Telegram.app", infoPlist: plist(feed: "https://osx.telegram.org/updates/versions.xml"),
            releaseNotes: nil)

        let bundle = CaskroomAppBundleLocator(caskroomPath: caskroom.root.path).bundle(forCask: "telegram", installedVersion: "12.10")

        #expect(bundle?.sparkleFeedURL?.absoluteString == "https://osx.telegram.org/updates/versions.xml")
    }
}
