import Foundation
import SystemConfiguration

enum Side: String, CaseIterable {
    case left, right, top, bottom
}

enum Resistance: Int, CaseIterable {
    case light = 15, medium = 40, firm = 100
    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .firm: "Firm"
        }
    }
}

struct DeviceInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let isKeyboard: Bool
    let channel: Int?   // 1-based
}

enum UpdateStatus: Equatable {
    case idle, checking, upToDate
    case available(String)
    case installing
    case failed(String)
}

/// Settings plus live state the popover renders.
final class AppState: ObservableObject {
    static let shared = AppState()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    /// Where the other Mac sits relative to this one.
    @Published var side: Side { didSet { d.set(side.rawValue, forKey: "side") } }
    /// 0 = auto (the other of channels 1 and 2), else 1...3
    @Published var targetChannel: Int { didSet { d.set(targetChannel, forKey: "targetChannel") } }
    @Published var resistance: Resistance { didSet { d.set(resistance.rawValue, forKey: "resistance") } }
    @Published var autoUpdate: Bool { didSet { d.set(autoUpdate, forKey: "autoUpdate") } }
    /// Switch only while Control is held (then instantly on contact). Off by default.
    @Published var requireControl: Bool { didSet { d.set(requireControl, forKey: "requireControl") } }

    @Published var devices: [DeviceInfo] = [] {
        didSet {
            // Remember names so the window can still say "MX Keys S: On other Mac" when they're away.
            if let k = devices.first(where: \.isKeyboard)?.name { keyboardName = k }
            if let m = devices.first(where: { !$0.isKeyboard })?.name { mouseName = m }
        }
    }
    /// What the user calls the other Mac ("Office Mac"). Shown in the window, hint and menu.
    @Published var otherName: String { didSet { d.set(otherName, forKey: "otherName") } }
    var otherDisplayName: String {
        let t = otherName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Other Mac" : t
    }
    /// This Mac's computer name from Sharing settings.
    let thisName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"
    @Published var keyboardName: String? { didSet { d.set(keyboardName, forKey: "keyboardName") } }
    @Published var mouseName: String? { didSet { d.set(mouseName, forKey: "mouseName") } }
    @Published var hasPermission = true
    @Published var launchAtLogin = false
    @Published var update: UpdateStatus = .idle

    private init() {
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        side = Side(rawValue: d.string(forKey: "side") ?? "") ?? .left
        targetChannel = d.integer(forKey: "targetChannel")
        resistance = Resistance(rawValue: d.integer(forKey: "resistance")) ?? .medium
        autoUpdate = d.object(forKey: "autoUpdate") as? Bool ?? true
        requireControl = d.bool(forKey: "requireControl")
        otherName = d.string(forKey: "otherName") ?? ""
        keyboardName = d.string(forKey: "keyboardName")
        mouseName = d.string(forKey: "mouseName")
    }

    var thisChannel: Int? { devices.compactMap(\.channel).first }

    /// 1-based channel to send devices to.
    var target: Int {
        if targetChannel > 0 { return targetChannel }
        return thisChannel == 2 ? 1 : 2
    }

    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
