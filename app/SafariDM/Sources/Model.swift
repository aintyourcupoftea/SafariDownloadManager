import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var downloads: [Download] = []
    @Published var daemonUp = false
    @Published var lastError: String? = nil
    @Published var intercepting = false
    @Published var proxyUp = false

    /// Set at launch from SDM_ROOT so the bundle can live anywhere.
    let root: String

    init(root: String) {
        self.root = root
        Task { await Aria2Client.shared.loadSecret(from: "\(root)/state/rpc.secret") }
        refreshToggles()
        start()
    }

    private func start() {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func tick() async {
        var up = await Aria2Client.shared.ping()
        if !up {
            // Could be a rotated secret rather than a dead daemon.
            await Aria2Client.shared.reloadSecret()
            up = await Aria2Client.shared.ping()
        }
        let items = up ? await Aria2Client.shared.fetchAll() : []
        // Newest first, but anything still moving floats to the top.
        let sorted = items.sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            return a.id > b.id
        }
        await MainActor.run {
            self.daemonUp = up
            self.lastError = up ? nil
                : "Can't reach the download engine. Run `sdm status` in a terminal."
            if self.downloads != sorted { self.downloads = sorted }
            self.refreshToggles()
        }
    }

    func refreshToggles() {
        let s = (try? String(contentsOfFile: "\(root)/state/STRATEGY", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "off"
        intercepting = (s != "off")
        proxyUp = !(runShell("pgrep -f 'mitmdump --mode local' | head -1").isEmpty)
    }

    func setIntercepting(_ on: Bool) {
        try? (on ? "probe" : "off").write(toFile: "\(root)/state/STRATEGY",
                                          atomically: true, encoding: .utf8)
        intercepting = on
    }

    var activeCount: Int { downloads.filter(\.isRunning).count }
    var totalSpeed: Int64 { downloads.filter(\.isRunning).reduce(0) { $0 + $1.speed } }

    func reveal(_ d: Download) {
        guard !d.path.isEmpty else { return }
        runShell("open -R '\(d.path.replacingOccurrences(of: "'", with: "'\\''"))'")
    }

    @discardableResult
    func runShell(_ cmd: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
