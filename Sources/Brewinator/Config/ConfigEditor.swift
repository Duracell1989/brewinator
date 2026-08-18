enum ConfigEditorError: Error, Sendable, Equatable {
    case unknownKey(String)
    case invalidValue(key: String, value: String)
}

/// The read/write half of `brewinator config`, kept out of the ArgumentParser
/// command types so it can be tested against a fake store — a parsed command
/// is built by the parser and has nowhere to inject one.
///
/// Every method returns the message to print rather than printing it, so a
/// test asserts on the same string the user sees.
struct ConfigEditor {
    let store: ConfigStore

    func show() throws -> String {
        let config = try store.load()
        let skipList = config.skipList.isEmpty ? "(none)" : config.skipList.joined(separator: ", ")

        return """
            \(store.path)

              archiveDirectory  \(config.archiveDirectory)
              skipList          \(skipList)
              notify            \(config.notify) (not implemented yet)

            Skipped built-in (no release notes published anywhere — open an issue if that's wrong):
              \(BuiltInSkipList.patterns.joined(separator: ", "))
            """
    }

    /// `skipList` is deliberately not settable here — a comma-splitting
    /// setter would silently mangle patterns; `addSkip`/`removeSkip` own it.
    func set(key: String, value: String) throws -> String {
        var config = try store.load()

        switch key {
        case "archiveDirectory":
            config.archiveDirectory = value
        case "notify":
            guard let flag = Bool(value) else {
                throw ConfigEditorError.invalidValue(key: key, value: value)
            }
            config.notify = flag
        default:
            throw ConfigEditorError.unknownKey(key)
        }

        try store.save(config)
        return "\(key) = \(value)"
    }

    func addSkip(_ pattern: String) throws -> String {
        var config = try store.load()
        guard !config.skipList.contains(pattern) else {
            return "\(pattern) is already in the skip list"
        }

        config.skipList.append(pattern)
        try store.save(config)
        return "Added \(pattern) to the skip list"
    }

    func removeSkip(_ pattern: String) throws -> String {
        var config = try store.load()
        guard config.skipList.contains(pattern) else {
            return "\(pattern) is not in the skip list"
        }

        config.skipList.removeAll { $0 == pattern }
        try store.save(config)
        return "Removed \(pattern) from the skip list"
    }
}
