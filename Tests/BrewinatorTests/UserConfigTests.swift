import Testing

@testable import Brewinator

@Suite("UserConfig.isSkipped")
struct UserConfigTests {
    @Test("exact name match")
    func exactMatch() {
        let config = UserConfig(archiveDirectory: "/tmp", skipList: ["discord"], notify: false)
        #expect(config.isSkipped("discord"))
        #expect(!config.isSkipped("obsidian"))
    }

    @Test("glob pattern match")
    func globMatch() {
        let config = UserConfig(archiveDirectory: "/tmp", skipList: ["lib*"], notify: false)
        #expect(config.isSkipped("libssh2"))
        #expect(!config.isSkipped("obsidian"))
    }

    @Test("empty skip list matches nothing")
    func emptySkipList() {
        let config = UserConfig(archiveDirectory: "/tmp", skipList: [], notify: false)
        #expect(!config.isSkipped("anything"))
    }
}

@Suite("Built-in skip list")
struct BuiltInSkipListTests {
    @Test("packages that publish no notes anywhere are skipped without the user configuring anything")
    func builtInsAreSkippedWithEmptyUserList() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: [], notify: false)

        #expect(config.isSkipped("spotify"))
        #expect(config.isSkipped("discord"))
        #expect(config.isSkipped("microsoft-word"))
    }

    @Test("a package with real release notes is not skipped by default")
    func normalPackagesAreNotSkipped() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: [], notify: false)

        #expect(!config.isSkipped("node"))
        #expect(!config.isSkipped("obsidian"))
    }

    @Test("the built-ins stay out of the user's own list — `config skip` only ever edits their entries")
    func builtInsAreNotInTheUserList() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: ["nspr"], notify: false)

        #expect(config.skipList == ["nspr"])
        #expect(config.effectiveSkipList.contains("nspr"))
        #expect(config.effectiveSkipList.contains("spotify"))
    }

    @Test("user globs keep working alongside the built-ins")
    func userGlobsStillApply() {
        let config = UserConfig(archiveDirectory: "/notes", skipList: ["proton-*"], notify: false)

        #expect(config.isSkipped("proton-mail"))
    }
}
