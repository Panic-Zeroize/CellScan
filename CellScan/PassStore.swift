import Foundation
import Combine

/// Serial queue for every disk write (passes + recording checkpoints). Sharing
/// one queue guarantees a checkpoint can never land after the pass it belongs
/// to was saved and the checkpoint cleared.
enum Persistence {
    static let queue = DispatchQueue(label: "com.cellscan.persistence", qos: .utility)
}

/// A message the UI should surface (load/save failures, recovered recordings).
struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// Owns the list of saved passes and keeps it in sync with disk.
final class PassStore: ObservableObject {
    @Published private(set) var passes: [Pass] = []
    @Published var alert: AppAlert?

    private let archive: PassArchive

    init(archive: PassArchive = .standard) {
        self.archive = archive
        let result = archive.load()
        passes = result.passes

        var messages: [String] = []
        if let issue = result.issue { messages.append(issue) }

        // A checkpoint only survives if the app died mid-recording.
        if let recovered = archive.takeCheckpoint(),
           !passes.contains(where: { $0.id == recovered.id }) {
            passes.append(recovered)
            sortPasses()
            // Saved synchronously: the checkpoint file is already consumed, so the
            // recovered pass must be on disk before launch continues.
            do {
                try archive.save(passes)
                messages.append("A recording that was interrupted (\(recovered.samples.count) samples, \(recovered.carrierLabel)) was recovered and saved.")
            } catch {
                try? archive.writeCheckpoint(recovered)   // retry on next launch
                messages.append("An interrupted recording was found but couldn’t be saved yet (\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)). It will be retried next launch.")
            }
        }
        if !messages.isEmpty {
            alert = AppAlert(title: result.issue == nil ? "Recording recovered" : "Saved data issue",
                             message: messages.joined(separator: "\n\n"))
        }
    }

    // MARK: - Queries

    private static let recentWindow: TimeInterval = 7 * 24 * 3600

    /// Passes from the last 7 days, newest first.
    var recent: [Pass] {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        return passes.filter { $0.startedAt >= cutoff }
    }

    /// Older passes, newest first (still saved, exportable and deletable).
    var older: [Pass] {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        return passes.filter { $0.startedAt < cutoff }
    }

    func pass(with id: UUID) -> Pass? {
        passes.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Saves a pass. With `finishingRecording`, the crash-recovery checkpoint is
    /// removed only once the pass is safely on disk — if the save fails, the
    /// checkpoint survives and the pass is recovered on next launch.
    func add(_ pass: Pass, finishingRecording: Bool = false) {
        passes.removeAll { $0.id == pass.id }
        passes.append(pass)
        sortPasses()
        persist(clearingCheckpoint: finishingRecording)
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        passes.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Merges the given passes into one new pass and removes the originals in a
    /// single save, so a failure can't leave both or neither on disk.
    @discardableResult
    func combine(ids: [UUID]) -> Pass? {
        let selected = ids.compactMap { pass(with: $0) }
        guard selected.count >= 2 else { return nil }
        let merged = Pass.combining(selected)
        let remove = Set(selected.map(\.id))
        passes.removeAll { remove.contains($0.id) }
        passes.append(merged)
        sortPasses()
        persist()
        return merged
    }

    // MARK: - Disk

    private func sortPasses() {
        passes.sort { $0.startedAt > $1.startedAt }
    }

    /// Encodes and writes off the main thread; failures are surfaced as an alert.
    private func persist(clearingCheckpoint: Bool = false) {
        let snapshot = passes
        let archive = self.archive
        Persistence.queue.async { [weak self] in
            do {
                try archive.save(snapshot)
                if clearingCheckpoint { archive.clearCheckpoint() }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.alert = AppAlert(title: "Couldn’t save", message: message)
                }
            }
        }
    }
}
