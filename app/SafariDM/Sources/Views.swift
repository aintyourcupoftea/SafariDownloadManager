import SwiftUI

// MARK: - Palette

private extension Color {
    static let accentStart = Color(red: 0.34, green: 0.55, blue: 1.00)
    static let accentEnd   = Color(red: 0.55, green: 0.38, blue: 0.98)
    static let okGreen     = Color(red: 0.20, green: 0.72, blue: 0.47)
    static let failRed     = Color(red: 0.92, green: 0.34, blue: 0.34)
}

// MARK: - Progress bar

struct Bar: View {
    let fraction: Double
    let tint: LinearGradient
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Row

struct DownloadRow: View {
    let d: Download
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    private var tint: LinearGradient {
        let colors: [Color] =
            d.isFailed ? [.failRed, .failRed.opacity(0.7)]
          : d.isDone   ? [.okGreen, .okGreen.opacity(0.75)]
          : [.accentStart, .accentEnd]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private var subtitle: String {
        if let e = d.error { return e }
        switch d.status {
        case "active":
            return "\(Download.bytes(d.completed)) of \(Download.bytes(d.total))  ·  \(Download.bytes(d.speed))/s  ·  \(d.etaText)"
        case "complete": return Download.bytes(d.total)
        case "paused":   return "Paused  ·  \(Download.bytes(d.completed)) of \(Download.bytes(d.total))"
        case "waiting":  return "Queued"
        default:         return d.status.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: d.isFailed ? "exclamationmark.triangle.fill" : d.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(d.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                if !d.isDone {
                    Bar(fraction: d.fraction, tint: tint)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(d.isFailed ? Color.failRed : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !d.isDone && d.total > 0 {
                Text("\(Int(d.fraction * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 3) {
                if d.isRunning {
                    IconButton("pause.fill", "Pause") { Task { await Aria2Client.shared.pause(d.id) } }
                } else if d.status == "paused" {
                    IconButton("play.fill", "Resume") { Task { await Aria2Client.shared.resume(d.id) } }
                }
                if d.isDone {
                    IconButton("magnifyingglass", "Show in Finder") { model.reveal(d) }
                }
                IconButton("xmark", "Remove") { Task { await Aria2Client.shared.remove(d.id) } }
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct IconButton: View {
    let sys: String, help: String, action: () -> Void
    init(_ s: String, _ h: String, action: @escaping () -> Void) { sys = s; help = h; self.action = action }
    @State private var over = false
    var body: some View {
        Button(action: action) {
            Image(systemName: sys)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(over ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { over = $0 }
        .help(help)
    }
}

// MARK: - Main

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if model.downloads.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.downloads) { DownloadRow(d: $0) }
                    }
                    .padding(8)
                }
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.accentStart, .accentEnd],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Safari Download Manager").font(.system(size: 13, weight: .semibold))
                Text(model.activeCount > 0
                     ? "\(model.activeCount) active  ·  \(Download.bytes(model.totalSpeed))/s"
                     : "Idle")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.intercepting },
                                     set: { model.setIntercepting($0) }))
                .toggleStyle(.switch).labelsHidden()
                .help(model.intercepting ? "Interception on" : "Interception off")
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var empty: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .thin)).foregroundStyle(.tertiary)
            Text("No downloads yet").font(.system(size: 13, weight: .medium))
            Text(model.lastError
                 ?? (model.intercepting
                     ? "Click any download in Safari and it lands here."
                     : "Interception is off — Safari will download normally."))
                .font(.system(size: 11))
                .foregroundStyle(model.lastError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.failRed))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            StatusDot(ok: model.proxyUp,   label: "Proxy")
            StatusDot(ok: model.daemonUp,  label: "Engine")
            Spacer()
            if model.downloads.contains(where: { $0.isDone || $0.isFailed }) {
                Button("Clear finished") { Task { await Aria2Client.shared.purgeFinished() } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

struct StatusDot: View {
    let ok: Bool, label: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Color.okGreen : Color.failRed).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}
