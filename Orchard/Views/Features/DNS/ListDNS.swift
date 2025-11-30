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
                        HStack {
                            SwiftUI.Image(systemName: "network")
                                .foregroundColor(.gray)
                                .frame(width: 16, height: 16)

                            Text(domain.domain)
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
}
