import SwiftUI

struct DNSListView: View {
    @EnvironmentObject var containerService: ContainerService
    @Binding var selectedDNSDomain: String?
    @Binding var lastSelectedDNSDomain: String?
    @Binding var showAddDNSDomainSheet: Bool
    @FocusState var listFocusedTab: TabSelection?

    var body: some View {
        VStack(spacing: 0) {
            if containerService.isDNSLoading {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading DNS domains...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if containerService.dnsDomains.isEmpty {
                VStack {
                    SwiftUI.Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("No DNS Domains")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add a domain to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // DNS domain list
                List(selection: $selectedDNSDomain) {
                    ForEach(containerService.dnsDomains) { domain in
                        let containerCount = containerService.containers.filter { container in
                            if let containerDomain = container.configuration.dns.domain {
                                return containerDomain == domain.domain
                            }
                            return container.configuration.dns.searchDomains.contains(domain.domain)
                        }.count

                        HStack {
                            SwiftUI.Image(systemName: "network")
                                .foregroundColor(.gray)
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading) {
                                Text(domain.domain)
                                if containerCount > 0 {
                                    Text("\(containerCount) container\(containerCount == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No containers")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if domain.isDefault {
                                Text("DEFAULT")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(8)
                        .contextMenu {
                            if !domain.isDefault {
                                Button("Make Default") {
                                    let currentSelection = selectedDNSDomain
                                    DispatchQueue.main.async {
                                        Task {
                                            await containerService.setDefaultDNSDomain(domain.domain)
                                            // Restore selection after operation
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                selectedDNSDomain = currentSelection
                                            }
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button("Delete Domain") {
                                confirmDNSDomainDeletion(domain: domain.domain)
                            }
                        }
                        .tag(domain.domain)
                    }
                }
                .listStyle(PlainListStyle())
                .animation(.easeInOut(duration: 0.3), value: containerService.dnsDomains)
                .focused($listFocusedTab, equals: .dns)
                .onChange(of: selectedDNSDomain) { _, newValue in
                    lastSelectedDNSDomain = newValue
                }
            }

            // Add domain button
            HStack {
                Button(action: {
                    showAddDNSDomainSheet = true
                }) {
                    HStack {
                        SwiftUI.Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("Add Domain")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddDNSDomainSheet) {
            AddDomainView()
                .environmentObject(containerService)
            }
        }

        private func confirmDNSDomainDeletion(domain: String) {
            let alert = NSAlert()
            alert.messageText = "Delete DNS Domain"
            alert.informativeText = "Are you sure you want to delete '\(domain)'? This requires administrator privileges."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                Task { await containerService.deleteDNSDomain(domain) }
            }
        }
    }
