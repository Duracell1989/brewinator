import Foundation
import Testing

@testable import Brewinator

@Suite("ProcessBrewClient.parseOutdated")
struct BrewClientParseOutdatedTests {
    @Test("empty data throws invalidOutdatedOutput")
    func emptyDataThrows() {
        #expect(throws: BrewClientError.invalidOutdatedOutput) {
            try ProcessBrewClient.parseOutdated(Data())
        }
    }

    @Test("garbled JSON throws invalidOutdatedOutput")
    func garbledJSONThrows() {
        let data = Data("not json".utf8)
        #expect(throws: BrewClientError.invalidOutdatedOutput) {
            try ProcessBrewClient.parseOutdated(data)
        }
    }

    @Test("valid response with no outdated packages decodes to empty arrays")
    func emptyArraysDecode() throws {
        let data = Data(#"{"formulae":[],"casks":[]}"#.utf8)
        let result = try ProcessBrewClient.parseOutdated(data)
        #expect(result.formulae.isEmpty)
        #expect(result.casks.isEmpty)
    }

    @Test("formulae and casks decode with first installed version and current version")
    func decodesEntries() throws {
        let json = """
            {
              "formulae": [
                {"name": "node", "installed_versions": ["22.0.0"], "current_version": "23.0.0"}
              ],
              "casks": [
                {"name": "obsidian", "installed_versions": ["1.0.0"], "current_version": "1.1.0"}
              ]
            }
            """
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))

        #expect(result.formulae == [OutdatedPackageInfo(name: "node", installedVersion: "22.0.0", currentVersion: "23.0.0", kind: .formula)])
        #expect(result.casks == [OutdatedPackageInfo(name: "obsidian", installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .cask)])
    }

    @Test("missing installed_versions entry defaults to empty string")
    func missingInstalledVersionsDefaultsEmpty() throws {
        let json = #"{"formulae":[{"name":"foo","installed_versions":[],"current_version":"1.0.0"}],"casks":[]}"#
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))
        #expect(result.formulae.first?.installedVersion == "")
    }

    /// `cmd/outdated.rb:195` emits `name: f.full_name`, so a tapped formula
    /// arrives slash-qualified and is split back apart here at the boundary.
    @Test("a tapped formula's slash-qualified name is split into short name + fullName")
    func splitsTappedFormulaName() throws {
        let json = """
            {
              "formulae": [
                {"name": "someone/tap/sometool", "installed_versions": ["0.4.0"], "current_version": "0.4.1"}
              ],
              "casks": []
            }
            """
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))

        #expect(result.formulae.first?.name == "sometool")
        #expect(result.formulae.first?.fullName == "someone/tap/sometool")
    }

    @Test("a core formula (name == full_name) is unchanged — fullName mirrors name")
    func coreFormulaNameIsUnchanged() throws {
        let json = #"{"formulae":[{"name":"node","installed_versions":["22.0.0"],"current_version":"23.0.0"}],"casks":[]}"#
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))

        #expect(result.formulae.first?.name == "node")
        #expect(result.formulae.first?.fullName == "node")
    }

    @Test("a trailing slash doesn't produce an empty name")
    func trailingSlashKeepsRawName() throws {
        let json = #"{"formulae":[{"name":"someone/tap/","installed_versions":["1.0.0"],"current_version":"1.1.0"}],"casks":[]}"#
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))

        #expect(result.formulae.first?.name == "someone/tap/")
        #expect(result.formulae.first?.fullName == "someone/tap/")
    }

    /// Cask tokens never contain a slash, so the cask branch must not split.
    @Test("cask tokens pass through with fullName mirroring name")
    func caskTokensPassThrough() throws {
        let json = #"{"formulae":[],"casks":[{"name":"obsidian","installed_versions":["1.0.0"],"current_version":"1.1.0"}]}"#
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))

        #expect(result.casks.first?.name == "obsidian")
        #expect(result.casks.first?.fullName == "obsidian")
    }

    @Test("one malformed entry is skipped, not the whole decode aborted")
    func oneMalformedEntryIsSkippedNotFatal() throws {
        let json = """
            {
              "formulae": [
                {"name": "node", "installed_versions": ["22.0.0"], "current_version": "23.0.0"},
                {"name": "broken", "current_version": "1.0.0"}
              ],
              "casks": []
            }
            """
        let result = try ProcessBrewClient.parseOutdated(Data(json.utf8))
        #expect(result.formulae == [OutdatedPackageInfo(name: "node", installedVersion: "22.0.0", currentVersion: "23.0.0", kind: .formula)])
    }
}

@Suite("ProcessBrewClient.run")
struct BrewClientRunTests {
    @Test("large stderr output does not deadlock — stdout and stderr must drain concurrently", .timeLimit(.minutes(1)))
    func largeStderrOutputDoesNotDeadlock() throws {
        let client = ProcessBrewClient(brewPath: "/bin/bash")
        // 200KB comfortably exceeds the ~64KB OS pipe buffer that would fill
        // and block the child if stderr weren't drained while stdout is.
        let data = try client.run(arguments: ["-c", "yes | head -c 200000 >&2; echo ok"])
        #expect(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
    }

