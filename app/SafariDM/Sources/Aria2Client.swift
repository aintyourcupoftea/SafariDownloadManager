import Foundation

/// Minimal JSON-RPC client for the aria2 daemon.
/// The daemon is the single source of truth for download state - the UI never
/// keeps its own copy, so it cannot drift from what is actually on disk.
actor Aria2Client {
    static let shared = Aria2Client()
    private let endpoint = URL(string: "http://127.0.0.1:6800/jsonrpc")!
    private var secret: String = ""

    func loadSecret(from path: String) {
        secret = (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func call(_ method: String, _ params: [Any] = []) async throws -> Any {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": "sdm", "method": method,
            "params": ["token:\(secret)"] + params,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let err = obj["error"] as? [String: Any] {
            throw NSError(domain: "aria2", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(err["message"] ?? "rpc error")"])
        }
        return obj["result"] ?? [:]
    }

    private static let fields = ["gid", "status", "totalLength", "completedLength",
                                 "downloadSpeed", "files", "errorMessage", "connections"]

    func fetchAll() async -> [Download] {
        async let active  = try? call("aria2.tellActive",  [Self.fields])
        async let waiting = try? call("aria2.tellWaiting", [0, 50, Self.fields])
        async let stopped = try? call("aria2.tellStopped", [0, 50, Self.fields])
        let groups = [await active, await waiting, await stopped]
        var out: [Download] = []
        for g in groups {
            for raw in (g as? [[String: Any]]) ?? [] {
                if let d = Download(raw) { out.append(d) }
            }
        }
        return out
    }

    func pause(_ gid: String)  { Task { _ = try? await call("aria2.pause",  [gid]) } }
    func resume(_ gid: String) { Task { _ = try? await call("aria2.unpause",[gid]) } }
    func remove(_ gid: String) {
        Task {
            // active jobs need forceRemove; finished ones only accept removeDownloadResult
            _ = try? await call("aria2.forceRemove", [gid])
            _ = try? await call("aria2.removeDownloadResult", [gid])
        }
    }
    func purgeFinished() { Task { _ = try? await call("aria2.purgeDownloadResult") } }
    func ping() async -> Bool { ((try? await call("aria2.getVersion")) != nil) }
}
