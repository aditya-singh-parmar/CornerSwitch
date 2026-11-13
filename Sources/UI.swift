import SwiftUI

let accent = Color(red: 0.42, green: 0.36, blue: 1.0)
let accentDeep = Color(red: 0.25, green: 0.17, blue: 0.62)

struct Actions {
    var switchNow: () -> Void
    var openPrivacy: () -> Void
    var refresh: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var checkUpdates: () -> Void
    var installUpdate: () -> Void
    var quit: () -> Void
}

struct PopoverView: View {
    @ObservedObject var state: AppState
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !state.hasPermission { permissionBanner }
            section("Arrangement") {
                ArrangementView(state: state)
                Text("Drag the other Mac to where it sits on your desk.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Devices") { devices }
            section("Behaviour") { behaviour }
            Button(action: actions.switchNow) {
                Label("Switch to channel \(state.target)", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .disabled(state.devices.isEmpty)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("CornerSwitch").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(state: state)
        }
    }

    private var subtitle: String {
        if let ch = state.thisChannel { return "This Mac is channel \(ch)" }
        return "Version \(state.version)"
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Input Monitoring needed").font(.callout.weight(.semibold))
                Text("macOS requires it before an app can talk to a keyboard. Turn on CornerSwitch, then reopen it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Privacy Settings", action: actions.openPrivacy).controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    @ViewBuilder private var devices: some View {
        if state.devices.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.secondary)
                Text("Keyboard and mouse are on another computer.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(state.devices.sorted { $0.isKeyboard && !$1.isKeyboard }) { d in
                    HStack(spacing: 10) {
                        Image(systemName: d.isKeyboard ? "keyboard" : "computermouse")
                            .frame(width: 22).foregroundStyle(accent)
                        Text(d.name).font(.callout)
                        Spacer()
                        Text(d.channel.map { "Ch \($0)" } ?? "Ch ?")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.14)))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
    }

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Push to switch").font(.callout)
                Spacer()
                Picker("", selection: $state.resistance) {
                    ForEach(Resistance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            HStack {
                Text("Send devices to").font(.callout)
                Spacer()
                Picker("", selection: $state.targetChannel) {
                    Text("Auto (channel \(state.thisChannel == 2 ? 1 : 2))").tag(0)
                    ForEach(1...3, id: \.self) { Text("Channel \($0)").tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Switching enabled", $state.enabled)
            row("Launch at login", Binding(get: { state.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
            row("Install updates automatically", $state.autoUpdate)
            HStack {
                updateControl
                Spacer()
                Button("Quit", action: actions.quit).buttonStyle(.borderless)
            }
            .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    @ViewBuilder private var updateControl: some View {
        switch state.update {
        case .available(let v):
            Button("Update to \(v)", action: actions.installUpdate).buttonStyle(.borderless).foregroundStyle(accent)
        case .installing:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Updating…") }
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .failed(let m):
            Button("v\(state.version) · \(m)", action: actions.checkUpdates).buttonStyle(.borderless).foregroundStyle(.secondary)
                .lineLimit(1)
        case .upToDate, .idle:
            Button("v\(state.version) · Check for updates", action: actions.checkUpdates)
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Toggle("", isOn: on).labelsHidden()
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            content()
        }
    }
}

struct StatusPill: View {
    @ObservedObject var state: AppState
    var body: some View {
        let (text, color): (String, Color) =
            !state.hasPermission ? ("Needs access", .orange)
            : !state.enabled ? ("Paused", .gray)
            : state.devices.isEmpty ? ("Away", .blue)
            : ("Active", .green)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

final class DragModel: ObservableObject {
    static let shared = DragModel()
    @Published var offset: CGSize = .zero
}

/// This Mac in the middle; drag or click to put the other Mac on any side.
struct ArrangementView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var dragModel = DragModel.shared
    private var drag: CGSize { dragModel.offset }

    private let canvas = CGSize(width: 308, height: 196)
    private let me = CGSize(width: 104, height: 64)
    private let other = CGSize(width: 76, height: 48)
    private let gap: CGFloat = 12

    private func center(for side: Side) -> CGPoint {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        switch side {
        case .left: return CGPoint(x: c.x - me.width / 2 - gap - other.width / 2, y: c.y)
        case .right: return CGPoint(x: c.x + me.width / 2 + gap + other.width / 2, y: c.y)
        case .top: return CGPoint(x: c.x, y: c.y - me.height / 2 - gap - other.height / 2)
        case .bottom: return CGPoint(x: c.x, y: c.y + me.height / 2 + gap + other.height / 2)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04))

            ForEach(Side.allCases.filter { $0 != state.side }, id: \.self) { side in
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: other.width, height: other.height)
                    .contentShape(Rectangle())
                    .position(center(for: side))
                    .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.side = side } }
            }

            VStack(spacing: 3) {
                Image(systemName: "laptopcomputer").font(.system(size: 20, weight: .medium))
                Text("This Mac").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: me.width, height: me.height)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)))
            .shadow(color: accent.opacity(0.35), radius: 6, y: 2)
            .position(x: canvas.width / 2, y: canvas.height / 2)

            VStack(spacing: 2) {
                Image(systemName: "desktopcomputer").font(.system(size: 15))
                Text("Ch \(state.target)").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(accent)
            .frame(width: other.width, height: other.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .position(center(for: state.side))
            .offset(drag)
            .gesture(DragGesture()
                .onChanged { dragModel.offset = $0.translation }
                .onEnded { v in
                    let start = center(for: state.side)
                    let p = CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height)
                    let nearest = Side.allCases.min {
                        hypot(center(for: $0).x - p.x, center(for: $0).y - p.y)
                            < hypot(center(for: $1).x - p.x, center(for: $1).y - p.y)
                    }!
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        state.side = nearest
                        dragModel.offset = .zero
                    }
                })

            arrow
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// Small chevron in the gap showing which way to push.
    private var arrow: some View {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let (dx, dy, name): (CGFloat, CGFloat, String) = {
            switch state.side {
            case .left: return (-(me.width / 2 + gap / 2), 0, "chevron.left")
            case .right: return (me.width / 2 + gap / 2, 0, "chevron.right")
            case .top: return (0, -(me.height / 2 + gap / 2), "chevron.up")
            case .bottom: return (0, me.height / 2 + gap / 2, "chevron.down")
            }
        }()
        return Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accent)
            .position(x: c.x + dx, y: c.y + dy)
            .opacity(drag == .zero ? 1 : 0)
    }
}
