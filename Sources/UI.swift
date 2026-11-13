// Main window: translucent window, Liquid Glass surfaces (macOS 26+, frosted
// material before that), a stage showing where the other Mac sits, device tiles
// with battery, and a footer. Advanced settings live in a sheet.

import SwiftUI
import AppKit

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
    @Published var showAdvanced = UserDefaults.standard.bool(forKey: "showAdvanced")
    @Published var renaming = false
}

/// "MX KEYS S" -> "MX Keys S"
func prettyName(_ n: String) -> String {
    n.split(separator: " ").map { w in
        w.count <= 2 || w.contains(where: \.isNumber) ? String(w) : w.capitalized
    }.joined(separator: " ")
}

func edgeName(_ side: Side) -> String {
    switch side {
    case .left: "left edge"
    case .right: "right edge"
    case .top: "top edge"
    case .bottom: "bottom edge"
    }
}

func statusLine(_ state: AppState) -> String {
    if !state.hasPermission { return "Needs one permission" }
    if !state.enabled { return "Paused" }
    if state.devices.isEmpty { return "Keyboard and mouse are on \(state.otherDisplayName)" }
    return "Push past the \(edgeName(state.side)) to switch"
}

// MARK: - Surfaces

struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Liquid Glass on macOS 26+, frosted material before.
    @ViewBuilder func glassSurface(_ radius: CGFloat = 22) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    @ViewBuilder func glassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

// MARK: - Main view

struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var ui = UIModel.shared
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if !state.hasPermission { permission }
            stage
            devices
            footer
        }
        .padding(.horizontal, 26)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowBackground().ignoresSafeArea())
        .tint(brand)
        .sheet(isPresented: $ui.renaming) { RenameView(state: state) { ui.renaming = false } }
        .sheet(isPresented: $ui.showAdvanced) {
            AdvancedView(state: state, actions: actions) { ui.showAdvanced = false }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CornerSwitch")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                StatusChip(text: statusLine(state), color: statusColor)
            }
            Spacer()
            Toggle("", isOn: $state.enabled)
                .toggleStyle(.switch).labelsHidden().controlSize(.large)
        }
    }

    private var statusColor: Color {
        if !state.hasPermission { return .orange }
        if !state.enabled { return .gray }
        return state.devices.isEmpty ? .blue : .green
    }

    private var permission: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill").font(.system(size: 20)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Allow access to your keyboard").font(.system(size: 13, weight: .semibold))
                Text("Turn on CornerSwitch under Input Monitoring. This updates by itself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings", action: actions.openPrivacy).glassButton()
        }
        .padding(16)
        .glassSurface(18)
    }

    private var stage: some View {
        VStack(spacing: 16) {
            Stage(side: state.side, active: state.enabled && !state.devices.isEmpty,
                  thisName: state.thisName, otherName: state.otherDisplayName)
            Picker("", selection: $state.side) {
                Label("Left", systemImage: "arrow.left").tag(Side.left)
                Label("Right", systemImage: "arrow.right").tag(Side.right)
                Label("Above", systemImage: "arrow.up").tag(Side.top)
                Label("Below", systemImage: "arrow.down").tag(Side.bottom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            Text("Where \(state.otherDisplayName) sits on your desk")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassSurface(26)
    }

    private var devices: some View {
        HStack(spacing: 14) {
            DeviceTile(symbol: "keyboard", fallback: "Keyboard",
                       device: state.devices.first { $0.isKeyboard },
                       remembered: state.keyboardName, state: state)
            DeviceTile(symbol: "computermouse", fallback: "Mouse",
                       device: state.devices.first { !$0.isKeyboard },
                       remembered: state.mouseName, state: state)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { actions.setLaunchAtLogin($0) })) {
                Text("Open at login").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.small)
            Spacer()
            Button { ui.renaming = true } label: { Label("Rename", systemImage: "pencil") }
                .glassButton()
            Button { ui.showAdvanced = true } label: { Label("Options", systemImage: "slider.horizontal.3") }
                .glassButton()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pieces

struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// This Mac and the other Mac, with a soft trail of dots flowing toward the other one.
struct Stage: View {
    let side: Side
    let active: Bool
    let thisName: String
    let otherName: String

    var body: some View {
        let vertical = side == .top || side == .bottom
        let me = Machine(symbol: "laptopcomputer", name: thisName, highlighted: true, size: vertical ? 40 : 56)
        let other = Machine(symbol: "desktopcomputer", name: otherName, highlighted: false, size: vertical ? 40 : 56)
        let trail = Trail(vertical: vertical, towardStart: side == .left || side == .top, active: active)
        Group {
            switch side {
            case .left: HStack(spacing: 18) { other; trail; me }
            case .right: HStack(spacing: 18) { me; trail; other }
            case .top: VStack(spacing: 10) { other; trail; me }
            case .bottom: VStack(spacing: 10) { me; trail; other }
            }
        }
        .frame(height: vertical ? 230 : 140)
        .animation(.spring(response: 0.4, dampingFraction: 1), value: side)
    }
}

struct Machine: View {
    let symbol: String
    let name: String
    let highlighted: Bool
    let size: CGFloat
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(highlighted ? brand : Color.secondary)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(highlighted ? Color.primary : Color.secondary)
                .lineLimit(1).frame(maxWidth: 150)
        }
    }
}

/// Five dots; a highlight travels along them toward the other Mac. Still when inactive
/// or when Reduce Motion is on.
struct Trail: View {
    let vertical: Bool
    let towardStart: Bool
    let active: Bool
    private let count = 5

    var body: some View {
        let still = !active || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = still ? -1 : (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
            let dots = ForEach(0..<count, id: \.self) { i in
                let pos = Double(towardStart ? count - 1 - i : i) / Double(count - 1)
                let glow = phase < 0 ? 0 : max(0, 1 - abs(phase * 1.3 - pos) * 3)
                Circle()
                    .fill(active ? brand : Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.25 + 0.75 * glow)
                    .scaleEffect(1 + 0.35 * glow)
            }
            if vertical { VStack(spacing: 7) { dots } } else { HStack(spacing: 9) { dots } }
        }
    }
}

struct DeviceTile: View {
    let symbol: String
    let fallback: String
    let device: DeviceInfo?
    let remembered: String?
    @ObservedObject var state: AppState

    var body: some View {
        let here = device != nil
        let name = device?.name ?? remembered ?? fallback
        let battery = device?.battery ?? state.batteries[name]
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(here ? brand : Color.secondary)
                Spacer()
                BatteryRing(percent: battery, charging: device?.charging ?? false, stale: !here)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(prettyName(name)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(here ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(here ? "Connected" : "On \(state.otherDisplayName)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(20)
    }
}

struct BatteryRing: View {
    let percent: Int?
    let charging: Bool
    let stale: Bool

    var body: some View {
        let p = Double(percent ?? 0) / 100
        let color: Color = percent == nil ? .secondary : (percent! <= 15 ? .red : percent! <= 30 ? .orange : .green)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3.5)
            Circle().trim(from: 0, to: p)
                .stroke(color.opacity(stale ? 0.5 : 1), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            } else {
                Text(percent.map { "\($0)" } ?? "–")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .help(percent.map { "Battery \($0)%\(stale ? " (last seen)" : "")" } ?? "Battery unknown")
    }
}

// MARK: - Sheets

struct RenameView: View {
    @ObservedObject var state: AppState
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name the other Mac").font(.headline)
            Text("Shown in this window and in the hint when you switch.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("", text: $state.otherName, prompt: Text("Office Mac"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(done)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .tint(brand)
    }
}

struct AdvancedView: View {
    @ObservedObject var state: AppState
    let actions: Actions
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Switching") {
                    Picker("Push strength", selection: $state.resistance) {
                        ForEach(Resistance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.requireControl)
                    Toggle(isOn: $state.requireControl) {
                        Text("Only while holding Control")
                        Text("Hold ⌃ and touch the edge to switch.")
                    }
                    Toggle(isOn: $state.followAlong) {
                        Text("Bring the other device along")
                        Text("Switch the mouse or keyboard by its button and the other follows.")
                    }
                    Toggle(isOn: $state.autoPause) {
                        Text("Pause during presentations and calls")
                        Text("Also while the screen is locked.")
                    }
                    Picker(selection: $state.targetChannel) {
                        Text("Automatic").tag(0)
                        ForEach(1...3, id: \.self) { Text("Key \($0)").tag($0) }
                    } label: {
                        Text("Other Mac's Easy-Switch key")
                        Text("Leave on Automatic unless it switches to the wrong computer.")
                    }
                }
                Section("General") {
                    Toggle("Low battery alerts", isOn: $state.batteryAlerts)
                    Toggle("Update automatically", isOn: $state.autoUpdate)
                    LabeledContent {
                        switch state.update {
                        case .available(let v): Button("Update to \(v)", action: actions.installUpdate)
                        case .installing, .checking: ProgressView().controlSize(.small)
                        default: Button("Check Now", action: actions.checkUpdates)
                        }
                    } label: {
                        Text("Version \(state.version)")
                        if let s = updateSubtitle { Text(s) }
                    }
                    LabeledContent {
                        Button("Switch Now", action: actions.switchNow).disabled(state.devices.isEmpty)
                    } label: {
                        Text("Test switch")
                        Text("Sends the keyboard and mouse to \(state.otherDisplayName).")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.never)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .tint(brand)
        .frame(width: 460, height: 560)
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
