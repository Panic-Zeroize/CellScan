import Foundation
import Combine

/// Persists recorded passes to a JSON file in the app's Documents directory.
final class PassStore: ObservableObject {
    @Published private(set) var passes: [Pass] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("passes.json")
    }()

    init() {
        load()
    }

    /// Passes recorded in the last 7 days, newest first (Home "Recent" list).
    var recent: [Pass] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return passes
            .filter { $0.startedAt >= cutoff }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func add(_ pass: Pass) {
        passes.insert(pass, at: 0)
        save()
    }

    func delete(_ pass: Pass) {
        passes.removeAll { $0.id == pass.id }
        save()
    }

    func pass(with id: UUID) -> Pass? {
        passes.first { $0.id == id }
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Pass].self, from: data) {
            passes = decoded.sorted { $0.startedAt > $1.startedAt }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(passes) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
