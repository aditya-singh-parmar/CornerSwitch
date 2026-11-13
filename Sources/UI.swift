// Main window, built from native macOS settings components (grouped Form),
// so it looks and behaves like System Settings in light and dark mode.

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
    @Published var showAdvanced = UserDefaults.standard.bool(forKey: "showAdvanced")
    @Published var renaming = false
}

/// "MX KEYS S" -> "MX Keys S"
func prettyName(_ n: String) -> String {
    n.split(separator: " ").map { w in
        w.count <= 2 || w.contains(where: \.isNumber) ? String(w) : w.capitalized
    }.joined(separator: " ")
}

func statusLine(_ state: AppState) -> String {
    if !state.hasPermission { return "Needs one permission" }
    if !state.enabled { return "Off" }
    if state.devices.isEmpty { return "Keyboard and mouse are on your other Mac" }
    let edge: String
    switch state.side {
    case .left: edge = "left edge"
    case .right: edge = "right edge"
    case .top: edge = "top edge"
    case .bottom: edge = "bottom edge"
    }
    return "Push past the \(edge) to switch to \(state.otherDisplayName)"
}

struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var ui = UIModel.shared
    let actions: Actions

    var body: some View {
        Form {
            if !state.hasPermission {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow access to your keyboard").fontWeight(.semibold)
                            Text("In Input Monitoring, turn on CornerSwitch. This window updates by itself.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Open Settings", action: actions.openPrivacy)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Hero(side: state.side, active: state.enabled && !state.devices.isEmpty,
                     thisName: state.thisName, otherName: state.otherDisplayName)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Toggle(isOn: $state.enabled) {
                    Text("Switch with the pointer")
                    Text(statusLine(state))
                }
                Picker("Other Mac is", selection: $state.side) {
                    Text("Left").tag(Side.left)
                    Text("Right").tag(Side.right)
                    Text("Above").tag(Side.top)
                    Text("Below").tag(Side.bottom)
                }
                .pickerStyle(.segmented)
                LabeledContent("Other Mac's name") {
                    HStack(spacing: 10) {
                        Text(state.otherDisplayName).foregroundStyle(.secondary)
                        Button("Rename…") { ui.renaming = true }
                    }
                }
            }

            Section("Devices") {
                DeviceRow(symbol: "keyboard", fallback: "Keyboard",
                          device: state.devices.first { $0.isKeyboard }, remembered: state.keyboardName)
                DeviceRow(symbol: "computermouse", fallback: "Mouse",
                          device: state.devices.first { !$0.isKeyboard }, remembered: state.mouseName)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { state.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
                HStack {
                    Text("Advanced")
                    Spacer()
                    Button("Options…") { ui.showAdvanced = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.never)
        .tint(brand)
        .frame(width: 460, height: state.hasPermission ? 600 : 694)
        .sheet(isPresented: $ui.renaming) {
            RenameView(state: state) { ui.renaming = false }
        }
        .sheet(isPresented: $ui.showAdvanced) {
            AdvancedView(state: state, actions: actions) { ui.showAdvanced = false }
        }
    }
}

/// Where the other Mac sits, drawn with system glyphs.
struct Hero: View {
    let side: Side
    let active: Bool
    let thisName: String
    let otherName: String

    var body: some View {
        let vertical = side == .top || side == .bottom
        let size: CGFloat = vertical ? 30 : 48
        let me = Glyph(symbol: "laptopcomputer", title: thisName, size: size, highlighted: true)
        let other = Glyph(symbol: "desktopcomputer", title: otherName, size: size, highlighted: false)
        let arrow = Image(systemName: {
            switch side {
            case .left: "arrow.left"
            case .right: "arrow.right"
            case .top: "arrow.up"
            case .bottom: "arrow.down"
            }
        }())
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(active ? brand : Color.secondary)

        Group {
            switch side {
            case .left: HStack(spacing: 28) { other; arrow; me }
            case .right: HStack(spacing: 28) { me; arrow; other }
            case .top: VStack(spacing: 8) { other; arrow; me }
            case .bottom: VStack(spacing: 8) { me; arrow; other }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .animation(.spring(response: 0.35, dampingFraction: 1), value: side)
    }
}

struct Glyph: View {
    let symbol: String
    let title: String
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .thin))
                .foregroundStyle(highlighted ? brand : Color.secondary)
            Text(title).font(.caption).fontWeight(.medium).lineLimit(1).frame(maxWidth: 140)
                .foregroundStyle(highlighted ? Color.primary : Color.secondary)
        }
    }
}

struct DeviceRow: View {
    let symbol: String
    let fallback: String
    let device: DeviceInfo?
    let remembered: String?

    var body: some View {
        let here = device != nil
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(here ? brand : Color.secondary)
            Text(prettyName(device?.name ?? remembered ?? fallback))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(here ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(here ? "Connected" : "On other Mac")
            }
            .foregroundStyle(.secondary)
        }
    }
}

struct AdvancedView: View {
    @ObservedObject var state: AppState
    let actions: Actions
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Push strength", selection: $state.resistance) {
                        ForEach(Resistance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.requireControl)
                    Toggle(isOn: $state.requireControl) {
                        Text("Only while holding Control")
                        Text("Hold ⌃ and touch the edge to switch. No accidental switches.")
                    }
                    Picker(selection: $state.targetChannel) {
                        Text("Automatic").tag(0)
                        ForEach(1...3, id: \.self) { Text("Key \($0)").tag($0) }
                    } label: {
                        Text("Other Mac's Easy-Switch key")
                        Text("Leave on Automatic unless it switches to the wrong computer")
                    }
                }
                Section {
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
                }
                Section {
                    LabeledContent {
                        Button("Switch Now", action: actions.switchNow).disabled(state.devices.isEmpty)
                    } label: {
                        Text("Test switch")
                        Text("Sends the keyboard and mouse to \(state.otherDisplayName)")
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .tint(brand)
        .frame(width: 440, height: 410)
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
