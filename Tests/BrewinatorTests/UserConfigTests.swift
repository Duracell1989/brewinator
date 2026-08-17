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
