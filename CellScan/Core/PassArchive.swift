import Foundation

/// Disk persistence for passes plus the crash-recovery checkpoint of a pass
/// that is still recording. Foundation-only and synchronous so it can be unit
/// tested; `PassStore` calls it from a background queue.
struct PassArchive {
    let directory: URL

    var passesURL: URL { directory.appendingPathComponent("passes.json") }
    var checkpointURL: URL { directory.appendingPathComponent("recording-checkpoint.json") }

    /// The app's Documents directory (falls back to tmp if it is unavailable).
    static var standard: PassArchive {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PassArchive(directory: dir)
    }

    enum ArchiveError: LocalizedError {
        case encode(Error)
        case write(Error)

        var errorDescription: String? {
            switch self {
            case .encode(let e): return "Couldn’t prepare your passes for saving (\(e.localizedDescription))."
            case .write(let e): return "Couldn’t save your passes to storage (\(e.localizedDescription)). Free some space and try again."
            }
        }
    }

    struct LoadResult {
        var passes: [Pass]
        /// Human-readable problem worth telling the user about (nil when clean).
        var issue: String?
        /// Where an unreadable / partially readable file was preserved.
        var backupURL: URL?
    }

    // MARK: - Coding

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    // MARK: - Passes

    /// Loads every readable pass. Never throws and never loses data: if the file
    /// is corrupt or some passes can't be read, the original file is copied
    /// aside before the app can overwrite it, and `issue` explains what happened.
    func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: passesURL.path) else { return LoadResult(passes: []) }

        let data: Data
        do {
            data = try Self.read(passesURL)
        } catch {
            let backup = preserve(passesURL, tag: "unreadable")
            return LoadResult(passes: [],
                              issue: "Saved passes couldn’t be read (\(error.localizedDescription)). The file was kept as a backup.",
                              backupURL: backup)
        }
        if data.isEmpty { return LoadResult(passes: []) }

        guard let lossy = try? Self.makeDecoder().decode([Lossy<Pass>].self, from: data) else {
            let backup = preserve(passesURL, tag: "corrupt")
            return LoadResult(passes: [],
                              issue: "Saved passes were damaged and couldn’t be opened. The original file was kept as a backup in the app’s Files folder.",
                              backupURL: backup)
        }

        var passes = lossy.compactMap(\.value)
        let dropped = lossy.count - passes.count
        // Duplicate ids would make SwiftUI lists misbehave; keep the first copy.
        var seen = Set<UUID>()
        passes = passes.filter { seen.insert($0.id).inserted }
        passes.sort { $0.startedAt > $1.startedAt }

        if dropped > 0 {
            let backup = preserve(passesURL, tag: "partial")
            return LoadResult(passes: passes,
                              issue: "\(dropped) saved pass\(dropped == 1 ? "" : "es") couldn’t be read and \(dropped == 1 ? "was" : "were") skipped. The original file was kept as a backup.",
                              backupURL: backup)
        }
        return LoadResult(passes: passes)
    }

    /// Atomically writes all passes (write-to-temp then rename, so a crash or a
    /// full disk mid-write can never leave a half-written file behind).
    func save(_ passes: [Pass]) throws {
        let data: Data
        do { data = try Self.makeEncoder().encode(passes) } catch { throw ArchiveError.encode(error) }
        try write(data, to: passesURL)
    }

    // MARK: - Recording checkpoint

    /// Snapshot of the pass currently being recorded, refreshed periodically so
    /// a crash, force-quit or iOS termination loses at most a few samples.
    func writeCheckpoint(_ pass: Pass) throws {
        let data: Data
        do { data = try Self.makeEncoder().encode(pass) } catch { throw ArchiveError.encode(error) }
        try write(data, to: checkpointURL)
    }

    /// Returns the interrupted pass (if any had samples) and removes the file.
    /// An unreadable checkpoint is preserved as a backup rather than deleted.
    func takeCheckpoint() -> Pass? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: checkpointURL.path) else { return nil }
        guard let data = try? Self.read(checkpointURL),
              let pass = try? Self.makeDecoder().decode(Pass.self, from: data) else {
            _ = preserve(checkpointURL, tag: "corrupt")
            clearCheckpoint()
            return nil
        }
        clearCheckpoint()
        return pass.samples.isEmpty ? nil : pass
    }

    func clearCheckpoint() {
        try? FileManager.default.removeItem(at: checkpointURL)
    }

    /// Removes the checkpoint only if it belongs to the given pass, so clearing a
    /// stale recovered pass can never delete a newer, live recording's checkpoint.
    func clearCheckpoint(ifPassID id: UUID) {
        guard let data = try? Self.read(checkpointURL),
              let pass = try? Self.makeDecoder().decode(Pass.self, from: data),
              pass.id == id else { return }
        clearCheckpoint()
    }

    // MARK: - Helpers

    /// Reads a file, short-circuiting zero-length files (Foundation's file reader
    /// leaks its scratch buffer for empty files on some platforms).
    private static func read(_ url: URL) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber, size.intValue == 0 { return Data() }
        return try Data(contentsOf: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ArchiveError.write(error)
        }
    }

    /// Copies a file aside as `<name>.<tag>-<timestamp>.json`; returns its URL.
    @discardableResult
    func preserve(_ url: URL, tag: String) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let base = url.deletingPathExtension().lastPathComponent
        let dest = directory.appendingPathComponent("\(base).\(tag)-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}
