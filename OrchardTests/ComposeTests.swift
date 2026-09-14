import ComposeModel
import ComposeParser
import ComposePlanner
import Foundation
import Testing

@testable import Orchard

/// A container as the runtime would report one that a compose project created.
private func composeContainer(
    id: String,
    project: String,
    service: String,
    hash: String = "a-hash",
    status: String = "running",
    hostPorts: [Int] = [],
    network: String? = "shop_default"
) throws -> Container {
    let labels: [String: String] = [
        ProjectIdentity.projectLabel: project,
        ProjectIdentity.serviceLabel: service,
        ProjectIdentity.hashLabel: hash,
    ]
    let labelsJSON = String(data: try JSONEncoder().encode(labels), encoding: .utf8)!
    let portsJSON = hostPorts
        .map { "{ \"hostPort\": \($0), \"containerPort\": 80, \"proto\": \"tcp\" }" }
        .joined(separator: ",")
    let networkJSON = network.map { "\"\($0)\"" } ?? "null"
    let json = """
    {
      "status": "\(status)",
      "networks": [],
      "configuration": {
        "id": "\(id)",
        "networkName": \(networkJSON),
        "runtimeHandler": "vz",
        "rosetta": false,
        "labels": \(labelsJSON),
        "sysctls": {},
        "publishedPorts": [\(portsJSON)],
        "mounts": [],
        "platform": \(fixturePlatformJSON),
        "image": \(fixtureImageJSON("nginx:latest")),
        "dns": \(fixtureDNSJSON),
        "resources": { "cpus": 1, "memoryInBytes": 1024 },
        "initProcess": \(fixtureInitProcessJSON)
      }
    }
    """
    return try JSONDecoder().decode(Container.self, from: Data(json.utf8))
}

private func record(_ name: String, path: String = "/tmp/shop/compose.yaml") -> ComposeProjectRecord {
    ComposeProjectRecord(name: name, path: path, acknowledgedFindings: [], addedAt: Date())
}

@Suite("Compose projects come from labels")
struct ComposeProjectGroupingTests {
    @Test("Containers group into projects by their project label")
    func groupsByLabel() throws {
        let containers = [
            try composeContainer(id: "shop-web", project: "shop", service: "web"),
            try composeContainer(id: "shop-db", project: "shop", service: "db", status: "stopped"),
            try composeContainer(id: "blog-web", project: "blog", service: "web"),
            try makeContainer(id: "unrelated", status: "running"),
        ]
        let projects = ComposeProject.group(containers: containers, records: [])
        #expect(projects.map(\.name) == ["blog", "shop"])
        let shop = try #require(projects.first { $0.name == "shop" })
        #expect(shop.serviceNames == ["db", "web"])
        #expect(shop.containers.map { $0.configuration.id } == ["shop-db", "shop-web"])
        #expect(shop.statusText == "1 of 2 running")
        #expect(shop.isRunning)
        #expect(!shop.hasFile)
    }

    @Test("A project Orchard knows a file for shows before anything is created")
    func knownProjectWithNoContainers() throws {
        let projects = ComposeProject.group(containers: [], records: [record("shop")])
        let shop = try #require(projects.first)
        #expect(shop.name == "shop")
        #expect(shop.hasFile)
        #expect(shop.containers.isEmpty)
        #expect(shop.statusText == "Not created")
        #expect(!shop.isRunning)
    }

    @Test("A file and its containers describe one project, not two")
    func fileAndContainersMerge() throws {
        let containers = [try composeContainer(id: "shop-web", project: "shop", service: "web")]
        let projects = ComposeProject.group(containers: containers, records: [record("shop")])
        #expect(projects.count == 1)
        #expect(projects[0].hasFile)
        #expect(projects[0].statusText == "Running")
        #expect(projects[0].container(forService: "web")?.configuration.id == "shop-web")
    }

    @Test("A project with no file can still be taken down, from its labels alone")
    func downWithoutAFile() throws {
        let containers = [
            try composeContainer(id: "shop-web", project: "shop", service: "web"),
            try composeContainer(id: "shop-db", project: "shop", service: "db"),
        ]
        let project = try #require(ComposeProject.group(containers: containers, records: []).first)
        let file = ComposeService.fileFromLabels(project)
        #expect(file.services.keys.sorted() == ["db", "web"])

        let plan = try Planner.down(
            file: file,
            project: ProjectIdentity(name: "shop"),
            state: CurrentState(containers: containers.map(ComposeService.containerState(of:)))
        )
        #expect(plan.operations.map(\.summary) == [
            "stop shop-web",
            "remove shop-web",
            "stop shop-db",
            "remove shop-db",
        ])
    }
}

@Suite("The snapshot the planner sees")
struct ComposeSnapshotTests {
    @Test("A container maps onto the planner's view of one")
    func containerState() throws {
        let container = try composeContainer(
            id: "shop-web",
            project: "shop",
            service: "web",
            hash: "abc",
            status: "stopped",
            hostPorts: [8080, 8443],
            network: "shop_default"
        )
        let state = ComposeService.containerState(of: container)
        #expect(state.name == "shop-web")
        #expect(state.isRunning == false)
        #expect(state.publishedHostPorts == [8080, 8443])
        #expect(state.networkName == "shop_default")
        #expect(state.projectName == "shop")
        #expect(state.serviceName == "web")
        #expect(state.serviceHash == "abc")
    }

