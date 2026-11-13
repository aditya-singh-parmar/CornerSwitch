// Main window. Flat and quiet: on/off, where the other Mac sits, device status.
// Channels, push strength and updates live under Advanced.

import SwiftUI

let brand = Color(red: 0.38, green: 0.31, blue: 0.93)

struct Actions {
    var switchNow: () -> Void
    var openPrivacy: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var checkUpdates: () -> Void
    var installUpdate: () -> Void
}

final class UIModel: ObservableObject {
    static let shared = UIModel()
    @Published var dragOffset: CGSize = .zero
    @Published var showAdvanced = UserDefaults.standard.bool(forKey: "showAdvanced")
}

/// "MX KEYS S" -> "MX Keys S"
func prettyName(_ n: String) -> String {
    n.split(separator: " ").map { w in
        w.count <= 2 || w.contains(where: \.isNumber) ? String(w) : w.capitalized
    }.joined(separator: " ")
}

private let card = Color(nsColor: .controlBackgroundColor)
private let hairline = Color.primary.opacity(0.09)

struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var ui = UIModel.shared
    let actions: Actions

    var body: some View {
        Group {
            if ui.showAdvanced { advancedPage } else { home }
        }
        .padding(.horizontal, 28)
        .padding(.top, 38)
        .padding(.bottom, 24)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !state.hasPermission { permissionCard }
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arrangement").font(.system(size: 13, weight: .semibold))
                    Text("Drag Other Mac to where it sits on your desk.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ArrangementView(state: state).frame(maxWidth: .infinity)
            }
            devices
            settings
        }
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                ui.showAdvanced = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("Back").font(.system(size: 13))
                }
                .foregroundStyle(brand)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Advanced").font(.system(size: 22, weight: .semibold))
            Card(spacing: 0) { advanced }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CornerSwitch").font(.system(size: 22, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusLine(state)).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $state.enabled).toggleStyle(.switch).labelsHidden().tint(brand)
        }
    }

    private var statusColor: Color {
        if !state.hasPermission { return .orange }
        if !state.enabled { return .gray }
        return state.devices.isEmpty ? .blue : .green
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: 18)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("One permission needed").font(.system(size: 13, weight: .semibold))
                Text("macOS asks before an app can talk to your keyboard. Turn on CornerSwitch under Input Monitoring. This window updates by itself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", action: actions.openPrivacy)
                    .buttonStyle(.borderedProminent).tint(brand).controlSize(.small).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
    }

    // MARK: Devices

    private var devices: some View {
        HStack(spacing: 12) {
            DeviceCard(symbol: "keyboard", fallback: "Keyboard",
                       device: state.devices.first { $0.isKeyboard }, rememberedName: state.keyboardName)
            DeviceCard(symbol: "computermouse", fallback: "Mouse",
                       device: state.devices.first { !$0.isKeyboard }, rememberedName: state.mouseName)
        }
    }

    // MARK: Settings

    private var settings: some View {
        Card(spacing: 0) {
            Row("Start at login") {
                Toggle("", isOn: Binding(get: { state.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(brand)
            }
            Divider()
            Button {
                ui.showAdvanced = true
            } label: {
                HStack {
                    Text("Advanced").font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var advanced: some View {
        Row("Push strength", "How firmly you push past the edge before it switches.") {
            Picker("", selection: $state.resistance) {
                ForEach(Resistance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        Divider()
        Row("Other Mac's Easy-Switch key", "Leave on Automatic unless it switches to the wrong computer.") {
            Picker("", selection: $state.targetChannel) {
                Text("Automatic").tag(0)
                ForEach(1...3, id: \.self) { Text("Key \($0)").tag($0) }
            }
            .labelsHidden().frame(width: 130)
        }
        Divider()
        Row("Update automatically") {
            Toggle("", isOn: $state.autoUpdate).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(brand)
        }
        Divider()
        Row("Version \(state.version)", updateSubtitle) {
            switch state.update {
            case .available(let v): Button("Update to \(v)", action: actions.installUpdate)
            case .installing, .checking: ProgressView().controlSize(.small)
            default: Button("Check now", action: actions.checkUpdates)
            }
        }
        Divider()
        Row("Switch now", "Sends the keyboard and mouse to the other Mac without the edge.") {
            Button("Switch", action: actions.switchNow).disabled(state.devices.isEmpty)
        }
    }

    private var updateSubtitle: String? {
        switch state.update {
        case .upToDate: "Up to date"
        case .failed(let m): m
        case .installing: "Installing…"
        default: nil
        }
    }
}

func statusLine(_ state: AppState) -> String {
    if !state.hasPermission { return "Needs one permission" }
    if !state.enabled { return "Off" }
    if state.devices.isEmpty { return "Keyboard and mouse are on your other Mac" }
    return "Ready. Push the pointer past the \(state.side.rawValue) edge to switch."
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, spacing == 0 ? 2 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hairline))
    }
}

struct Row<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing
    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 10)
    }
}

struct DeviceCard: View {
    let symbol: String
    let fallback: String
    let device: DeviceInfo?
    let rememberedName: String?

    var body: some View {
        let here = device != nil
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(here ? brand : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(prettyName(device?.name ?? rememberedName ?? fallback))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(here ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(here ? "Connected here" : "On other Mac")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hairline))
    }
}

/// This Mac in the middle; drag Other Mac (or click a dashed slot) to any side.
struct ArrangementView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var ui = UIModel.shared

    private let canvas = CGSize(width: 452, height: 224)
    private let tile = CGSize(width: 116, height: 66)
    private let gap: CGFloat = 10

    private func center(for side: Side) -> CGPoint {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let dx = tile.width + gap, dy = tile.height + gap
        switch side {
        case .left: return CGPoint(x: c.x - dx, y: c.y)
        case .right: return CGPoint(x: c.x + dx, y: c.y)
        case .top: return CGPoint(x: c.x, y: c.y - dy)
        case .bottom: return CGPoint(x: c.x, y: c.y + dy)
        }
    }

    var body: some View {
        ZStack {
            ForEach(Side.allCases.filter { $0 != state.side }, id: \.self) { side in
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .frame(width: tile.width, height: tile.height)
                    .contentShape(Rectangle())
                    .position(center(for: side))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { state.side = side } }
            }

            tileView("This Mac", "laptopcomputer", primary: true)
                .position(x: canvas.width / 2, y: canvas.height / 2)

            tileView("Other Mac", "desktopcomputer", primary: false)
                .position(center(for: state.side))
                .offset(ui.dragOffset)
                .gesture(DragGesture()
                    .onChanged { ui.dragOffset = $0.translation }
                    .onEnded { v in
                        let s = center(for: state.side)
                        let p = CGPoint(x: s.x + v.translation.width, y: s.y + v.translation.height)
                        let nearest = Side.allCases.min {
                            hypot(center(for: $0).x - p.x, center(for: $0).y - p.y)
                                < hypot(center(for: $1).x - p.x, center(for: $1).y - p.y)
                        }!
                        withAnimation(.easeOut(duration: 0.2)) {
                            state.side = nearest
                            ui.dragOffset = .zero
                        }
                    })
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private func tileView(_ title: String, _ symbol: String, primary: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(primary ? Color.white : Color.primary)
        .frame(width: tile.width, height: tile.height)
        .background(RoundedRectangle(cornerRadius: 10).fill(primary ? brand : Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(primary ? Color.clear : Color.primary.opacity(0.18)))
    }
}
