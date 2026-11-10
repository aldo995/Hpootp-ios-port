import SwiftUI
import GameController

/// GBA keypad bits (same order as the hardware register).
enum GBABit {
    static let a: UInt32 = 1 << 0, b: UInt32 = 1 << 1, select: UInt32 = 1 << 2, start: UInt32 = 1 << 3
    static let right: UInt32 = 1 << 4, left: UInt32 = 1 << 5, up: UInt32 = 1 << 6, down: UInt32 = 1 << 7
    static let r: UInt32 = 1 << 8, l: UInt32 = 1 << 9
}

/// Everything a physical controller button or key can be mapped to.
enum PadAction: String, CaseIterable, Codable, Identifiable {
    case a = "A", b = "B", l = "L", r = "R", start = "Start", select = "Select"
    case up = "Up", down = "Down", left = "Left", right = "Right"
    case fastForward = "Fast-forward (hold)", rewind = "Rewind (hold)", saveState = "Quick save", loadState = "Quick load", menu = "Pause menu", none = "Nothing"
    var id: String { rawValue }
    var bit: UInt32? {
        switch self {
        case .a: return GBABit.a;  case .b: return GBABit.b
        case .l: return GBABit.l;  case .r: return GBABit.r
        case .start: return GBABit.start; case .select: return GBABit.select
        case .up: return GBABit.up; case .down: return GBABit.down
        case .left: return GBABit.left; case .right: return GBABit.right
        default: return nil
        }
    }
    static var bindable: [PadAction] { allCases.filter { $0 != .none } }
}

/// Physical controller inputs you can remap (D-pad and left stick are always directions).
enum PadInput: String, CaseIterable, Codable, Identifiable {
    case a, b, x, y, l1, r1, l2, r2, start, select, l3, r3
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a: return "A / Cross"; case .b: return "B / Circle"; case .x: return "X / Square"; case .y: return "Y / Triangle"
        case .l1: return "L1 / LB"; case .r1: return "R1 / RB"; case .l2: return "L2 / LT"; case .r2: return "R2 / RT"
        case .start: return "Menu / Start"; case .select: return "Options / Select"
        case .l3: return "Left stick click"; case .r3: return "Right stick click"
        }
    }
    static let defaults: [String: String] = [
        "a": "A", "b": "B", "x": "B", "y": "A", "l1": "L", "r1": "R",
        "l2": PadAction.rewind.rawValue, "r2": PadAction.fastForward.rawValue,
        "start": "Start", "select": "Select", "l3": PadAction.loadState.rawValue, "r3": PadAction.menu.rawValue,
    ]
}

/// Keys offered for hardware-keyboard mapping.
enum KeyChoice: String, CaseIterable, Identifiable {
    case unbound = "None"
    case up = "↑", down = "↓", left = "←", right = "→"
    case z = "Z", x = "X", a = "A", s = "S", q = "Q", w = "W", d = "D", e = "E"
    case ret = "Return", space = "Space", backspace = "Backspace", tab = "Tab"
    case lshift = "Left Shift", rshift = "Right Shift", esc = "Esc"
    case f5 = "F5", f6 = "F6", f7 = "F7", f8 = "F8"
    var id: String { rawValue }
    var code: GCKeyCode? {
        switch self {
        case .unbound: return nil
        case .up: return .upArrow; case .down: return .downArrow; case .left: return .leftArrow; case .right: return .rightArrow
        case .z: return .keyZ; case .x: return .keyX; case .a: return .keyA; case .s: return .keyS
        case .q: return .keyQ; case .w: return .keyW; case .d: return .keyD; case .e: return .keyE
        case .ret: return .returnOrEnter; case .space: return .spacebar; case .backspace: return .deleteOrBackspace; case .tab: return .tab
        case .lshift: return .leftShift; case .rshift: return .rightShift; case .esc: return .escape
        case .f5: return .F5; case .f6: return .F6; case .f7: return .F7; case .f8: return .F8
        }
    }
    static let defaults: [String: String] = [
        "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "A": "X", "B": "Z", "L": "A", "R": "S",
        "Start": "Return", "Select": "Right Shift",
        "Fast-forward (hold)": "Tab", "Rewind (hold)": "Backspace", "Quick save": "F5", "Quick load": "F7", "Pause menu": "Esc",
    ]
}

enum ScreenFilter: Int, CaseIterable, Identifiable {
    case sharp, smooth, sharpBilinear, lcdGrid, scanlines
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sharp: return "Pixel perfect (nearest)"; case .smooth: return "Smooth (bilinear)"
        case .sharpBilinear: return "Sharp bilinear"; case .lcdGrid: return "LCD grid"; case .scanlines: return "Scanlines"
        }
    }
}

