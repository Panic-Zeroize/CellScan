import SwiftUI
import UIKit

struct RecordingView: View {
    @ObservedObject var engine: RecordingEngine
    var onSave: () -> Void
    var onDiscard: () -> Void

    @State private var pulse = false
    @State private var confirmStop = false

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
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityLabel("Elapsed time \(engine.elapsedString)")
                }
                .padding(.top, 22)

                SignalBadge(rat: engine.currentRat)
                    .padding(.top, 12)
                    .accessibilityLabel("Radio: \(engine.currentRat.label)")

                if let warning = statusWarning {
                    warningBanner(warning)
                        .padding(.top, 14)
                }

                Sparkline(downloads: engine.sparks)
                    .padding(.top, 18)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)

                statsGrid
                    .padding(.top, 18)

                HStack(spacing: 7) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text("Keeps recording with the screen off. Progress is saved continuously.")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                BigButton(title: "Stop", kind: .secondaryDestructive, systemIcon: "stop.fill") {
                    confirmStop = true
                }
                .accessibilityIdentifier("recording.stop")
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .onAppear { pulse = true }
        .confirmationDialog("Finish this pass?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Save Pass") { onSave() }
            Button("Discard Pass", role: .destructive) { onDiscard() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("\(engine.samples.count) sample\(engine.samples.count == 1 ? "" : "s") captured. Discarding permanently deletes them.")
        }
    }

    // MARK: - Status

    private struct Warning { var icon: String; var text: String; var showSettings: Bool }

    private var statusWarning: Warning? {
        switch engine.locationAccess {
        case .denied, .restricted:
            return Warning(icon: "location.slash",
                           text: "Location access is off — nothing can be recorded.",
                           showSettings: true)
        case .notDetermined:
            return Warning(icon: "location", text: "Waiting for location permission…", showSettings: false)
        case .granted:
            if let msg = engine.gpsMessage { return Warning(icon: "exclamationmark.triangle", text: msg, showSettings: false) }
            if engine.waitingForGPS {
                return Warning(icon: "location.magnifyingglass",
                               text: "Acquiring GPS — samples resume once there’s a clear fix.",
                               showSettings: false)
            }
            return nil
        }
    }

    private func warningBanner(_ w: Warning) -> some View {
        HStack(spacing: 9) {
            Image(systemName: w.icon)
            Text(w.text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if w.showSettings {
                Button("Settings") { AppLinks.openSettings() }
                    .font(.system(size: 12.5, weight: .semibold))
            }
        }
        .foregroundStyle(Color(hex: 0xFBBF24))
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(Color(hex: 0xFBBF24).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(hex: 0xFBBF24).opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Layout

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording")
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
            .accessibilityElement(children: .combine)
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                StatTile(label: "SAMPLES", value: "\(engine.samples.count)")
                    .accessibilityIdentifier("recording.samples")
                StatTile(label: "CELLS (DEDUP)", value: "\(engine.cellCount)")
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LAST FIX").font(.system(size: 10, weight: .semibold)).tracking(1)
                        .foregroundStyle(Theme.textFaint)
                    Text("\(engine.lastLatString), \(engine.lastLngString)")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xEDEFF2))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
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
            .accessibilityElement(children: .combine)

            HStack(spacing: 9) {
                StatTile(label: "SPEED", value: engine.speedString)
                StatTile(label: "DOWN", value: engine.downloadString)
                StatTile(label: "LATENCY", value: engine.latencyString)
            }
        }
    }
}

/// Deep links out of the app.
enum AppLinks {
    /// Opens CellScan's page in the iOS Settings app (location permission etc.).
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
