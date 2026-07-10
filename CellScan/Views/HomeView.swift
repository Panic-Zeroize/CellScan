import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: PassStore
    var onStartPass: () -> Void
    var onOpenPass: (UUID) -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passes")
                            .font(.system(size: 33, weight: .bold))
                        Text("\(store.recent.count) recorded · last 7 days")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    startButton
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    Text("RECENT")
                        .sectionHeader()
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    if store.recent.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.recent) { pass in
                            PassCard(pass: pass)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .onTapGesture { onOpenPass(pass.id) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(pass)
                                    } label: { Label("Delete Pass", systemImage: "trash") }
                                }
                        }
                    }
                }
                .padding(.bottom, 34)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

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
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
    var pass: Pass

    private var cells: [Cell] { pass.cells }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                DotLabel(color: pass.carrier.color, text: pass.carrier.displayName, size: 9)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(RelativeDate.string(pass.startedAt))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 22) {
                miniStat("TIME", pass.durationString)
                miniStat("DIST", String(format: "%.1f mi", pass.distanceMiles))
                miniStat("CELLS", "\(cells.count)")
                miniStat("DEAD", "\(pass.deadZoneCount)",
                         color: pass.deadZoneCount > 0 ? Theme.dangerSoft : Theme.textBright)
            }
            CoverageBar(segments: ratSegments, height: 7)
        }
        .card()
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
