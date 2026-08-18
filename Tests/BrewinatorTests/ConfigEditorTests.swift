import Testing

@testable import Brewinator

@Suite("ConfigEditor")
struct ConfigEditorTests {
    private func editor(_ config: UserConfig? = nil) -> (ConfigEditor, InMemoryConfigStore) {
        let store = InMemoryConfigStore(config: config)
        return (ConfigEditor(store: store), store)
    }

    private var sample: UserConfig {
        UserConfig(archiveDirectory: "/notes", skipList: ["whatsapp", "proton-*"], notify: false)
    }

    @Test("show renders the config path and every setting, so `brewinator config` answers 'where does this write?'")
    func showRendersEverything() throws {
        let (editor, store) = editor(sample)

        let output = try editor.show()

        #expect(output.contains(store.path))
        #expect(output.contains("/notes"))
        #expect(output.contains("whatsapp"))
        #expect(output.contains("proton-*"))
    }

    @Test("set archiveDirectory persists the new path")
    func setArchiveDirectory() throws {
        let (editor, store) = editor(sample)

        _ = try editor.set(key: "archiveDirectory", value: "/elsewhere")

        #expect(try store.load().archiveDirectory == "/elsewhere")
    }

    @Test("set notify parses a bool")
    func setNotify() throws {
        let (editor, store) = editor(sample)

        _ = try editor.set(key: "notify", value: "true")

        #expect(try store.load().notify)
    }

    @Test("set notify rejects a non-bool instead of silently storing false")
    func setNotifyRejectsGarbage() {
        let (editor, _) = editor(sample)

        #expect(throws: ConfigEditorError.invalidValue(key: "notify", value: "maybe")) {
            _ = try editor.set(key: "notify", value: "maybe")
        }
    }

    @Test("an unknown key is rejected rather than written into the JSON as a stray field")
    func setUnknownKey() {
        let (editor, _) = editor(sample)

        #expect(throws: ConfigEditorError.unknownKey("archiveDir")) {
            _ = try editor.set(key: "archiveDir", value: "/elsewhere")
        }
    }

    @Test("skipList is not settable through `set` — it has its own add/remove verbs")
    func setSkipListIsRejected() {
        let (editor, _) = editor(sample)

        #expect(throws: ConfigEditorError.unknownKey("skipList")) {
            _ = try editor.set(key: "skipList", value: "spotify")
        }
    }

    @Test("skip add appends a pattern")
    func skipAdd() throws {
        let (editor, store) = editor(sample)

        _ = try editor.addSkip("spotify")

        #expect(try store.load().skipList == ["whatsapp", "proton-*", "spotify"])
    }

    @Test("skip add is idempotent and doesn't rewrite the file for a duplicate")
    func skipAddIsIdempotent() throws {
        let (editor, store) = editor(sample)

        _ = try editor.addSkip("whatsapp")

        #expect(try store.load().skipList == ["whatsapp", "proton-*"])
        #expect(store.saveCount == 0)
    }

    @Test("skip remove drops the pattern")
    func skipRemove() throws {
        let (editor, store) = editor(sample)

        _ = try editor.removeSkip("whatsapp")

        #expect(try store.load().skipList == ["proton-*"])
    }

    @Test("removing a pattern that isn't listed says so rather than failing the command")
    func skipRemoveUnknownPattern() throws {
        let (editor, store) = editor(sample)

        let message = try editor.removeSkip("cowsay")

        #expect(message.contains("not in the skip list"))
        #expect(store.saveCount == 0)
    }
}

@Suite("ConfigEditor built-in skips")
struct ConfigEditorBuiltInSkipTests {
    @Test("show lists the built-in skips separately, so they're visible without being editable")
    func showListsBuiltIns() throws {
        let store = InMemoryConfigStore(config: UserConfig(archiveDirectory: "/notes", skipList: ["nspr"], notify: false))
        let editor = ConfigEditor(store: store)

        let output = try editor.show()

        #expect(output.contains("built-in"))
        #expect(output.contains("spotify"))
        #expect(output.contains("nspr"))
    }
}
