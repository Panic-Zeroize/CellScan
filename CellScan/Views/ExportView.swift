import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A CSV file wrapper so `.fileExporter` can write a real .csv to Files.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ExportView: View {
    let passes: [Pass]
    @Environment(\.dismiss) private var dismiss

    @State private var showingSaver = false
    @State private var copied = false
    @State private var saved = false
    @State private var errorMessage: String?

    // Built once — re-rendering a multi-thousand-row CSV on every redraw is slow.
    private let csv: String
    private let document: CSVDocument
    private let fileName: String
    private let rowCount: Int
    private let previewLines: [String]

    init(passes: [Pass]) {
        self.passes = passes
        let csv = CSV.document(for: passes)
        self.csv = csv
        self.document = CSVDocument(text: csv)
        self.fileName = CSV.fileName(for: passes)
        self.rowCount = passes.reduce(0) { $0 + $1.samples.count }
        self.previewLines = Array(csv.split(separator: "\n").prefix(6)).map(String.init)
    }

    private var byteCount: Int { csv.utf8.count }
    private var baseFilename: String { (fileName as NSString).deletingPathExtension }

    var body: some View {
        ZStack {
            Theme.bgElevated.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textBright)
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("export.back")
                    Spacer()
                }

                Text("Export CSV").font(.system(size: 28, weight: .bold))
                if passes.count > 1 {
                    Text("\(passes.count) passes combined into one file, sorted by time")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        .padding(.top, 2)
                }

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
        .fileExporter(isPresented: $showingSaver,
                      document: document,
                      contentType: .commaSeparatedText,
                      defaultFilename: baseFilename) { result in
            switch result {
            case .success:
                saved = true
            case .failure(let error):
                // Cancelling the picker is not an error worth reporting.
                if (error as NSError).code != NSUserCancelledError {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Couldn’t save the file",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((errorMessage ?? "") + "\n\nYou can still use Copy and paste the data elsewhere.")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Shows a confirmation state on a button for two seconds.
    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flag.wrappedValue = false }
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
                Text(fileName)
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                Text("\(rowCount) rows · 11 columns · \(sizeString) · UTF-8")
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
            Button {
                showingSaver = true
            } label: {
                pillLabel(saved ? "Saved" : "Save",
                          systemImage: saved ? "checkmark" : "square.and.arrow.down",
                          primary: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.save")

            Button {
                UIPasteboard.general.string = csv
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                flash($copied)
            } label: {
                pillLabel(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc",
                          primary: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.copy")
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

    private var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
