import SwiftUI

struct SummaryView: View {
    var pass: Pass
    var onViewMap: () -> Void
    var onDone: () -> Void

    @State private var showingExport = false

    private var cells: [Cell] { pass.cells }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    completeHeader.padding(.top, 14)
                    topStats.padding(.top, 22)

                    Text("COVERAGE BREAKDOWN")
                        .sectionHeader()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24).padding(.bottom, 9)

                    CoverageBar(segments: segments.map { ($0.rat.color, $0.fraction) }, height: 11)
                    breakdownRows.padding(.top, 13)

                    if pass.deadZoneCount > 0 { deadZoneBanner.padding(.top, 13) }

                    actions.padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) {
            ExportView(pass: pass)
                .presentationDetents([.medium, .large])
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
            Text("Pass complete")
                .font(.system(size: 23, weight: .bold))
                .padding(.top, 13)
            HStack(spacing: 7) {
                Circle().fill(pass.carrier.color).frame(width: 8, height: 8)
                Text("\(pass.carrier.displayName) · \(RelativeDate.string(pass.startedAt)) · \(pass.durationString) · \(String(format: "%.1f mi", pass.distanceMiles))")
            }
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.textDim)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var topStats: some View {
        HStack(spacing: 10) {
            bigStat("\(cells.count)", "cells captured")
            bigStat("\(pass.samples.count)", "raw samples")
        }
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .light, design: .monospaced))
                .foregroundStyle(Color(hex: 0xF4F6F8))
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var breakdownRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                HStack {
                    DotLabel(color: seg.rat.color, text: seg.rat.label)
                        .font(.system(size: 14.5))
                    Spacer()
                    Text("\(seg.count) cells · \(seg.pct)%")
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x9AA3AD))
                }
                .padding(.vertical, 10)
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

    private var deadZoneBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.dangerSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(pass.deadZoneCount) dead zone\(pass.deadZoneCount == 1 ? "" : "s") found")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF4A0A8))
                Text("No service recorded at \(pass.deadZoneCount) location\(pass.deadZoneCount == 1 ? "" : "s") along the route")
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
    }

    private var actions: some View {
        VStack(spacing: 10) {
            BigButton(title: "View Map", kind: .primary, systemIcon: "map", action: onViewMap)
            BigButton(title: "Export CSV", kind: .secondary, systemIcon: "square.and.arrow.up") {
                showingExport = true
            }
            Button("Done", action: onDone)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x8A929B))
                .padding(.top, 2)
        }
    }

    private struct Seg { var rat: RAT; var count: Int; var pct: Int; var fraction: Double }
    private var segments: [Seg] {
        let total = max(1, cells.count)
        let order: [RAT] = [.fiveG, .lte, .threeG, .none]
        return order.map { rat in
            let n = cells.filter { $0.rat == rat }.count
            return Seg(rat: rat, count: n, pct: Int((Double(n) / Double(total) * 100).rounded()),
                      fraction: Double(n) / Double(total))
        }
    }
}
