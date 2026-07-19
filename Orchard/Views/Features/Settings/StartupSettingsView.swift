import SwiftUI
struct StartupSettingsView: View {
	@EnvironmentObject private var containerListService: ContainerListService
	@EnvironmentObject private var startupSequenceService: StartupSequenceService
	@State private var isShowingAddGroupPrompt = false
	@State private var newGroupName = ""
	@State private var showStatusMessage = true

	private var availableContainerIDs: [String] {
		let configuredIDs = startupSequenceService.sequence.groups.flatMap { $0.containers.map(\.containerID) }
		return Set(containerListService.containers.map { $0.configuration.id } + configuredIDs).sorted()
	}

	private var validationMessage: String? {
		startupSequenceService.sequence.validationError(
			availableContainerIDs: Set(containerListService.containers.map { $0.configuration.id }))
	}

	var body: some View {
		Form {
			Section {
				Toggle(
					"Run startup sequence when Orchard opens",
					isOn: Binding(
						get: { startupSequenceService.sequence.isEnabled },
						set: { isEnabled in
							var sequence = startupSequenceService.sequence
							sequence.isEnabled = isEnabled
							startupSequenceService.updateSequence(sequence)
						}))

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
			}

			if startupSequenceService.sequence.groups.isEmpty {
				Section("Groups") {
					ContentUnavailableView {
						Label("No startup groups", systemImage: "square.stack.3d.up")
					} description: {
						Text("Add a group to build the launch graph.")
					} actions: {
						Button("Add Group", systemImage: "plus") {
							newGroupName = ""
							isShowingAddGroupPrompt = true
						}
					}
					.frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
				}
			} else {
				ForEach(startupSequenceService.sequence.groups.indices, id: \.self) { index in
					StartupGroupEditor(
						group: startupSequenceService.sequence.groups[index],
						allGroups: startupSequenceService.sequence.groups,
						containerIDs: availableContainerIDs,
						startupSequence: startupSequenceService.sequence,
						onChange: { updateGroup(index, with: $0) },
						onMoveUp: { moveGroup(index, by: -1) },
						onMoveDown: { moveGroup(index, by: 1) },
						onDelete: { deleteGroup(index) })
				}
			}

			if !startupSequenceService.sequence.groups.isEmpty {
				Section {
					HStack {
						Spacer()
						Button("Add Group", systemImage: "plus") {
							newGroupName = ""
							isShowingAddGroupPrompt = true
						}
						Spacer()
					}
				}
			}

			Section {
				HStack {
					Button("Run Sequence", systemImage: "play.fill") {
						startupSequenceService.run(
							availableContainerIDs: Set(containerListService.containers.map { $0.configuration.id }))
					}
					.disabled(startupSequenceService.isRunning || validationMessage != nil)

					Button("Stop Owned Containers", systemImage: "stop.fill") {
						Task { await startupSequenceService.stopSequenceOwnedContainers() }
					}
					.disabled(startupSequenceService.sequenceOwnedContainerIDs.isEmpty && !startupSequenceService.isRunning)
				}

				if showStatusMessage {
					Label(startupSequenceService.state.displayText, systemImage: "info.circle")
						.foregroundStyle(.secondary)
				}
			}
		}
		.formStyle(.grouped)
		.alert("Add Group", isPresented: $isShowingAddGroupPrompt) {
			TextField("Group name", text: $newGroupName)
			Button("Cancel", role: .cancel) { }
			Button("Add") {
				addGroup(named: newGroupName)
			}
			.disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
		} message: {
			Text("Enter a name for the startup group.")
		}
		.task(id: startupSequenceService.state) {
			if startupSequenceService.state == .completed {
				showStatusMessage = true
				try? await Task.sleep(for: .seconds(5))
				if !Task.isCancelled {
					showStatusMessage = false
				}
			} else {
				showStatusMessage = true
			}
		}
	}

	private func addGroup(named name: String) {
		let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedName.isEmpty else { return }
		var sequence = startupSequenceService.sequence
		sequence.groups.append(StartupGroup(name: trimmedName))
		startupSequenceService.updateSequence(sequence)
	}

	private func updateGroup(_ index: Int, with group: StartupGroup) {
		var sequence = startupSequenceService.sequence
		guard sequence.groups.indices.contains(index) else { return }
		sequence.groups[index] = group
		startupSequenceService.updateSequence(sequence)
	}

	private func moveGroup(_ index: Int, by offset: Int) {
		var sequence = startupSequenceService.sequence
		let destination = index + offset
		guard sequence.groups.indices.contains(index), sequence.groups.indices.contains(destination) else { return }
		sequence.groups.swapAt(index, destination)
		startupSequenceService.updateSequence(sequence)
	}

