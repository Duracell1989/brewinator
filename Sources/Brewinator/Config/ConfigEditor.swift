import Foundation

enum ConfigEditorError: Error, Sendable, Equatable {
    case unknownKey(String)
    case invalidValue(key: String, value: String)
    case invalidPath(String)
}

/// ArgumentParser prints a thrown error straight to the terminal, so an
/// unconformed enum would surface as `Error: unknownKey("bogus")` - naming the
/// mistake but not the way out of it.
extension ConfigEditorError: CustomStringConvertible, LocalizedError {
    var description: String {
        switch self {
        case .unknownKey(let key):
            return """
                \(key) is not a setting. Valid keys: archiveDirectory, notify.
                The skip list has its own verbs: brewinator config skip add|remove.
                """
        case .invalidValue(let key, let value):
            return "\(value) is not a valid value for \(key). Expected true or false."
        case .invalidPath(let value):
            let shown = value.isEmpty ? "an empty path" : value
            return """
                \(shown) cannot be used as archiveDirectory.
                Give an absolute path, or one starting with ~ - anything else resolves against \
                whatever directory the run happens to start in.
                """
        }
    }

    var errorDescription: String? { description }
}

/// The read/write half of `brewinator config`, kept out of the ArgumentParser
/// command types so it can be tested against a fake store - a parsed command
/// is built by the parser and has nowhere to inject one.
///
/// Every method returns the message to print rather than printing it, so a
/// test asserts on the same string the user sees.
struct ConfigEditor {
    let store: ConfigStore

    func show() throws -> String {
        let (config, notice) = try loadConfig()
        let skipList = config.skipList.isEmpty ? "(none)" : config.skipList.joined(separator: ", ")

        return notice + """
            \(store.path)

              archiveDirectory  \(config.archiveDirectory)
              skipList          \(skipList)
              notify            \(config.notify) (not implemented yet)

            Skipped by brewinator itself (no release notes published anywhere):
              \(BuiltInSkipList.patterns.joined(separator: ", "))
            If one of them does publish notes, please report it: \(BuiltInSkipList.issuesURL)
            """
    }

    /// `skipList` is deliberately not settable here - a comma-splitting
    /// setter would silently mangle patterns; `addSkip`/`removeSkip` own it.
    func set(key: String, value: String) throws -> String {
        var (config, notice) = try loadConfig()

        let stored: String
        switch key {
        case "archiveDirectory":
            stored = try Self.normalizedArchiveDirectory(value)
            config.archiveDirectory = stored
        case "notify":
            guard let flag = Bool(value) else {
                throw ConfigEditorError.invalidValue(key: key, value: value)
            }
            config.notify = flag
            stored = value
        default:
            throw ConfigEditorError.unknownKey(key)
        }

        try store.save(config)
        return notice + "\(key) = \(stored)"
    }

    func addSkip(_ pattern: String) throws -> String {
        var (config, notice) = try loadConfig()
        guard !BuiltInSkipList.patterns.contains(pattern) else {
            return notice + "\(pattern) is already skipped by brewinator itself, so there is nothing to add."
        }
        guard !config.skipList.contains(pattern) else {
            return notice + "\(pattern) is already in the skip list"
        }

        config.skipList.append(pattern)
        try store.save(config)
        return notice + "Added \(pattern) to the skip list"
    }

    func removeSkip(_ pattern: String) throws -> String {
        var (config, notice) = try loadConfig()
        let isBuiltIn = BuiltInSkipList.patterns.contains(pattern)

        guard config.skipList.contains(pattern) else {
            guard isBuiltIn else {
                return notice + "\(pattern) is not in the skip list"
            }
            return notice + """
                \(pattern) is skipped by brewinator itself, not by your config, so there is nothing here to remove.
                If it does publish release notes, please open an issue: \(BuiltInSkipList.issuesURL)
                """
        }

        config.skipList.removeAll { $0 == pattern }
        try store.save(config)
        let stillSkipped = isBuiltIn ? " (it stays skipped: brewinator skips it by default)" : ""
        return notice + "Removed \(pattern) from the skip list\(stillSkipped)"
    }

    /// Every verb creates the config rather than dead-ending on a fresh
    /// install: `brewinator config` is a plausible first command to run, and
    /// the command's own help says the file appears by itself.
    private func loadConfig() throws -> (config: UserConfig, notice: String) {
        let loaded = try store.loadOrCreate(default: UserConfig.default)
        return (loaded.config, loaded.created ? "Created a default config at \(store.path)\n\n" : "")
    }

    /// A `~` that no shell expanded (quoted, or issued from a script or a
    /// launchd plist) used to be stored literally, and `URL(fileURLWithPath:)`
    /// then resolved it against the process cwd - so a daily job created a
    /// directory actually named `~` and pruned inside it.
    private static func normalizedArchiveDirectory(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ConfigEditorError.invalidPath(value) }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw ConfigEditorError.invalidPath(value) }
        return expanded
    }
}
