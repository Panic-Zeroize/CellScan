import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: PassStore
    var onStartPass: () -> Void
    var onOpenPass: (UUID) -> Void
    var onOpenSettings: () -> Void
    var onCombine: ([UUID]) -> Void

    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showExport = false
    @State private var exportURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    titleBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if !selecting {
                        startButton
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    Text("RECENT")
                        .sectionHeader()
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    if store.recent.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.recent) { pass in
                            PassCard(pass: pass, selecting: selecting,
                                     selected: selectedIDs.contains(pass.id))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selecting { toggle(pass.id) } else { onOpenPass(pass.id) }
                                }
                                .onLongPressGesture {
                                    if !selecting { selecting = true }
                                    toggle(pass.id)
                                }
                        }
                    }
                }
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIDs.isEmpty { actionBar }
        }
        .sheet(isPresented: $showExport) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .confirmationDialog("Delete \(selectedIDs.count) pass\(selectedIDs.count == 1 ? "" : "es")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                LogoMark()
                Text("CELLSCAN")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textBright)
            }
            Spacer()
            if selecting {
                Button("Done") { endSelecting() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                HStack(spacing: 14) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: 0x9AA3AD))
                    }
                    if !store.recent.isEmpty {
                        Button("Select") { selecting = true }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Passes")
                .font(.system(size: 33, weight: .bold))
            Text(selecting
                 ? "\(selectedIDs.count) selected"
                 : "\(store.recent.count) recorded · last 7 days")
                .font(.system(size: 13.5))
                .foregroundStyle(selecting ? Theme.accent : Theme.textDim)
        }
    }

    private var startButton: some View {
        Button(action: onStartPass) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.16)).frame(width: 34, height: 34)
                    Circle().fill(Color.white).frame(width: 15, height: 15)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start New Pass")
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Record GPS + coverage while you drive")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 17)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.32), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Multi-select action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton("Combine", "square.stack.3d.up", enabled: selectedIDs.count >= 2) {
                onCombine(orderedSelection())
                endSelecting()
            }
            actionButton("Export", "square.and.arrow.up", enabled: true, action: exportSelected)
            actionButton("Delete", "trash", enabled: true, destructive: true) {
                confirmDelete = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }

    private func actionButton(_ title: String, _ icon: String, enabled: Bool,
                              destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(destructive ? Theme.dangerSoft : (enabled ? Theme.accent : Theme.textFaint))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textFaint)
            Text("No passes yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Text("Tap “Start New Pass” and drive to record your first coverage track.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func endSelecting() {
        selecting = false
        selectedIDs = []
    }

    /// Selected passes in the order they appear (newest first).
    private func selectedPasses() -> [Pass] {
        store.recent.filter { selectedIDs.contains($0.id) }
    }
    private func orderedSelection() -> [UUID] {
        selectedPasses().map { $0.id }
    }

    private func deleteSelected() {
        for pass in selectedPasses() { store.delete(pass) }
        endSelecting()
    }

    private func exportSelected() {
        let passes = selectedPasses()
        guard !passes.isEmpty else { return }
        let csv = passes.count == 1 ? passes[0].csvString() : Pass.combinedCSV(passes)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let name = passes.count == 1 ? passes[0].csvFileName
                                     : "cellscan_combined_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? csv.data(using: .utf8)?.write(to: url, options: [.atomic])
        exportURL = url
        showExport = true
    }
}

/// The little gradient bar-chart logo mark.
struct LogoMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.55)).frame(width: 3, height: 5)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.75)).frame(width: 3, height: 8)
            RoundedRectangle(cornerRadius: 1).fill(Color.white).frame(width: 3, height: 11)
        }
        .padding(.horizontal, 6)
        .frame(width: 30, height: 30, alignment: .bottom)
        .padding(.bottom, 7)
        .background(
            LinearGradient(colors: [Theme.accent, Color(hex: 0x4744D6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.45), radius: 7)
    }
}

/// A recent-pass summary card.
struct PassCard: View {
    @EnvironmentObject var settingsStore: SettingsStore
    var pass: Pass
    var selecting: Bool = false
    var selected: Bool = false

    private var cells: [Cell] {
        pass.mergedCells(gridMeters: settingsStore.settings.cellMergeMeters,
                         average: settingsStore.settings.averageCells)
    }
    private var deadCount: Int { cells.filter { $0.rat == .none }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                DotLabel(color: pass.carrier.color, text: pass.carrier.displayName, size: 9)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.accent : Theme.textFaint)
                } else {
                    Text(RelativeDate.string(pass.startedAt))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            HStack(spacing: 22) {
                miniStat("TIME", pass.durationString)
                miniStat("DIST", settingsStore.settings.distanceString(miles: pass.distanceMiles))
                miniStat("CELLS", "\(cells.count)")
                miniStat("DEAD", "\(deadCount)",
                         color: deadCount > 0 ? Theme.dangerSoft : Theme.textBright)
            }
            CoverageBar(segments: ratSegments, height: 7)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: selected ? 2 : 0)
        )
    }

    private func miniStat(_ label: String, _ value: String, color: Color = Theme.textBright) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).tracking(1).foregroundStyle(Theme.textFaint)
            Text(value).font(.system(size: 15, design: .monospaced)).foregroundStyle(color)
        }
    }

    private var ratSegments: [(color: Color, fraction: Double)] {
        let total = max(1, cells.count)
        let order: [RAT] = [.fiveG, .lte, .threeG, .none]
        return order.map { rat in
            let n = cells.filter { $0.rat == rat }.count
            return (rat.color, Double(n) / Double(total))
        }
    }
}

enum RelativeDate {
    static func string(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "Today · \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(time)" }
        let wd = date.formatted(.dateTime.weekday(.abbreviated))
        return "\(wd) · \(time)"
    }
}