    @Test("A stopped container still says which network it belongs to")
    func stoppedContainerKeepsItsNetwork() throws {
        // The runtime reports no live attachments for a stopped container, so this has to come
        // from the configuration or `down` would remove a network something still needs.
        let container = try composeContainer(
            id: "shop-db", project: "shop", service: "db", status: "stopped", network: "shop_default"
        )
        #expect(container.networks.isEmpty)
        #expect(ComposeService.containerState(of: container).networkName == "shop_default")
    }
}

@Suite("A planned container becomes an Orchard create")
struct ComposeCreateSpecTests {
    private func plan(_ yaml: String) throws -> CreateOperation {
        let parsed = try ComposeFileParser.parse(
            yaml: yaml,
            options: ParseOptions(projectDirectory: "/project", environment: [:], dotEnvPath: nil)
        )
        let plan = try Planner.up(
            file: parsed.file,
            project: ProjectIdentity(name: "shop"),
            state: CurrentState()
        )
        let creates = plan.operations.compactMap { operation -> CreateOperation? in
            guard case .createContainer(let create) = operation else { return nil }
            return create
        }
        return try #require(creates.first)
    }

    @Test("Every field the create call takes comes from the file")
    func fullMapping() throws {
        let operation = try plan(
            """
            services:
              web:
                image: nginx
                container_name: the-front
                command: nginx -g "daemon off;"
                working_dir: /srv
                environment:
                  B: two
                  A: one
                ports:
                  - "127.0.0.1:8080:80"
                volumes:
                  - ./site:/usr/share/nginx/html:ro
                deploy:
                  resources:
                    limits:
                      cpus: "0.5"
                      memory: 512m
            """
        )
        let spec = ComposeService.createSpec(from: operation)
        #expect(spec.id == "the-front")
        #expect(spec.imageRef == "nginx")
        #expect(spec.environment == ["A=one", "B=two"])
        #expect(spec.commandOverride == ["nginx", "-g", "daemon off;"])
        #expect(spec.workingDirectory == "/srv")
        #expect(spec.volumes.count == 1)
        #expect(spec.volumes[0].hostPath == "/project/site")
        #expect(spec.volumes[0].containerPath == "/usr/share/nginx/html")
        #expect(spec.volumes[0].readonly)
        #expect(spec.publishedPorts.count == 1)
        #expect(spec.publishedPorts[0].hostPort == 8080)
        #expect(spec.publishedPorts[0].containerPort == 80)
        // Half a core is not a thing a VM can have, and rounding down would be the quieter
        // kind of wrong.
        #expect(spec.cpus == 1)
        #expect(spec.memoryBytes == 512 << 20)
        #expect(spec.labels[ProjectIdentity.projectLabel] == "shop")
        #expect(spec.labels[ProjectIdentity.serviceLabel] == "web")
        #expect(spec.labels[ProjectIdentity.hashLabel]?.count == 64)
        #expect(spec.networkName == "shop_default")
        #expect(spec.autoRemove == false)
    }

    @Test("A port published to one interface is not widened on the way through")
    func hostAddressSurvives() throws {
        let operation = try plan(
            """
            services:
              web:
                image: nginx
                ports:
                  - "127.0.0.1:8080:80"
            """
        )
        #expect(ComposeService.createSpec(from: operation).publishedPorts[0].hostAddress == "127.0.0.1")
    }

    @Test("A file that says nothing about resources gets the same defaults as the Run form")
    func resourceDefaults() throws {
        let operation = try plan("services:\n  web:\n    image: nginx\n")
        let spec = ComposeService.createSpec(from: operation)
        #expect(spec.cpus == ContainerRunConfig.defaultCPUs)
        #expect(spec.memoryBytes == ContainerRunConfig.defaultMemoryBytes)
    }
}

@Suite("Remembering projects")
struct ComposeProjectsPersistenceTests {
    @Test("Records survive a round trip")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-projects-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let persistence = ComposeProjectsPersistence(fileURL: url)
        let records = [
            ComposeProjectRecord(
                name: "shop",
                path: "/tmp/shop/compose.yaml",
                acknowledgedFindings: ["unhandledKey:web/restart@8:14"],
                addedAt: Date(timeIntervalSince1970: 1_000_000)
            )
        ]
        try persistence.save(records)
        #expect(persistence.load() == records)
    }

    @Test("A file that is not there, or not understood, means no projects rather than a crash")
    func missingOrCorrupt() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-projects-\(UUID().uuidString).json")
        #expect(ComposeProjectsPersistence(fileURL: missing).load().isEmpty)

        try "not json".write(to: missing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: missing) }
        #expect(ComposeProjectsPersistence(fileURL: missing).load().isEmpty)
    }
}

@Suite("Folding an image's entrypoint")
struct ComposeProcessArgumentTests {
    /// Orchard folds entrypoint, cmd and an override for every container it creates; the
    /// planner folds the same three for compose. They have to agree, or the same file would
    /// run differently in the terminal and in the app.
    @Test("The planner and the backend agree on what a container runs")
    func plannerAndBackendAgree() {
        let cases: [(entrypoint: [String]?, cmd: [String]?, override: [String])] = [
            (["/bin/tini", "--"], ["nginx"], []),
            (["/bin/tini", "--"], ["nginx"], ["sleep", "1"]),
            (nil, ["nginx"], []),
            (nil, ["nginx"], ["sleep"]),
            (nil, nil, ["sh", "-c", "echo"]),
            (nil, nil, []),
        ]
        for testCase in cases {
            #expect(
                resolveProcessArguments(
                    imageEntrypoint: testCase.entrypoint,
                    imageCmd: testCase.cmd,
                    override: testCase.override
                ) == Planner.processArguments(
                    imageEntrypoint: testCase.entrypoint,
                    imageCmd: testCase.cmd,
                    command: testCase.override
                )
            )
        }
    }
}
