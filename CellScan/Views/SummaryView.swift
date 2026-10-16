import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    var pass: Pass
    var onViewMap: () -> Void
    var onExport: () -> Void
    var onDelete: () -> Void
    var onDone: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        // Merge once per render; every section below reads from this.
        let cells = pass.mergedCells(gridMeters: settingsStore.settings.cellMergeMeters,
                                     average: settingsStore.settings.averageCells)
        let breakdown = CoverageBreakdown(cells: cells)
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    completeHeader.padding(.top, 14)
                    topStats(cells: breakdown.totalCells).padding(.top, 22)

                    Text("COVERAGE BREAKDOWN")
                        .sectionHeader()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24).padding(.bottom, 9)

                    CoverageBar(segments: breakdown.segments.map { ($0.rat.color, $0.fraction) }, height: 11)
                        .accessibilityHidden(true)
                    breakdownRows(breakdown.segments).padding(.top, 13)

                    if breakdown.deadCells > 0 { deadZoneBanner(breakdown.deadCells).padding(.top, 13) }
                    if pass.samples.isEmpty { emptyBanner.padding(.top, 13) }

                    actions.padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete this pass?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Pass", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone. Export first if you want to keep the data.")
        }
    }

    private var completeHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.success.opacity(0.14)).frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(Theme.success.opacity(0.4), lineWidth: 1))
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.success)
            }
            .accessibilityHidden(true)
            Text("Pass complete")
                .font(.system(size: 23, weight: .bold))
                .padding(.top, 13)
            HStack(spacing: 7) {
                Circle().fill(pass.carrierColor).frame(width: 8, height: 8)
                Text("\(pass.carrierLabel) · \(RelativeDate.string(pass.startedAt)) · \(pass.durationString) · \(settingsStore.settings.distanceString(miles: pass.distanceMiles))")
                    .multilineTextAlignment(.center)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.textDim)
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }

    private func topStats(cells: Int) -> some View {
        HStack(spacing: 10) {
            bigStat("\(cells)", "cells captured")
            bigStat("\(pass.samples.count)", "raw samples")
        }
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .light, design: .monospaced))
                .foregroundStyle(Color(hex: 0xF4F6F8))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func breakdownRows(_ segments: [CoverageBreakdown.Segment]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                HStack {
                    DotLabel(color: seg.rat.color, text: seg.rat.label)
                        .font(.system(size: 14.5))
                    Spacer()
                    Text("\(seg.count) cells · \(seg.percent)%")
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x9AA3AD))
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if idx < segments.count - 1 {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
        .padding(.horizontal, 15)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func deadZoneBanner(_ deadCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.dangerSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(deadCount) dead zone\(deadCount == 1 ? "" : "s") found")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF4A0A8))
                Text("No service recorded at \(deadCount) location\(deadCount == 1 ? "" : "s") along the route")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x9AA3AD))
            }
            Spacer()
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
        .background(Color(hex: 0xF43F5E).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color(hex: 0xF43F5E).opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var emptyBanner: some View {
        Text("This pass has no readable samples, so there is nothing to map or export.")
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 13, radius: 14)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            BigButton(title: "View Map", kind: .primary, systemIcon: "map", action: onViewMap)
                .accessibilityIdentifier("summary.viewMap")
                .disabled(pass.samples.isEmpty)
            BigButton(title: "Export CSV", kind: .secondary, systemIcon: "square.and.arrow.up", action: onExport)
                .accessibilityIdentifier("summary.export")
                .disabled(pass.samples.isEmpty)
            HStack(spacing: 28) {
                Button("Delete") { confirmDelete = true }
                    .foregroundStyle(Theme.dangerSoft)
                    .accessibilityIdentifier("summary.delete")
                Button("Done", action: onDone)
                    .foregroundStyle(Color(hex: 0x8A929B))
                    .accessibilityIdentifier("summary.done")
            }
            .font(.system(size: 15))
            .padding(.top, 4)
        }
    }
}
