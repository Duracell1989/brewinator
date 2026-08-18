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

    /// Uses a package that is *not* on the built-in list: adding one of those
    /// is refused rather than duplicated, which has its own test.
    @Test("skip add appends a pattern")
    func skipAdd() throws {
        let (editor, store) = editor(sample)

        _ = try editor.addSkip("cowsay")

        #expect(try store.load().skipList == ["whatsapp", "proton-*", "cowsay"])
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

        #expect(output.contains("brewinator itself"))
        #expect(output.contains(BuiltInSkipList.issuesURL))
        #expect(output.contains("spotify"))
        #expect(output.contains("nspr"))
    }
}

@Suite("ConfigEditor first run")
struct ConfigEditorFirstRunTests {
    /// Every verb used to call `store.load()` directly, so a brand-new install
    /// got `Error: notFound(path: ...)` from the very first command it was told
    /// to run - while the command's own help text promised the file is created
    /// automatically.
    @Test("show creates the config instead of failing on a fresh install")
    func showCreatesConfig() throws {
        let store = InMemoryConfigStore()
        let editor = ConfigEditor(store: store)

        let output = try editor.show()

        #expect(output.contains("Created a default config"))
        #expect(store.saveCount == 1)
    }

    @Test("set creates the config instead of failing on a fresh install")
    func setCreatesConfig() throws {
        let store = InMemoryConfigStore()
        let editor = ConfigEditor(store: store)

        let output = try editor.set(key: "notify", value: "true")

        #expect(output.contains("Created a default config"))
        #expect(try store.load().notify)
    }

    @Test("skip add creates the config instead of failing on a fresh install")
    func skipAddCreatesConfig() throws {
        let store = InMemoryConfigStore()
        let editor = ConfigEditor(store: store)

        let output = try editor.addSkip("cowsay")

        #expect(output.contains("Created a default config"))
        #expect(try store.load().skipList == ["cowsay"])
    }

    @Test("skip remove creates the config instead of failing on a fresh install")
    func skipRemoveCreatesConfig() throws {
        let store = InMemoryConfigStore()
        let editor = ConfigEditor(store: store)

        let output = try editor.removeSkip("cowsay")

        #expect(output.contains("Created a default config"))
    }

    @Test("an existing config is never announced as created")
    func existingConfigIsNotAnnounced() throws {
        let store = InMemoryConfigStore(config: UserConfig(archiveDirectory: "/notes", skipList: [], notify: false))
        let editor = ConfigEditor(store: store)

        #expect(try !editor.show().contains("Created a default config"))
    }
}

@Suite("ConfigEditor archiveDirectory validation")
struct ConfigEditorArchiveDirectoryTests {
    private func editor() -> (ConfigEditor, InMemoryConfigStore) {
        let store = InMemoryConfigStore(config: UserConfig(archiveDirectory: "/notes", skipList: [], notify: false))
        return (ConfigEditor(store: store), store)
    }

    /// A quoted `~` (or one from a script or launchd plist, where no shell
    /// expands it) used to be stored literally, and `URL(fileURLWithPath:)` then
    /// resolved it against the process cwd - creating a directory actually named
    /// `~` and pointing `prune` at it.
    @Test("a leading tilde is expanded rather than stored literally")
    func expandsTilde() throws {
        let (editor, store) = editor()

        _ = try editor.set(key: "archiveDirectory", value: "~/Notes/Brew")

        let stored = try store.load().archiveDirectory
        #expect(!stored.contains("~"))
        #expect(stored.hasSuffix("/Notes/Brew"))
        #expect(stored.hasPrefix("/"))
    }

    @Test("a relative path is rejected - it would resolve against whatever cwd the run happens to have")
    func rejectsRelativePath() {
        let (editor, store) = editor()

        #expect(throws: ConfigEditorError.invalidPath("../relative")) {
            _ = try editor.set(key: "archiveDirectory", value: "../relative")
        }
        #expect(store.saveCount == 0)
    }

    @Test("an empty path is rejected - it resolves to the cwd, where prune would start trashing files")
    func rejectsEmptyPath() {
        let (editor, store) = editor()

        #expect(throws: ConfigEditorError.invalidPath("")) {
            _ = try editor.set(key: "archiveDirectory", value: "")
        }
        #expect(store.saveCount == 0)
    }

    @Test("an absolute path is stored as given")
    func acceptsAbsolutePath() throws {
        let (editor, store) = editor()

        _ = try editor.set(key: "archiveDirectory", value: "/Volumes/Vault/Notes")

        #expect(try store.load().archiveDirectory == "/Volumes/Vault/Notes")
    }
}

@Suite("ConfigEditor skip verbs vs built-ins")
struct ConfigEditorBuiltInVerbTests {
    private func editor(_ skipList: [String] = []) -> (ConfigEditor, InMemoryConfigStore) {
        let store = InMemoryConfigStore(config: UserConfig(archiveDirectory: "/notes", skipList: skipList, notify: false))
        return (ConfigEditor(store: store), store)
    }

    /// Used to print "spotify is not in the skip list" while spotify stayed
    /// skipped forever, with no hint that the tool itself was doing it.
    @Test("removing a built-in explains who is skipping it and where to report it")
    func removeBuiltInExplains() throws {
        let (editor, store) = editor()

        let message = try editor.removeSkip("spotify")

        #expect(message.contains("brewinator itself"))
        #expect(message.contains("github.com/Duracell1989/brewinator/issues"))
        #expect(store.saveCount == 0)
    }

    @Test("adding a built-in reports it as already skipped rather than duplicating it into the user's list")
    func addBuiltInIsNotDuplicated() throws {
        let (editor, store) = editor()

        let message = try editor.addSkip("spotify")

        #expect(message.contains("brewinator itself"))
        #expect(try store.load().skipList.isEmpty)
        #expect(store.saveCount == 0)
    }

    @Test("a pattern in both lists is removed from the user's list but reported as still skipped")
    func removeUserEntryThatIsAlsoBuiltIn() throws {
        let (editor, store) = editor(["spotify"])

        let message = try editor.removeSkip("spotify")

        #expect(try store.load().skipList.isEmpty)
        #expect(message.contains("stays skipped"))
    }
}

@Suite("ConfigEditorError messages")
struct ConfigEditorErrorTests {
    /// ArgumentParser renders a thrown error straight to the user, so a bare
    /// enum case reached the terminal as `Error: unknownKey("bogus")`.
    @Test("unknownKey names the keys that are valid")
    func unknownKeyNamesValidKeys() {
        let description = String(describing: ConfigEditorError.unknownKey("bogus"))

        #expect(description.contains("bogus"))
        #expect(description.contains("archiveDirectory"))
        #expect(description.contains("notify"))
        #expect(!description.contains("unknownKey("))
    }

    @Test("invalidValue says what was expected")
    func invalidValueSaysExpected() {
        let description = String(describing: ConfigEditorError.invalidValue(key: "notify", value: "maybe"))

        #expect(description.contains("maybe"))
        #expect(description.contains("true"))
        #expect(!description.contains("invalidValue("))
    }

    @Test("invalidPath says an absolute path is wanted")
    func invalidPathSaysAbsolute() {
        let description = String(describing: ConfigEditorError.invalidPath("../relative"))

        #expect(description.contains("absolute"))
        #expect(!description.contains("invalidPath("))
    }
}
