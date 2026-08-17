import Darwin
import Foundation

protocol ArchiveStore: Sendable {
    func existingFile(for package: OutdatedPackageInfo) -> Bool
    func write(_ notes: ReleaseNotes, for package: OutdatedPackageInfo) throws
    func prune(keeping outdatedIdentities: Set<ArchivePackageIdentity>, skipList: [String]) throws -> [URL]
}

final class FileArchiveStore: ArchiveStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func existingFile(for package: OutdatedPackageInfo) -> Bool {
        FileManager.default.fileExists(atPath: targetURL(for: package).path)
    }

    /// Atomic write: content lands in a per-run temp file first and is only
    /// moved into place once confirmed non-empty, so a transient failure can
    /// never cache a blank. Callers are expected to have already checked
    /// `existingFile(for:)`.
    func write(_ notes: ReleaseNotes, for package: OutdatedPackageInfo) throws {
        guard !notes.markdown.isEmpty else { return }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = targetURL(for: package)
        let tmp = directory.appendingPathComponent(".\(target.lastPathComponent).tmp.\(ProcessInfo.processInfo.processIdentifier)")

        try notes.markdown.write(to: tmp, atomically: false, encoding: .utf8)
        try FileManager.default.moveItem(at: tmp, to: target)
    }

    /// Trashes any archived file whose package is no longer outdated (i.e.
    /// upgraded) or is now skip-listed. `outdatedIdentities` is deliberately
    /// the *unfiltered* outdated set: a still-outdated but newly-skip-listed
    /// package is trashed anyway, since it's computed before skip filtering.
    /// Keyed by `(name, kind)`, not bare name — a same-named formula and
    /// cask must not be conflated (see `packageIdentity(fromArchiveFilename:)`).
    /// `FileManager.trashItem` handles Trash-name collisions itself.
    func prune(keeping outdatedIdentities: Set<ArchivePackageIdentity>, skipList: [String]) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }

        var trashed: [URL] = []
        for file in files {
            guard let identity = Self.packageIdentity(fromArchiveFilename: file.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let isSkipped = skipList.contains { fnmatch($0, identity.name, 0) == 0 }
            guard isSkipped || !outdatedIdentities.contains(identity) else { continue }

            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: file, resultingItemURL: &trashedURL)
            if let url = trashedURL as URL? {
                trashed.append(url)
            }
        }
        return trashed
    }

    private func targetURL(for package: OutdatedPackageInfo) -> URL {
        directory.appendingPathComponent("\(package.name) (\(package.kind.rawValue)) - \(package.cleanCurrentVersion).md")
    }

    /// Strips the " (<kind>) - <version>" suffix off an archive filename's
    /// base, e.g. "node (formula) - 23.0.0" -> "node".
    static func packageName(fromArchiveFilename base: String) -> String? {
        packageIdentity(fromArchiveFilename: base)?.name
    }

    /// Parses both the bare name and the kind out of an archive filename's
    /// base, e.g. "node (formula) - 23.0.0" -> ("node", .formula). Nil if the
    /// shape doesn't parse or the kind isn't recognised.
    private static func packageIdentity(fromArchiveFilename base: String) -> ArchivePackageIdentity? {
        guard let openRange = base.range(of: " (") else { return nil }
        let name = String(base[base.startIndex..<openRange.lowerBound])
        let afterOpen = base[openRange.upperBound...]
        guard let closeIndex = afterOpen.firstIndex(of: ")") else { return nil }
        guard let kind = PackageKind(rawValue: String(afterOpen[afterOpen.startIndex..<closeIndex])) else { return nil }
        return ArchivePackageIdentity(name: name, kind: kind)
    }
}
