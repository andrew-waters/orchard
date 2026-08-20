import Foundation
import Testing
@testable import Orchard

@MainActor
struct CommandPaletteCatalogTests {

    private func catalog(
        containers: [Container] = [],
        machines: [Machine] = [],
        systemRunning: Bool = true
    ) -> [PaletteEntry] {
        CommandPaletteCatalog.entries(
            containers: containers,
            images: [makeImage(reference: "docker.io/library/nginx:latest")],
            mounts: [],
            machines: machines,
            clusters: [],
            providers: [],
            sandboxes: [],
            dnsDomains: [DNSDomain(domain: "test.local", isDefault: true)],
            networks: [makeNetwork(id: "default")],
            systemRunning: systemRunning)
    }

    private func ids(_ entries: [PaletteEntry]) -> [String] { entries.map(\.id) }

    @Test("A running container gets stop/console/logs verbs; a stopped one gets start/logs")
    func containerVerbsAreStateAware() throws {
        let entries = catalog(containers: [
            try makeContainer(id: "web", status: "running"),
            try makeContainer(id: "db", status: "stopped"),
        ])
        let all = ids(entries)
        #expect(all.contains("container:web:stop"))
        #expect(all.contains("container:web:console"))
        #expect(all.contains("container:web:logs"))
        #expect(!all.contains("container:web:start"))
        #expect(all.contains("container:db:start"))
        #expect(all.contains("container:db:logs"))
        #expect(!all.contains("container:db:stop"))
        #expect(!all.contains("container:db:console"))
    }

    @Test("System actions flip between start and stop/restart with the daemon state")
    func systemActionsAreStateAware() {
        let running = ids(catalog(systemRunning: true))
        #expect(running.contains("action:stopSystem"))
        #expect(running.contains("action:restartSystem"))
        #expect(!running.contains("action:startSystem"))

        let stopped = ids(catalog(systemRunning: false))
        #expect(stopped.contains("action:startSystem"))
        #expect(!stopped.contains("action:stopSystem"))
        #expect(!stopped.contains("action:restartSystem"))
    }

    @Test("Machine verbs are state-aware")
    func machineVerbs() {
        let entries = catalog(machines: [
            makeMachine(id: "buildbox", status: "running"),
            makeMachine(id: "spare", status: "stopped"),
        ])
        let all = ids(entries)
        #expect(all.contains("machine:buildbox:stop"))
        #expect(!all.contains("machine:buildbox:boot"))
        #expect(all.contains("machine:spare:boot"))
        #expect(!all.contains("machine:spare:stop"))
    }

    @Test("The empty query shows the curated list: no verb entries, running containers first")
    func emptyQueryIsCurated() throws {
        let entries = catalog(containers: [
            try makeContainer(id: "aaa-stopped", status: "stopped"),
            try makeContainer(id: "zzz-running", status: "running"),
        ])
        let ranked = CommandPaletteCatalog.rank(entries, query: "")
        let all = ids(ranked)
        #expect(all.contains("container:zzz-running"))
        #expect(!all.contains {
            $0.hasSuffix(":stop") || $0.hasSuffix(":start") || $0.hasSuffix(":console") || $0.hasSuffix(":logs")
        })
        let runningIndex = try #require(all.firstIndex(of: "container:zzz-running"))
        let stoppedIndex = try #require(all.firstIndex(of: "container:aaa-stopped"))
        #expect(runningIndex < stoppedIndex)
    }

    @Test("A verb query ranks the verb entry first")
    func verbQueryRanksVerbFirst() throws {
        let entries = catalog(containers: [try makeContainer(id: "db", status: "running")])
        let ranked = CommandPaletteCatalog.rank(entries, query: "stop db")
        #expect(ranked.first?.id == "container:db:stop")
    }

    @Test("An entity query ranks the entity above its verbs and unrelated entries")
    func entityQueryRanksEntityFirst() throws {
        let entries = catalog(containers: [try makeContainer(id: "db", status: "running")])
        let ranked = CommandPaletteCatalog.rank(entries, query: "db")
        #expect(ranked.first?.id == "container:db")
    }

    @Test("Navigation entries match their tab names")
    func navigationMatches() {
        let ranked = CommandPaletteCatalog.rank(catalog(), query: "networks")
        #expect(ranked.contains { $0.id == "nav:networks" })
    }

    @Test("Non-matching entries are excluded")
    func nonMatchesExcluded() throws {
        let entries = catalog(containers: [try makeContainer(id: "db", status: "running")])
        let ranked = CommandPaletteCatalog.rank(entries, query: "qqqqxxxx")
        #expect(ranked.isEmpty)
    }
}
