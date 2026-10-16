import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: PassStore
    var onStartPass: () -> Void
    var onOpenPass: (UUID) -> Void
    var onOpenSettings: () -> Void
    var onExport: ([UUID]) -> Void

    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDelete = false

    var body: some View {
        let recent = store.recent
        let older = store.older
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    titleBlock(recentCount: recent.count, totalCount: store.passes.count)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if !selecting {
                        startButton
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    if store.passes.isEmpty {
                        sectionHeader("RECENT")
                        emptyState
                    } else {
                        sectionHeader("LAST 7 DAYS")
                        if recent.isEmpty {
                            Text("No passes this week.")
                                .font(.system(size: 13)).foregroundStyle(Theme.textFaint)
                                .padding(.horizontal, 22).padding(.bottom, 6)
                        }
                        ForEach(recent) { pass in card(pass) }
                        if !older.isEmpty {
                            sectionHeader("EARLIER")
                            ForEach(older) { pass in card(pass) }
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
        .confirmationDialog("Delete \(selectedIDs.count) pass\(selectedIDs.count == 1 ? "" : "es")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone. Export first if you want to keep the data.")
        }
        .onChange(of: store.passes.count) { _, _ in
            // Drop selections for passes that no longer exist.
            let existing = Set(store.passes.map(\.id))
            selectedIDs.formIntersection(existing)
            if store.passes.isEmpty { selecting = false }
        }
    }

    private func card(_ pass: Pass) -> some View {
        PassCard(pass: pass, selecting: selecting, selected: selectedIDs.contains(pass.id))
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
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(selecting ? "Toggles selection" : "Opens the pass summary. Long-press to select.")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .sectionHeader()
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 8)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CellScan")
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
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Settings")
                    if !store.passes.isEmpty {
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

    private func titleBlock(recentCount: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Passes")
                .font(.system(size: 33, weight: .bold))
            Text(selecting
                 ? "\(selectedIDs.count) selected"
                 : (totalCount == recentCount
                    ? "\(recentCount) recorded · last 7 days"
                    : "\(recentCount) this week · \(totalCount) total"))
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Multi-select action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton("Combine", "square.stack.3d.up", enabled: selectedIDs.count >= 2,
                         action: combineSelected)
            actionButton("Export", "square.and.arrow.up", enabled: true) {
                let ids = orderedSelection()
                endSelecting()
                onExport(ids)
            }
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
            .padding(.vertical, 2)
            .foregroundStyle(destructive ? Theme.dangerSoft : (enabled ? Theme.accent : Theme.textFaint))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(title == "Combine" && !enabled ? "Select at least two passes to combine" : "")
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

    /// Selected pass ids in list order (newest first).
    private func orderedSelection() -> [UUID] {
        store.passes.map(\.id).filter { selectedIDs.contains($0) }
    }

    private func deleteSelected() {
        store.delete(ids: selectedIDs)
        endSelecting()
    }

    /// Merge the selected passes into one new pass (originals removed in the same
    /// save) and open the merged pass's summary.
    private func combineSelected() {
        guard let merged = store.combine(ids: orderedSelection()) else { return }
        endSelecting()
        onOpenPass(merged.id)
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
        .accessibilityHidden(true)
    }
}

/// A pass summary card.
struct PassCard: View {
    @EnvironmentObject var settingsStore: SettingsStore
    var pass: Pass
    var selecting: Bool = false
    var selected: Bool = false

    var body: some View {
        // Merge once per render; every stat below reads from this.
        let breakdown = CoverageBreakdown(cells: pass.mergedCells(
            gridMeters: settingsStore.settings.cellMergeMeters,
            average: settingsStore.settings.averageCells))
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                DotLabel(color: pass.carrierColor, text: pass.carrierLabel, size: 9)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.accent : Theme.textFaint)
                        .accessibilityLabel(selected ? "Selected" : "Not selected")
                } else {
                    Text(RelativeDate.string(pass.startedAt))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            HStack(spacing: 22) {
                miniStat("TIME", pass.durationString)
                miniStat("DIST", settingsStore.settings.distanceString(miles: pass.distanceMiles))
                miniStat("CELLS", "\(breakdown.totalCells)")
                miniStat("DEAD", "\(breakdown.deadCells)",
                         color: breakdown.deadCells > 0 ? Theme.dangerSoft : Theme.textBright)
            }
            CoverageBar(segments: breakdown.segments.map { ($0.rat.color, $0.fraction) }, height: 7)
                .accessibilityHidden(true)
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
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
