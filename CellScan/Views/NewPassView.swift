import SwiftUI

struct NewPassView: View {
    @ObservedObject var engine: RecordingEngine
    var onCancel: () -> Void
    var onStart: (Carrier, Bool) -> Void

    @State private var carrier: Carrier = .verizon
    @State private var throughputOn = true

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CARRIER — TAG MANUALLY")
                            .sectionHeader().padding(.top, 8).padding(.bottom, 6).padding(.horizontal, 2)
                        carrierPicker
                        infoRow("iOS no longer reports carrier name — tag the SIM you’re recording. Every row in this pass is stamped with it.")
                            .padding(.top, 9)

                        Text("METRICS")
                            .sectionHeader().padding(.top, 24).padding(.bottom, 6).padding(.horizontal, 2)
                        throughputCard

                        Text("PERMISSION")
                            .sectionHeader().padding(.top, 24).padding(.bottom, 6).padding(.horizontal, 2)
                        permissionCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                bottomBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            carrier = engine.carrier
            engine.requestPermission()
        }
    }

    private var topBar: some View {
        ZStack {
            Text("New Pass").font(.system(size: 16, weight: .semibold))
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0x8A929B))
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var carrierPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(Carrier.allCases.enumerated()), id: \.element) { idx, c in
                Button {
                    carrier = c
                } label: {
                    HStack(spacing: 11) {
                        Circle().fill(c.color).frame(width: 11, height: 11)
                        Text(c == .other ? "Other…" : c.displayName)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if carrier == c {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 15)
                }
                .buttonStyle(.plain)
                if idx < Carrier.allCases.count - 1 {
                    Divider().overlay(Color.white.opacity(0.05)).padding(.leading, 15)
                }
            }
        }
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var throughputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Throughput test").font(.system(size: 16))
                    Text("Measures real download speed")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Toggle("", isOn: $throughputOn)
                    .labelsHidden()
                    .tint(Theme.success)
            }
            if throughputOn {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13)).foregroundStyle(Color(hex: 0xFB923C))
                    Text("Burns cellular data — up to ~1–3 GB / hour. Test is adaptive, capped per probe, and pauses in dead zones.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xE0B894))
                }
                .padding(11)
                .background(Color(hex: 0xFB923C).opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(hex: 0xFB923C).opacity(0.28), lineWidth: 1))
                .padding(.top, 13)
            }
        }
        .card(padding: 15, radius: 16)
    }

    private var permissionCard: some View {
        HStack(spacing: 11) {
            Image(systemName: "location.fill")
                .foregroundStyle(Theme.accent)
            (Text("Uses ").foregroundColor(Color(hex: 0xAEB6BE))
             + Text("When-In-Use").foregroundColor(Color(hex: 0xD7DBDF)).bold()
             + Text(" location with background updates — the blue bar shows while recording.")
                .foregroundColor(Color(hex: 0xAEB6BE)))
                .font(.system(size: 13))
        }
        .card(padding: 14, radius: 16)
    }

    private var bottomBar: some View {
        VStack {
            BigButton(title: "Start Recording", kind: .danger, systemIcon: "record.circle") {
                onStart(carrier, throughputOn)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.bg)
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
    }

    private func infoRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}