enum TouchControl: String, CaseIterable, Identifiable {
    case dpad, a, b, ab, l, r, start, select
    var id: String { rawValue }
    var title: String { self == .dpad ? "D-pad" : self == .ab ? "A/B cluster" : rawValue.capitalized }
    /// Default centre as a fraction of the view, per orientation.
    func defaultPosition(landscape: Bool) -> CGPoint {
        switch (self, landscape) {
        case (.dpad, false): return CGPoint(x: 0.24, y: 0.80)
        case (.a, false):    return CGPoint(x: 0.88, y: 0.76)
        case (.b, false):    return CGPoint(x: 0.70, y: 0.84)
        case (.ab, false):   return CGPoint(x: 0.78, y: 0.80)
        case (.l, false):    return CGPoint(x: 0.13, y: 0.58)
        case (.r, false):    return CGPoint(x: 0.87, y: 0.58)
        case (.select, false): return CGPoint(x: 0.36, y: 0.95)
        case (.start, false):  return CGPoint(x: 0.64, y: 0.95)
        case (.dpad, true):  return CGPoint(x: 0.13, y: 0.66)
        case (.a, true):     return CGPoint(x: 0.93, y: 0.56)
        case (.b, true):     return CGPoint(x: 0.82, y: 0.74)
        case (.ab, true):    return CGPoint(x: 0.87, y: 0.65)
        case (.l, true):     return CGPoint(x: 0.09, y: 0.16)
        case (.r, true):     return CGPoint(x: 0.91, y: 0.16)
        case (.select, true): return CGPoint(x: 0.42, y: 0.92)
        case (.start, true):  return CGPoint(x: 0.58, y: 0.92)
        }
    }
}

struct Prefs: Codable {
    var showTouch = true
    var hideTouchWithController = true
    var abCluster = true         // one A/B pad you can slide across; off = two independent buttons
    var opacity = 0.65
    var scale = 1.0
    var haptics = true
    var dpadDeadzone = 0.30      // fraction of d-pad radius
    var stickDeadzone = 0.40
    var ffSpeed = 3
    var filter = ScreenFilter.sharpBilinear.rawValue
    var colorCorrect = false
    var rewindEnabled = true
    var rewindSeconds = 10        // 5...20
    var iCloudSync = true         // only active when the build has the iCloud capability
    var padMap: [String: String] = PadInput.defaults
    var keyMap: [String: String] = KeyChoice.defaults
    var layout: [String: CGPoint] = [:]   // "port.dpad" / "land.a" -> normalised centre
    var sizes: [String: Double] = [:]     // per-control size multiplier

    enum CodingKeys: String, CodingKey {
        case showTouch, hideTouchWithController, abCluster, opacity, scale, haptics, dpadDeadzone, stickDeadzone
        case ffSpeed, filter, colorCorrect, rewindEnabled, rewindSeconds, iCloudSync, padMap, keyMap, layout, sizes
    }
}

extension Prefs {
    /// Tolerant decoding: settings saved by older versions keep working when new fields are added,
    /// and out-of-range / corrupted values are clamped instead of crashing or exhausting memory.
    init(from decoder: Decoder) throws {
        var p = Prefs()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func take<T: Decodable>(_ k: CodingKeys, _ kp: WritableKeyPath<Prefs, T>) {
            if let v = try? c.decodeIfPresent(T.self, forKey: k) { p[keyPath: kp] = v }
        }
        take(.showTouch, \.showTouch); take(.hideTouchWithController, \.hideTouchWithController)
        take(.abCluster, \.abCluster); take(.opacity, \.opacity); take(.scale, \.scale); take(.haptics, \.haptics)
        take(.dpadDeadzone, \.dpadDeadzone); take(.stickDeadzone, \.stickDeadzone); take(.ffSpeed, \.ffSpeed)
        take(.filter, \.filter); take(.colorCorrect, \.colorCorrect)
        take(.rewindEnabled, \.rewindEnabled); take(.rewindSeconds, \.rewindSeconds); take(.iCloudSync, \.iCloudSync)
        take(.padMap, \.padMap); take(.keyMap, \.keyMap); take(.layout, \.layout); take(.sizes, \.sizes)
        for (k, v) in KeyChoice.defaults where p.keyMap[k] == nil { p.keyMap[k] = v }   // new hotkeys on old saves
        p.sanitize()
        self = p
    }

    mutating func sanitize() {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double { v.isFinite ? min(max(v, lo), hi) : d }
        opacity = clamp(opacity, 0.15, 1, 0.65); scale = clamp(scale, 0.6, 1.6, 1)
        dpadDeadzone = clamp(dpadDeadzone, 0.1, 0.6, 0.3); stickDeadzone = clamp(stickDeadzone, 0.1, 0.8, 0.4)
        ffSpeed = min(max(ffSpeed, 2), 8); rewindSeconds = min(max(rewindSeconds, 5), 20)
        if ScreenFilter(rawValue: filter) == nil { filter = ScreenFilter.sharpBilinear.rawValue }
        layout = layout.mapValues { CGPoint(x: clamp(Double($0.x), 0.03, 0.97, 0.5), y: clamp(Double($0.y), 0.03, 0.97, 0.5)) }
        sizes = sizes.mapValues { clamp($0, 0.5, 2, 1) }
    }
}

