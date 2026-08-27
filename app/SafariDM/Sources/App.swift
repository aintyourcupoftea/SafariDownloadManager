import SwiftUI

/// Runtime state lives in SDM_HOME, exactly as the CLI and daemons resolve it.
/// Anything else and the app reads a stale rpc.secret and every call fails auth
/// while the UI just shows an empty list.
let sdmRoot: String = ProcessInfo.processInfo.environment["SDM_HOME"]
    ?? (FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SafariDownloadManager").path)

@main
struct SafariDMApp: App {
    @StateObject private var model = AppModel(root: sdmRoot)

    var body: some Scene {
        Window("Safari Download Manager", id: "main") {
            ContentView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 620, height: 480)

        MenuBarExtra {
            MenuBarPanel().environmentObject(model)
        } label: {
            Image(systemName: model.activeCount > 0
                  ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.activeCount > 0
                     ? "\(model.activeCount) downloading" : "No active downloads")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(get: { model.intercepting },
                                         set: { model.setIntercepting($0) }))
                    .toggleStyle(.switch).labelsHidden().scaleEffect(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            if model.downloads.isEmpty {
                Text("Nothing here yet")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.downloads.prefix(6)) { DownloadRow(d: $0) }
                    }.padding(6)
                }.frame(maxHeight: 300)
            }
            Divider()
            HStack {
                Button("Open Manager") { openWindow(id: "main") }
                    .buttonStyle(.plain).font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .frame(width: 400)
    }
}