	private func deleteGroup(_ index: Int) {
		var sequence = startupSequenceService.sequence
		guard sequence.groups.indices.contains(index) else { return }
		sequence.groups.remove(at: index)
		startupSequenceService.updateSequence(sequence)
	}
}

private struct StartupGroupEditor: View {
	let group: StartupGroup
	let allGroups: [StartupGroup]
	let containerIDs: [String]
	let startupSequence: StartupSequence
	let onChange: (StartupGroup) -> Void
	let onMoveUp: () -> Void
	let onMoveDown: () -> Void
	let onDelete: () -> Void

	var body: some View {
		let containersInOtherGroups = Set(
			allGroups
				.filter { $0.id != group.id }
				.flatMap { $0.containers.map(\.containerID) })

		Section {
			if group.containers.isEmpty {
				ContentUnavailableView {
					Label("No containers", systemImage: "shippingbox")
				} description: {
					Text("Add a container to this startup group.")
				} actions: {
					Button("Add Container", systemImage: "plus", action: addContainer)
				}
				.frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
			} else {
				ForEach(group.containers) { container in
					StartupGroupContainerEditor(
						container: container,
						containerIDs: containerIDs,
						allGroups: allGroups,
						disabledContainerIDs: containersInOtherGroups,
						startupSequence: startupSequence,
						onChange: { updateContainer(container.id, with: $0) },
						onDelete: { deleteContainer(container.id) })
				}
			}

			if !group.containers.isEmpty {
				Button("Add Container", systemImage: "plus", action: addContainer)
					.disabled(containerIDs.allSatisfy { id in
						group.containers.contains { $0.containerID == id } || containersInOtherGroups.contains(id)
					})
					.frame(maxWidth: .infinity, alignment: .center)
			}
		} header: {
			HStack {
				HStack {
					Text(group.name)
					Menu {
						ForEach(allGroups.filter { $0.id != group.id }) { candidate in
							Toggle(candidate.name, isOn: Binding(
								get: { group.waitForGroupIDs.contains(candidate.id) },
								set: { selected in
									var dependencies = group.waitForGroupIDs
									if selected {
										if !dependencies.contains(candidate.id) { dependencies.append(candidate.id) }
									} else {
										dependencies.removeAll { $0 == candidate.id }
									}
									onChange(StartupGroup(id: group.id, name: group.name, containers: group.containers, waitForGroupIDs: dependencies))
								}))
								.disabled(startupSequence.wouldCreateGroupDependency(groupID: group.id, dependencyID: candidate.id) && !group.waitForGroupIDs.contains(candidate.id))
								}
					} label: {
						Label(
							groupPrerequisiteLabel,
							systemImage: "arrow.trianglehead.turn.up.right.diamond")
					}
				}
				Spacer()
				Button("Move up", systemImage: "chevron.up", action: onMoveUp)
					.labelStyle(.iconOnly)
					.buttonStyle(.plain)
				Button("Move down", systemImage: "chevron.down", action: onMoveDown)
					.labelStyle(.iconOnly)
					.buttonStyle(.plain)
				Button("Delete group", systemImage: "trash", action: onDelete)
					.labelStyle(.iconOnly)
					.foregroundStyle(.red)
                .buttonStyle(.plain)
		}
			.controlSize(.small)
	}
	}

	private var groupPrerequisiteLabel: String {
		switch group.waitForGroupIDs.count {
		case 0:
			return "No group prerequisites"
		case 1:
			return "Wait for \(allGroups.first { $0.id == group.waitForGroupIDs[0] }?.name ?? "group")"
		default:
			return "Wait for \(group.waitForGroupIDs.count) groups"
		}
	}

	private func addContainer() {
		let containersInOtherGroups = Set(
			allGroups
				.filter { $0.id != group.id }
				.flatMap { $0.containers.map(\.containerID) })
		guard let id = containerIDs.first(where: { id in
			!group.containers.contains { $0.containerID == id } && !containersInOtherGroups.contains(id)
		}) else { return }
		var containers = group.containers
		containers.append(StartupGroupContainer(containerID: id))
		onChange(StartupGroup(id: group.id, name: group.name, containers: containers, waitForGroupIDs: group.waitForGroupIDs))
	}

	private func updateContainer(_ id: UUID, with container: StartupGroupContainer) {
		var containers = group.containers
		guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
		containers[index] = container
		onChange(StartupGroup(id: group.id, name: group.name, containers: containers, waitForGroupIDs: group.waitForGroupIDs))
	}

	private func deleteContainer(_ id: UUID) {
		var containers = group.containers
		containers.removeAll { $0.id == id }
		onChange(StartupGroup(id: group.id, name: group.name, containers: containers, waitForGroupIDs: group.waitForGroupIDs))
	}
}

