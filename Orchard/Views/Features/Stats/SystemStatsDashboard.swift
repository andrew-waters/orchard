import SwiftUI

/// System-wide resource charts: every container's history summed tick-by-tick. CPU is a
/// total across containers (auto-scaled, since it can exceed 100%), memory is total used
/// vs total limit. Shown above the fleet table on the Stats tab.
struct SystemStatsDashboard: View {
    @EnvironmentObject var statsService: StatsService
    @State private var window: StatsWindow = .fiveMin

    /// Aggregate only the samples within the selected window — keeps the summation cheap
    /// even when 24h of per-container history is retained.
    private var aggregates: [StatsSample] {
        let histories = statsService.history.allSamples()
        guard let newest = histories.compactMap({ $0.last?.timestamp }).max() else { return [] }
        let cutoff = newest.addingTimeInterval(-window.seconds)
        let windowed = histories.map { $0.filter { $0.timestamp >= cutoff } }
        return aggregate(windowed)
    }

    var body: some View {
        let series = aggregates
        if series.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("System")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(StatsWindow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                StatsChartsGrid(
                    samples: series,
                    memoryLimitBytes: series.last?.memoryLimitBytes ?? 0,
                    windowSeconds: window.seconds,
                    cpuDomain: nil   // summed CPU can exceed 100% → auto-scale
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
