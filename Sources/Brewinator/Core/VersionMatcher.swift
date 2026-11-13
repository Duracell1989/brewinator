import Foundation

protocol VersionTagged {
    var tagName: String { get }
}

enum VersionMatcher {
    /// Drops the cask build-number suffix after a comma, then the formula
    /// revision suffix. Anchored to `_[0-9]+$` because an unanchored match would
    /// also eat real version data (`3.9_1.2.3`).
    static func cleanVersion(_ raw: String) -> String {
        var cleaned = raw
        if let commaIndex = cleaned.firstIndex(of: ",") {
            cleaned = String(cleaned[cleaned.startIndex..<commaIndex])
        }
        if let range = cleaned.range(of: "_[0-9]+$", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned
    }

    /// First two dot-fields of a version: 10.0.400 -> 10.0, 9.0 -> 9.0, 9 -> 9.
    static func versionChannel(_ version: String) -> String {
        let parts = version.split(separator: ".")
        return parts.prefix(2).joined(separator: ".")
    }

    /// Exact `tagName` match, case-insensitive with an optional `v` prefix on
    /// either side; then a tag that is the version behind a name prefix
    /// (`lcms2.20`, `release-1.2`); then the first element (releases list
    /// newest first).
    static func matchRelease<T: VersionTagged>(in releases: [T], version: String) -> T? {
        let target = version.lowercased().hasPrefix("v") ? String(version.lowercased().dropFirst()) : version.lowercased()
        let exact = releases.first { release in
            let tag = release.tagName.lowercased()
            let strippedTag = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return strippedTag == target
        }
        return exact ?? releases.first { isPrefixed(tag: $0.tagName.lowercased(), version: target) } ?? releases.first
    }

    /// The character before the version must be a letter, `-` or `_`. A digit
    /// or `.` there means the tag is a longer version that merely ends in this
    /// one (`12.20`, `1.2.20` for `2.20`).
    private static func isPrefixed(tag: String, version: String) -> Bool {
        guard !version.isEmpty, tag.count > version.count, tag.hasSuffix(version) else { return false }
        let before = tag[tag.index(tag.endIndex, offsetBy: -version.count - 1)]
        return before.isLetter || before == "-" || before == "_"
    }
}
