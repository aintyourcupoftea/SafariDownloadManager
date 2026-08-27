import Foundation

struct Download: Identifiable, Equatable {
    let id: String            // aria2 gid
    let name: String
    let path: String
    let status: String        // active | waiting | paused | complete | error | removed
    let total: Int64
    let completed: Int64
    let speed: Int64
    let connections: Int
    let error: String?

    init?(_ raw: [String: Any]) {
        guard let gid = raw["gid"] as? String else { return nil }
        id = gid
        status = raw["status"] as? String ?? "unknown"
        total     = Int64(raw["totalLength"]     as? String ?? "0") ?? 0
        completed = Int64(raw["completedLength"] as? String ?? "0") ?? 0
        speed     = Int64(raw["downloadSpeed"]   as? String ?? "0") ?? 0
        connections = Int(raw["connections"] as? String ?? "0") ?? 0
        let files = raw["files"] as? [[String: Any]] ?? []
        let p = files.first?["path"] as? String ?? ""
        path = p
        name = p.isEmpty ? gid : (p as NSString).lastPathComponent
        let e = raw["errorMessage"] as? String
        error = (e?.isEmpty == false) ? e : nil
    }

    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    var isRunning: Bool { status == "active" }
    var isDone: Bool { status == "complete" }
    var isFailed: Bool { status == "error" }

    var etaText: String {
        guard isRunning, speed > 0, total > completed else { return "" }
        let s = Int(Double(total - completed) / Double(speed))
        if s >= 3600 { return "\(s/3600)h \((s%3600)/60)m left" }
        if s >= 60   { return "\(s/60)m \(s%60)s left" }
        return "\(s)s left"
    }

    var icon: String {
        switch (name as NSString).pathExtension.lowercased() {
        case "dmg", "pkg", "app":               return "shippingbox.fill"
        case "zip", "tar", "gz", "7z", "rar", "tgz", "xz", "bz2": return "doc.zipper"
        case "mp4", "mkv", "avi", "mov", "webm": return "film.fill"
        case "mp3", "flac", "wav", "m4a":        return "music.note"
        case "pdf", "epub":                      return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo.fill"
        case "iso", "img", "bin":                return "opticaldisc.fill"
        default:                                  return "arrow.down.doc.fill"
        }
    }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }
}