private struct StartupGroupContainerEditor: View {
	let container: StartupGroupContainer
	let containerIDs: [String]
	let allGroups: [StartupGroup]
	let disabledContainerIDs: Set<String>
	let startupSequence: StartupSequence
	let onChange: (StartupGroupContainer) -> Void
	let onDelete: () -> Void

	var body: some View {
		HStack {
			HStack {
			Menu {
				ForEach(containerIDs, id: \.self) { id in
					Button {
						onChange(StartupGroupContainer(id: container.id, containerID: id, waitForContainerIDs: container.waitForContainerIDs))
					} label: {
						if id == container.containerID {
							Label(id, systemImage: "checkmark")
						} else {
							Text(id)
						}
					}
					.disabled(disabledContainerIDs.contains(id) && id != container.containerID)
				}
			} label: {
				Label(container.containerID, systemImage: "shippingbox")
			}

			Menu {
				ForEach(allGroups) { group in
					let ids = group.containers.map(\.containerID).filter { $0 != container.containerID }
					if !ids.isEmpty {
						Section(group.name) {
							ForEach(ids, id: \.self) { id in
								prerequisiteToggle(for: id)
							}
						}
					}
				}

				let groupedIDs = Set(allGroups.flatMap { $0.containers.map(\.containerID) })
				let ungroupedIDs = containerIDs.filter { !$0.isEmpty && !groupedIDs.contains($0) && $0 != container.containerID }
				if !ungroupedIDs.isEmpty {
					Section("Available containers") {
						ForEach(ungroupedIDs, id: \.self) { id in
							prerequisiteToggle(for: id)
						}
					}
				}
			} label: {
				Label(
					containerPrerequisiteLabel,
					systemImage: "arrow.trianglehead.turn.up.right.diamond")
			}
			}
			Spacer()
			Button("Delete container", systemImage: "trash", action: onDelete)
				.labelStyle(.iconOnly)
				.foregroundStyle(.red)
                .buttonStyle(.plain)
		}
		.controlSize(.small)
	}

	@ViewBuilder
	private func prerequisiteToggle(for id: String) -> some View {
		Toggle(id, isOn: Binding(
			get: { container.waitForContainerIDs.contains(id) },
			set: { selected in
				var dependencies = container.waitForContainerIDs
				if selected {
					if !dependencies.contains(id) { dependencies.append(id) }
				} else {
					dependencies.removeAll { $0 == id }
				}
				onChange(StartupGroupContainer(id: container.id, containerID: container.containerID, waitForContainerIDs: dependencies))
			}))
		.disabled(startupSequence.wouldCreateContainerDependency(containerID: container.containerID, dependencyID: id) && !container.waitForContainerIDs.contains(id))
	}

	private var containerPrerequisiteLabel: String {
		switch container.waitForContainerIDs.count {
		case 0:
			return "No prerequisites"
		case 1:
			return "Wait for \(container.waitForContainerIDs[0])"
		default:
			return "Wait for \(container.waitForContainerIDs.count) containers"
		}
	}
}

#Preview("Startup Groups") {
	let certbotID = UUID()
	let websitesID = UUID()
	let servicesID = UUID()
	let groups = [
		StartupGroup(
			id: certbotID,
			name: "Certbot",
			containers: [
				StartupGroupContainer(containerID: "certbot_aepornis"),
				StartupGroupContainer(containerID: "certbot_pugnier"),
				StartupGroupContainer(containerID: "certbot_tazintosh")]),
		StartupGroup(
			id: websitesID,
			name: "Websites",
			containers: [
				StartupGroupContainer(containerID: "mysql"),
				StartupGroupContainer(containerID: "php"),
				StartupGroupContainer(containerID: "php7"),
				StartupGroupContainer(containerID: "nginx", waitForContainerIDs: ["mysql", "php", "php7"])],
				waitForGroupIDs: [certbotID, servicesID]),
		StartupGroup(
			id: servicesID,
			name: "Services",
			containers: [
				StartupGroupContainer(containerID: "mosquitto", waitForContainerIDs: ["nodered"]),
				StartupGroupContainer(containerID: "nodered", waitForContainerIDs: ["mosquitto", "mysql"]),
				StartupGroupContainer(containerID: "emby"),
				StartupGroupContainer(containerID: "hotline"),
				StartupGroupContainer(containerID: "minecraft")],
			waitForGroupIDs: [certbotID, websitesID])
	]
	let containerIDs = groups.flatMap { $0.containers.map(\.containerID) }
	let sequence = StartupSequence(groups: groups)

	Form {
		ForEach(groups) { group in
			StartupGroupEditor(
				group: group,
				allGroups: groups,
				containerIDs: containerIDs,
				startupSequence: sequence,
				onChange: { _ in },
				onMoveUp: { },
				onMoveDown: { },
				onDelete: { })
		}
		}
		.formStyle(.grouped)
	.frame(width: 640, height: 760)
}
