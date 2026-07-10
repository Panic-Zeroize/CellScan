import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                intPicker("Sample interval", selection: $settingsStore.settings.sampleIntervalSec,
                          options: AppSettings.sampleIntervals)
                intPicker("Speed test interval", selection: $settingsStore.settings.throughputIntervalSec,
                          options: AppSettings.throughputIntervals)
                doublePicker("Min distance / sample", selection: $settingsStore.settings.minSampleDistanceM,
                             options: AppSettings.distances)
                Toggle("Speed test on by default", isOn: $settingsStore.settings.throughputDefaultOn)
            } header: {
                Text("Recording")
            } footer: {
                Text("How often a GPS fix and speed probe are taken. A minimum distance skips samples while parked.")
            }

            Section {
                doublePicker("Merge radius", selection: $settingsStore.settings.cellMergeMeters,
                             options: AppSettings.mergeRadii)
                Picker("Merge mode", selection: $settingsStore.settings.averageCells) {
                    Text("Average (default)").tag(true)
                    Text("Worst-case").tag(false)
                }
            } header: {
                Text("Coverage cells")
            } footer: {
                Text("Samples within the merge radius group into one cell. Average blends their readings; Worst-case keeps the weakest.")
            }

            Section("Display") {
                Picker("Units", selection: $settingsStore.settings.metric) {
                    Text("Imperial (mph / mi)").tag(false)
                    Text("Metric (km/h / km)").tag(true)
                }
            }

            Section {
                Button(role: .destructive) {
                    settingsStore.reset()
                } label: {
                    Text("Reset to defaults")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    private func intPicker(_ title: String, selection: Binding<Int>, options: [(Int, String)]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
    }

    private func doublePicker(_ title: String, selection: Binding<Double>, options: [(Double, String)]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
    }
}