import Foundation

protocol VersionTagged {
    var tagName: String { get }
}

enum VersionMatcher {
    /// Drops the cask build-number suffix after a comma, then the formula
    /// revision suffix (`_1`, `_2`, ...). Anchored to `_[0-9]+$` — a bare
    /// underscore-digit *anywhere* would also strip a legitimate
    /// underscore-digit segment that has real version data after it (e.g.
    /// `3.9_1.2.3`); only a pure digit run at the true end is a revision
    /// suffix.
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
    /// either side, falling back to the first element (releases list newest
    /// first).
    static func matchRelease<T: VersionTagged>(in releases: [T], version: String) -> T? {
        let target = version.lowercased().hasPrefix("v") ? String(version.lowercased().dropFirst()) : version.lowercased()
        let exact = releases.first { release in
            let tag = release.tagName.lowercased()
            let strippedTag = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return strippedTag == target
        }
        return exact ?? releases.first
    }
}
