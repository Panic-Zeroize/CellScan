import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExportView: View {
    var pass: Pass
    @Environment(\.dismiss) private var dismiss

    @State private var fileURL: URL?
    @State private var copied = false

    private var csv: String { pass.csvString() }
    private var byteCount: Int { csv.utf8.count }

    var body: some View {
        ZStack {
            Theme.bgElevated.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 16)

                Text("Export CSV").font(.system(size: 20, weight: .bold))

                fileRow.padding(.top, 15)
                preview.padding(.top, 13)

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    Text("ArcGIS auto-detects lat/lng. Over 1,000 features → publish a hosted layer or export in chunks.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)

                actionRow.padding(.top, 18)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .onAppear(perform: writeTempFile)
    }

    private var fileRow: some View {
        HStack(spacing: 12) {
            Text("CSV")
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white).tracking(0.5)
                .frame(width: 38, height: 46)
                .background(LinearGradient(colors: [Color(hex: 0x1F8A5B), Color(hex: 0x13663F)],
                                           startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(pass.csvFileName)
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                Text("\(pass.samples.count) rows · 11 columns · \(sizeString) · UTF-8")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(13)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var preview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(previewLines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(idx == 0 ? Theme.accent
                                         : (line.contains(",None,") || line.hasSuffix(",")
                                            ? Theme.dangerSoft : Color(hex: 0x9AA3AD)))
                        .lineLimit(1)
                        .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 11).padding(.leading, 12).padding(.trailing, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if let fileURL {
                ShareLink(item: fileURL) {
                    pillLabel("Share / Save", systemImage: "square.and.arrow.up", primary: true)
                }
            }
            Button {
                UIPasteboard.general.string = csv
                copied = true
            } label: {
                pillLabel(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", primary: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func pillLabel(_ title: String, systemImage: String, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title).font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(primary ? .white : Color(hex: 0xD7DBDF))
        .background(primary
                    ? AnyView(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyView(Theme.bgChip))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if !primary {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var previewLines: [String] {
        Array(csv.split(separator: "\n", omittingEmptySubsequences: false).prefix(6)).map(String.init)
    }

    private var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func writeTempFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(pass.csvFileName)
        try? csv.data(using: .utf8)?.write(to: url, options: [.atomic])
        fileURL = url
    }
}
