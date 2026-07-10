import SwiftUI

struct RecordingView: View {
    @ObservedObject var engine: RecordingEngine
    var onStop: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x16131A), Theme.bg],
                           center: .top, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                VStack(spacing: 2) {
                    Text("ELAPSED")
                        .font(.system(size: 11, weight: .semibold)).tracking(2)
                        .foregroundStyle(Theme.textFaint)
                    Text(engine.elapsedString)
                        .font(.system(size: 62, weight: .light, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xF4F6F8))
                        .monospacedDigit()
                }
                .padding(.top, 26)

                SignalBadge(rat: engine.currentRat)
                    .padding(.top, 14)

                Sparkline(rats: engine.sparks)
                    .padding(.top, 22)
                    .padding(.horizontal, 4)

                statsGrid
                    .padding(.top, 20)

                HStack(spacing: 7) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text("Map renders after you stop — saves battery while the screen is off.")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                BigButton(title: "Stop & Save", kind: .secondary, systemIcon: "stop.fill", action: onStop)
                    .tint(Theme.danger)
                    .foregroundStyle(Color(hex: 0xFF6A60))
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .onAppear { pulse = true }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(Theme.danger).frame(width: 11, height: 11)
                    .shadow(color: Theme.danger.opacity(0.7), radius: 5)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                Text("RECORDING")
                    .font(.system(size: 13, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Color(hex: 0xFF6A60))
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(engine.carrier.color).frame(width: 8, height: 8)
                Text(engine.carrier.displayName)
                    .font(.system(size: 13)).foregroundStyle(Color(hex: 0xC7CDD3))
            }
            .padding(.vertical, 6).padding(.horizontal, 11)
            .background(Theme.bgChip)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                StatTile(label: "SAMPLES", value: "\(engine.samples.count)")
                StatTile(label: "CELLS (DEDUP)", value: "\(engine.cellCount)")
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST FIX").font(.system(size: 10, weight: .semibold)).tracking(1)
                        .foregroundStyle(Theme.textFaint)
                    Text("\(engine.lastLatString), \(engine.lastLngString)")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xEDEFF2))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("±ACC").font(.system(size: 10, weight: .semibold)).tracking(1)
                        .foregroundStyle(Theme.textFaint)
                    Text(engine.accuracyString)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xEDEFF2))
                }
            }
            .padding(.vertical, 11).padding(.horizontal, 13)
            .background(Theme.bgTile)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

            HStack(spacing: 9) {
                StatTile(label: "SPEED", value: engine.speedString)
                StatTile(label: "LATENCY", value: engine.latencyString)
            }
        }
    }
}