/// The control-related settings that can be overridden per game.
struct ControlProfile: Codable {
    var abCluster: Bool, opacity: Double, scale: Double, dpadDeadzone: Double, stickDeadzone: Double
    var padMap: [String: String], keyMap: [String: String], layout: [String: CGPoint], sizes: [String: Double]
    init(_ p: Prefs) {
        abCluster = p.abCluster; opacity = p.opacity; scale = p.scale; dpadDeadzone = p.dpadDeadzone; stickDeadzone = p.stickDeadzone
        padMap = p.padMap; keyMap = p.keyMap; layout = p.layout; sizes = p.sizes
    }
    func apply(to p: inout Prefs) {
        p.abCluster = abCluster; p.opacity = opacity; p.scale = scale; p.dpadDeadzone = dpadDeadzone; p.stickDeadzone = stickDeadzone
        p.padMap = padMap; p.keyMap = keyMap; p.layout = layout; p.sizes = sizes
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let key = "PhoenixGBA.prefs.v1"
    private let profilesKey = "PhoenixGBA.profiles.v1"
    @Published var prefs: Prefs { didSet { save() } }
    @Published private(set) var profiles: [String: ControlProfile] { didSet { saveProfiles() } }
    @Published private(set) var gameProfileActive = false
    private var currentGame: String?
    private var globalControls: ControlProfile?   // the global controls, parked while a game profile is active

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode(Prefs.self, from: d) { prefs = p }
        else { prefs = Prefs() }
        if let d = UserDefaults.standard.data(forKey: profilesKey), let p = try? JSONDecoder().decode([String: ControlProfile].self, from: d) { profiles = p }
        else { profiles = [:] }
    }

    /// Always persists the *global* controls, even while a per-game profile is live, so a crash can't pollute them.
    private func save() {
        var p = prefs
        if gameProfileActive, let g = globalControls { g.apply(to: &p) }
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func saveProfiles() { if let d = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(d, forKey: profilesKey) } }

    // MARK: Per-game profiles
    func beginGame(_ name: String, allowProfiles: Bool) {
        currentGame = name; globalControls = nil; gameProfileActive = false
        if allowProfiles, let p = profiles[name] {
            globalControls = ControlProfile(prefs); gameProfileActive = true
            var np = prefs; p.apply(to: &np); prefs = np
        }
    }
    func endGame() {
        if gameProfileActive, let name = currentGame, let g = globalControls {
            profiles[name] = ControlProfile(prefs)
            var np = prefs; g.apply(to: &np); prefs = np
        }
        currentGame = nil; globalControls = nil; gameProfileActive = false
    }
    func setGameProfile(_ on: Bool) {
        guard let name = currentGame else { return }
        if on, !gameProfileActive {
            globalControls = ControlProfile(prefs); gameProfileActive = true
            profiles[name] = ControlProfile(prefs)
        } else if !on, gameProfileActive {
            if let g = globalControls { var np = prefs; g.apply(to: &np); prefs = np }
            profiles[name] = nil; globalControls = nil; gameProfileActive = false
        }
    }

    func action(for input: PadInput) -> PadAction {
        PadAction(rawValue: prefs.padMap[input.rawValue] ?? "") ?? .none
    }
    func setAction(_ a: PadAction, for input: PadInput) { prefs.padMap[input.rawValue] = a.rawValue }

    func keyChoice(for a: PadAction) -> KeyChoice { KeyChoice(rawValue: prefs.keyMap[a.rawValue] ?? "") ?? .unbound }
    func setKey(_ k: KeyChoice, for a: PadAction) { prefs.keyMap[a.rawValue] = k.rawValue }

    var screenFilter: ScreenFilter { ScreenFilter(rawValue: prefs.filter) ?? .sharpBilinear }

    /// Controls actually shown, depending on the A/B cluster setting.
    var visibleControls: [TouchControl] {
        TouchControl.allCases.filter { prefs.abCluster ? ($0 != .a && $0 != .b) : $0 != .ab }
    }

    private func k(_ c: TouchControl, _ land: Bool) -> String { (land ? "land." : "port.") + c.rawValue }
    func position(_ c: TouchControl, landscape: Bool) -> CGPoint { prefs.layout[k(c, landscape)] ?? c.defaultPosition(landscape: landscape) }
    func setPosition(_ p: CGPoint, _ c: TouchControl, landscape: Bool) {
        prefs.layout[k(c, landscape)] = CGPoint(x: min(max(p.x, 0.03), 0.97), y: min(max(p.y, 0.03), 0.97))
    }
    func size(_ c: TouchControl) -> Double { prefs.sizes[c.rawValue] ?? 1.0 }
    func setSize(_ v: Double, _ c: TouchControl) { prefs.sizes[c.rawValue] = v }
    func resetLayout() { prefs.layout = [:]; prefs.sizes = [:] }
    func resetAll() { prefs = Prefs() }
}

enum Haptics {
    private static let gen = UIImpactFeedbackGenerator(style: .light)
    static func tap() { if SettingsStore.shared.prefs.haptics { gen.impactOccurred() } }
}