    @Test("a non-zero exit status throws processFailed instead of being treated as success")
    func nonZeroExitThrows() {
        let client = ProcessBrewClient(brewPath: "/bin/bash")
        #expect(throws: BrewClientError.processFailed(exitCode: 7)) {
            try client.run(arguments: ["-c", "exit 7"])
        }
    }
}

@Suite("ProcessBrewClient.parseFormulaInfo")
struct BrewClientParseFormulaInfoTests {
    @Test("empty data returns an empty dictionary rather than throwing — brew info failures cost resolution, not the sync")
    func emptyDataReturnsEmptyDictionary() {
        #expect(ProcessBrewClient.parseFormulaInfo(Data()).isEmpty)
    }

    @Test("garbled JSON returns an empty dictionary")
    func garbledJSONReturnsEmptyDictionary() {
        #expect(ProcessBrewClient.parseFormulaInfo(Data("not json".utf8)).isEmpty)
    }

    @Test("keyed by .full_name, with stable.url, head.url and homepage extracted from the real brew info --json=v2 shape")
    func decodesRealFixture() throws {
        let info = ProcessBrewClient.parseFormulaInfo(try Fixture.data("brew-formula-info-sample", extension: "json"))
        #expect(info["node"]?.stableURL == "https://nodejs.org/dist/v26.7.0/node-v26.7.0.tar.xz")
        #expect(info["node"]?.homepage == "https://nodejs.org/")
        #expect(info["node"]?.headURL == "https://github.com/nodejs/node.git")
        #expect(info["jq"]?.stableURL == "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.tar.gz")
    }

    /// Most formulae have no `head do` block at all, so the key is simply
    /// absent rather than null.
    @Test("a formula with no head block decodes to a nil headURL")
    func missingHeadDecodesToNil() {
        let json = #"{"formulae":[{"name":"jq","urls":{"stable":{"url":"https://example.test/jq.tar.gz"}}}],"casks":[]}"#
        let info = ProcessBrewClient.parseFormulaInfo(Data(json.utf8))

        #expect(info["jq"]?.stableURL == "https://example.test/jq.tar.gz")
        #expect(info["jq"]?.headURL == nil)
    }

    /// `brew info` reports a tapped formula's `name` short and only `full_name`
    /// slash-qualified — the opposite of `brew outdated`, which is what made
    /// the two unjoinable.
    @Test("a tapped formula is keyed by its full name, not its short name")
    func keysTappedFormulaByFullName() {
        let json = """
            {
              "formulae": [
                {
                  "name": "sometool",
                  "full_name": "someone/tap/sometool",
                  "homepage": "https://example.com/sometool",
                  "urls": {"stable": {"url": "https://example.com/sometool/v0.4.0.tar.gz"}}
                }
              ],
              "casks": []
            }
            """
        let info = ProcessBrewClient.parseFormulaInfo(Data(json.utf8))

        #expect(info["someone/tap/sometool"]?.homepage == "https://example.com/sometool")
        #expect(info["sometool"] == nil)
    }

    /// Optional in the decoder as insurance against trimmed `brew info` output.
    @Test("an entry with no full_name falls back to name")
    func fallsBackToNameWhenFullNameMissing() {
        let json = #"{"formulae":[{"name":"node","homepage":"https://nodejs.org/"}],"casks":[]}"#
        let info = ProcessBrewClient.parseFormulaInfo(Data(json.utf8))

        #expect(info["node"]?.homepage == "https://nodejs.org/")
    }
}

@Suite("ProcessBrewClient.parseCaskInfo")
struct BrewClientParseCaskInfoTests {
    @Test("empty data returns an empty dictionary rather than throwing")
    func emptyDataReturnsEmptyDictionary() {
        #expect(ProcessBrewClient.parseCaskInfo(Data()).isEmpty)
    }

    @Test("keyed by .token, not .name — casks index differently in brew info's response")
    func decodesRealFixtureKeyedByToken() throws {
        let info = ProcessBrewClient.parseCaskInfo(try Fixture.data("brew-cask-info-sample", extension: "json"))
        #expect(info["rectangle"]?.homepage == "https://rectangleapp.com/")
        #expect(info["obsidian"]?.stableURL == "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.13.7/Obsidian-1.13.7.dmg")
    }
}

@Suite("ProcessBrewClient.update")
struct BrewClientUpdateTests {
    @Test("invokes `brew update --quiet` — the daily launchd run has no shell wrapper to do it first")
    func invokesBrewUpdate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let record = directory.appendingPathComponent("arguments")
        let stub = directory.appendingPathComponent("brew")
        try "#!/bin/sh\nprintf '%s' \"$*\" > '\(record.path)'\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        try await ProcessBrewClient(brewPath: stub.path).update()

        #expect(try String(contentsOf: record, encoding: .utf8) == "update --quiet")
    }

    @Test("a failing `brew update` throws, so the caller can say so instead of silently syncing against stale metadata")
    func failureThrows() async {
        let client = ProcessBrewClient(brewPath: "/usr/bin/false")

        await #expect(throws: BrewClientError.processFailed(exitCode: 1)) {
            try await client.update()
        }
    }
}
