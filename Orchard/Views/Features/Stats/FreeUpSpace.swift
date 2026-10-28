import SwiftUI

/// Free Up Space (#159): lists what isn't in use, with sizes, and removes what the user ticks
/// once they confirm. Images start ticked; stopped containers and volumes are sections to turn
/// on, since what they hold can't be got back. What counts as unused is `DiskPurge`'s.
struct FreeUpSpaceView: View {
    /// What the sheet offers: everything, or only volumes, as Prune Volumes opens it (#161).
    enum Scope {
        case everything
        case volumes

        var initialSelection: DiskPurgeSelection {
            var selection = DiskPurgeSelection()
            if self == .volumes {
                selection.includeImages = false
                selection.includeVolumes = true
            }
            return selection
        }
    }

    var scope: Scope = .everything

    @EnvironmentObject var diskPurgeService: DiskPurgeService
    @EnvironmentObject var imageService: ImageService
    @Environment(\.dismiss) private var dismiss

    @State private var selection = DiskPurgeSelection()
    @State private var showConfirmation = false

    private var preview: DiskPurgePreview? {
        diskPurgeService.inventory.map { DiskPurge.preview($0, selection: selection) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // The service outlives the sheet: forget last time's list or result before the
            // first await, so it never shows while the new one loads.
            diskPurgeService.reset()
            selection = scope.initialSelection
            if scope == .volumes {
                await diskPurgeService.load()
            } else {
                async let images: Void = imageService.load()
                async let candidates: Void = diskPurgeService.load()
                _ = await (images, candidates)
            }
        }
        .alert(confirmationTitle, isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                guard let plan = preview?.plan else { return }
                Task { await diskPurgeService.purge(plan) }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack {
            Text(scope == .volumes ? "Prune Volumes" : "Free Up Space").font(.title2).fontWeight(.semibold)
            Spacer()
            Button(isFinished ? "Done" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(diskPurgeService.phase == .purging)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .bottom)
    }

    @ViewBuilder
    private var footer: some View {
        if diskPurgeService.phase == .ready, let preview {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(totalText(preview)).font(.subheadline).fontWeight(.medium)
                    if scope == .everything {
                        Text("Image sizes overlap where images share layers, so the space freed can be less.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(preview.plan.count == 1 ? "Remove 1 Item..." : "Remove \(preview.plan.count) Items...") {
                    showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(preview.plan.count == 0)
                .accessibilityIdentifier("free-up-space-remove")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(NSColor.separatorColor)), alignment: .top)
        }
    }

    private var isFinished: Bool {
        if case .finished = diskPurgeService.phase { return true }
        return false
    }

    // MARK: - Content by phase

    @ViewBuilder
    private var content: some View {
        switch diskPurgeService.phase {
        case .idle, .loading:
            progress("Looking for unused data...")
        case .purging:
            progress("Removing...")
        case .failed(let message):
            VStack(spacing: 12) {
                SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { Task { await diskPurgeService.load() } }
            }
            .padding()
        case .finished(let result):
            FreeUpSpaceResultView(result: result)
        case .ready:
            if let preview, let inventory = diskPurgeService.inventory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if scope == .everything {
                            imagesSection(preview, inventory)
                            containersSection(preview, inventory)
                        }
                        volumesSection(preview, inventory)
                    }
                    .padding()
                }
            }
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Sections

    private func imagesSection(_ preview: DiskPurgePreview, _ inventory: DiskPurgeInventory) -> some View {
        section(
            title: "Images",
            systemImage: "square.stack.3d.up",
            caption: "Images no container is made from, running or stopped. Images from a registry can be pulled again; one built or committed here can't.",
            isOn: $selection.includeImages,
            empty: "Every image is used by a container.",
            rows: preview.candidates.images.map { image in
                row(.image(reference: image.reference), inventory, preview,
                    size: imageSize(image.reference))
            }
        )
    }

    private func containersSection(_ preview: DiskPurgePreview, _ inventory: DiskPurgeInventory) -> some View {
        section(
            title: "Stopped Containers",
            systemImage: "shippingbox",
            caption: "Stopped containers that nothing else manages; compose services, cluster nodes, sandboxes and machines aren't listed. A container's changes to its filesystem go with it. Images and volumes only it used are listed above and below.",
            isOn: $selection.includeContainers,
            empty: "No stopped containers.",
            rows: preview.candidates.containers.map { container in
                let id = container.configuration.id
                return row(.container(id: id), inventory, preview,
                           detail: container.configuration.image.reference,
                           size: diskPurgeService.containerSizes[id] ?? .measuring)
            }
        )
    }

    private func volumesSection(_ preview: DiskPurgePreview, _ inventory: DiskPurgeInventory) -> some View {
        section(
            title: "Volumes",
            systemImage: "cylinder",
            caption: "Volumes no container mounts. What's in a volume can't be got back once it's removed. Anonymous volumes start ticked and named ones don't. A compose project's volumes aren't listed: they're kept while the project is down.",
            isOn: $selection.includeVolumes,
            showsToggle: scope == .everything,
            empty: "Every volume is mounted by a container.",
            rows: preview.candidates.volumes.map { volume in
                row(.volume(name: volume.name), inventory, preview,
                    detail: volume.isAnonymous ? "Anonymous" : nil,
                    size: diskPurgeService.volumeSizes[volume.name] ?? .measuring)
            }
        )
    }

    private func section(
        title: String,
        systemImage: String,
        caption: String,
        isOn: Binding<Bool>,
        showsToggle: Bool = true,
        empty: String,
        rows: [FreeUpSpaceRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                if isOn.wrappedValue && !rows.isEmpty {
                    let allTicked = rows.allSatisfy(\.isTicked)
                    Button(allTicked ? "Deselect All" : "Select All") {
                        for row in rows { row.$isTicked.wrappedValue = !allTicked }
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                }
                if showsToggle {
                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(rows.isEmpty)
                }
            }

            Text(caption)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary)
            } else if isOn.wrappedValue {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { $0 }
                }
                .padding(.top, 4)
            } else {
                let known = rows.compactMap { row -> Int64? in
                    if case .known(let bytes) = row.size { return bytes }
                    return nil
                }
                Text("\(rows.count) not in use\(known.isEmpty ? "" : ", \(ByteFormat.string(known.reduce(0, +)))"). Turn on to choose which to remove.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .well()
    }

    private func row(
        _ item: DiskPurgeItem,
        _ inventory: DiskPurgeInventory,
        _ preview: DiskPurgePreview,
        detail: String? = nil,
        size: MeasuredSize
    ) -> FreeUpSpaceRow {
        let byDefault = DiskPurge.isTickedByDefault(item, in: inventory)
        return FreeUpSpaceRow(
            item: item,
            detail: detail,
            freedByContainers: preview.freedByContainers.contains(item),
            size: size,
            isTicked: Binding(
                get: { selection.isTicked(item, byDefault: byDefault) },
                set: { selection.setTicked($0, item, byDefault: byDefault) }
            )
        )
    }

    // MARK: - Sizes and wording

    private func imageSize(_ reference: String) -> MeasuredSize {
        switch imageService.imageSizes[reference] {
        case .known(let size): return .known(size)
        case .failed: return .failed
        case .loading, nil: return .measuring
        }
    }

    /// The ticked items' known sizes. Images can share layers, so theirs is an upper bound.
    private func totalText(_ preview: DiskPurgePreview) -> String {
        let plan = preview.plan
        if plan.count == 0 { return "Nothing ticked" }
        let sizes = plan.imageReferences.map(imageSize)
            + plan.containerIDs.map { diskPurgeService.containerSizes[$0] ?? .measuring }
            + plan.volumeNames.map { diskPurgeService.volumeSizes[$0] ?? .measuring }
        let known = sizes.compactMap { size -> Int64? in
            if case .known(let bytes) = size { return bytes }
            return nil
        }
        let total = "Up to \(ByteFormat.string(known.reduce(0, +)))"
        if sizes.contains(.measuring) { return "\(total), and items still being measured" }
        if sizes.contains(.failed) { return "\(total), and some sizes couldn't be read" }
        return total
    }

    private var confirmationTitle: String {
        guard let plan = preview?.plan else { return "Remove?" }
        return plan.count == 1 ? "Remove 1 Item?" : "Remove \(plan.count) Items?"
    }

    private var confirmationMessage: String {
        guard let plan = preview?.plan else { return "" }
        var parts: [String] = []
        if !plan.imageReferences.isEmpty { parts.append(counted(plan.imageReferences.count, "image")) }
        if !plan.containerIDs.isEmpty { parts.append(counted(plan.containerIDs.count, "stopped container")) }
        if !plan.volumeNames.isEmpty { parts.append(counted(plan.volumeNames.count, "volume")) }
        var message = "This removes \(ListFormatter.localizedString(byJoining: parts))."
        if !plan.containerIDs.isEmpty || !plan.volumeNames.isEmpty {
            message += " Containers and volumes can't be got back."
        }
        message += " Anything that comes into use before the removal starts is left alone."
        return message
    }

    private func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

/// One candidate with its tick box, as `FreeUpSpaceView` lists them.
struct FreeUpSpaceRow: View, Identifiable {
    let item: DiskPurgeItem
    let detail: String?
    let freedByContainers: Bool
    let size: MeasuredSize
    @Binding var isTicked: Bool

    var id: DiskPurgeItem { item }

    var body: some View {
        Toggle(isOn: $isTicked) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1).truncationMode(.middle)
                        .help(item.name)
                    if let detail {
                        Text(detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if freedByContainers {
                        Text("Used only by containers ticked for removal")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                sizeText
                    .fontDesign(.monospaced).foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private var sizeText: some View {
        switch size {
        case .known(let bytes): Text(ByteFormat.string(bytes))
        case .measuring: Text("...")
        case .failed: Text("Unknown").help("The runtime couldn't say how big this is")
        }
    }
}

/// What a purge did: the space freed, what went, and anything it left or couldn't remove.
struct FreeUpSpaceResultView: View {
    let result: DiskPurgeResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    SwiftUI.Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.failures.isEmpty ? .green : .orange)
                    Text("Freed \(ByteFormat.string(Int64(clamping: result.freedBytes)))")
                        .font(.title3).fontWeight(.semibold)
                }

                if !result.removed.isEmpty {
                    list("Removed", result.removed.map(\.name))
                }
                ForEach(DiskPurgeResult.SkipReason.allCases, id: \.self) { reason in
                    let names = result.skipped.filter { $0.reason == reason }.map(\.item.name)
                    if !names.isEmpty {
                        list(reason.title, names)
                    }
                }
                if !result.failures.isEmpty {
                    list("Couldn't remove", result.failures.map { failure in
                        failure.item.map { "\($0.name): \(failure.message)" } ?? failure.message
                    })
                }
                if result.removed.isEmpty && result.skipped.isEmpty && result.failures.isEmpty {
                    Text("Nothing needed removing.").foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func list(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
