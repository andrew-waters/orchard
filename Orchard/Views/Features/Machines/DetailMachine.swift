import SwiftUI

struct MachineDetailView: View {
    @EnvironmentObject var machineService: MachineService
    @EnvironmentObject var statsService: StatsService
    let machineId: String
    /// Set when a stopped machine's logs show the init-missing exit — explains *why* it stopped.
    @State private var stoppedForMissingInit = false

    var body: some View {
        if let machine = machineService.machines.first(where: { $0.id == machineId }) {
            VStack(spacing: 0) {
                MachineDetailHeader(machine: machine)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if stoppedForMissingInit && machine.isStopped {
                            missingInitBanner
                        }

                        detailCard(machine)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Resource Usage")
                                .font(.headline)
                            MachineStatsPanel(machine: machine)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .onAppear { statsService.beginSampling() }
            .onDisappear { statsService.endSampling() }
            // Re-check whenever the machine or its state changes. Only stopped machines are
            // diagnosed; a running one clears the banner.
            .task(id: "\(machine.id)-\(machine.status)") {
                await checkStopReason(machine)
            }
        } else {
            Text("Machine not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var missingInitBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stopped: the image has no init system")
                    .font(.subheadline).fontWeight(.medium)
                Text("This machine booted and then exited because its image has no init system at /sbin/init. Container machines must run systemd or openrc as PID 1. Recreate it from an init-enabled image (e.g. geerlingguy/docker-ubuntu2204-ansible).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// For a stopped machine, read its logs and flag the init-missing exit. Running machines
    /// clear the flag. Failures to read logs leave the flag off (no false diagnosis).
    private func checkStopReason(_ machine: Machine) async {
        guard machine.isStopped else {
            stoppedForMissingInit = false
            return
        }
        let stdio = (try? await machineService.fetchLogs(id: machine.id)) ?? []
        let boot = (try? await machineService.fetchLogs(id: machine.id, boot: true)) ?? []
        // The `.task(id:)` is cancelled when the machine/status changes; don't let a stale
        // in-flight check overwrite the banner for the newer state.
        guard !Task.isCancelled else { return }
        stoppedForMissingInit = MachineImageAdvisor.logsIndicateMissingInit(stdio + boot)
    }

    @ViewBuilder
    private func detailCard(_ machine: Machine) -> some View {
        VStack(spacing: 0) {
            detailRow(label: "Name", value: machine.id)
            divider
            detailRow(label: "Status", value: machine.status.capitalized)
            divider
            detailRow(label: "Image", value: machine.imageReference, monospaced: true)
            divider
            detailRow(label: "Platform", value: "\(machine.platform.os)/\(machine.platform.architecture)")
            divider
            detailRow(label: "CPUs", value: "\(machine.cpus)")
            divider
            detailRow(label: "Memory", value: ByteFormat.memory(machine.memoryBytes))
            divider
            detailRow(label: "Disk", value: machine.diskSizeBytes.map { ByteFormat.string($0) } ?? "—")
            divider
            detailRow(label: "Home Mount", value: machine.homeMount)
            divider
            detailRow(label: "Nested Virt", value: machine.virtualization ? "Enabled" : "Disabled")
            if let kernelPath = machine.kernelPath {
                divider
                detailRow(label: "Kernel", value: kernelPath, monospaced: true)
            }
            divider
            detailRow(label: "IP Address", value: machine.ipAddress ?? "—", monospaced: true)
            if let user = machine.userSetup {
                divider
                detailRow(label: "User", value: "\(user.username) (uid \(user.uid), gid \(user.gid))")
            }
            if let containerId = machine.containerId {
                divider
                detailRow(label: "Container ID", value: containerId, monospaced: true)
            }
            divider
            detailRow(label: "Created", value: formatted(machine.createdDate))
            divider
            detailRow(label: "Started", value: formatted(machine.startedDate))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var divider: some View { Divider().padding(.leading, 140) }

    @ViewBuilder
    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
