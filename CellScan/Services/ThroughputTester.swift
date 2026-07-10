import Foundation

struct ThroughputResult {
    var downMbps: Double?
    var upMbps: Double?
    var latencyMs: Double?
}

/// Runs a real, bounded download / upload / latency probe against Cloudflare's
/// public speed endpoints. Kept small and capped so a pass doesn't burn much data.
final class ThroughputTester {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 10
        cfg.allowsCellularAccess = true
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// One probe: latency, then a capped download, then a small upload.
    /// `downloadBytes` is adaptive — the engine shrinks it in weak coverage.
    func measure(downloadBytes: Int = 1_500_000, uploadBytes: Int = 400_000) async -> ThroughputResult {
        let latency = await measureLatency()
        let down = await measureDownload(bytes: downloadBytes)
        // Only spend upload budget if we actually have a working link.
        let up = down == nil ? nil : await measureUpload(bytes: uploadBytes)
        return ThroughputResult(downMbps: down, upMbps: up, latencyMs: latency)
    }

    // MARK: - Latency

    private func measureLatency() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let start = Date()
        do {
            _ = try await session.data(for: req)
            return Date().timeIntervalSince(start) * 1000.0
        } catch {
            return nil
        }
    }

    // MARK: - Download

    private func measureDownload(bytes: Int) async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let start = Date()
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0.02, !data.isEmpty else { return nil }
            return (Double(data.count) * 8.0) / elapsed / 1_000_000.0
        } catch {
            return nil
        }
    }

    // MARK: - Upload

    private func measureUpload(bytes: Int) async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: bytes)
        let start = Date()
        do {
            let (_, response) = try await session.upload(for: req, from: payload)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0.02 else { return nil }
            return (Double(bytes) * 8.0) / elapsed / 1_000_000.0
        } catch {
            return nil
        }
    }
}
