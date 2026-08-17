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

    @Test("keyed by .name, with stable.url and homepage extracted from the real brew info --json=v2 shape")
    func decodesRealFixture() throws {
        let info = ProcessBrewClient.parseFormulaInfo(try Fixture.data("brew-formula-info-sample", extension: "json"))
        #expect(info["node"]?.stableURL == "https://nodejs.org/dist/v26.7.0/node-v26.7.0.tar.xz")
        #expect(info["node"]?.homepage == "https://nodejs.org/")
        #expect(info["jq"]?.stableURL == "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.tar.gz")
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
