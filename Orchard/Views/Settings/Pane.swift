import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedTab: SettingsTab = .general
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""

    enum SettingsTab: String, CaseIterable {
        case general = "general"
        case registries = "registries"
        case dns = "dns"

        var title: String {
            switch self {
            case .general:
                return "General"
            case .registries:
                return "Registries"
            case .dns:
                return "DNS"
            }
        }

        var icon: String {
            switch self {
            case .general:
                return "gearshape"
            case .registries:
                return "server.rack"
            case .dns:
                return "network"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environmentObject(containerService)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            RegistrySettingsView()
                .environmentObject(containerService)
                .tabItem {
                    Label("Registries", systemImage: "server.rack")
                }
                .tag(SettingsTab.registries)

            DNSSettingsView()
                .environmentObject(containerService)
                .tabItem {
                    Label("DNS", systemImage: "network")
                }
                .tag(SettingsTab.dns)
        }
        .frame(width: 600, height: 500)
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .onChange(of: containerService.errorMessage) { _, newValue in
            if let error = newValue {
                errorMessage = error
                showingErrorAlert = true
                containerService.errorMessage = nil
            }
        }
        .onChange(of: containerService.successMessage) { _, newValue in
            if let success = newValue {
                successMessage = success
                showingSuccessAlert = true
                containerService.successMessage = nil
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(ContainerService())
    }
}
