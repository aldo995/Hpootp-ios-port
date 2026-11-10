import GameController
import Combine

/// Bridges game controllers (MFi / Xbox / PlayStation / Backbone) and hardware keyboards into the emulator.
final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()
    @Published private(set) var names: [String] = []
    @Published private(set) var keyboardConnected = false
    weak var emulator: Emulator?

    private let store = SettingsStore.shared
    private var held = Set<PadInput>()
    private var kbHeld = Set<PadAction>()
    private var dpad: (x: Float, y: Float) = (0, 0)
    private var stick: (x: Float, y: Float) = (0, 0)
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.attach(c) }
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.held.removeAll(); self?.dpad = (0, 0); self?.stick = (0, 0)
            self?.refreshNames(); self?.recompute()
        }
        nc.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in self?.attachKeyboard() }
        nc.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.kbHeld.removeAll(); self?.keyboardConnected = false; self?.recompute()
        }
        GCController.controllers().forEach(attach)
        GCController.startWirelessControllerDiscovery {}
        attachKeyboard()
    }

    private func refreshNames() {
        names = GCController.controllers().filter { $0.extendedGamepad != nil }.map { $0.vendorName ?? "Controller" }
    }

    // MARK: Controllers

    private func attach(_ c: GCController) {
        guard let g = c.extendedGamepad else { return }
        c.handlerQueue = .main
        func bind(_ b: GCControllerButtonInput?, _ i: PadInput) {
            b?.valueChangedHandler = { [weak self] _, _, pressed in self?.set(i, pressed) }
        }
        bind(g.buttonA, .a); bind(g.buttonB, .b); bind(g.buttonX, .x); bind(g.buttonY, .y)
        bind(g.leftShoulder, .l1); bind(g.rightShoulder, .r1)
        bind(g.leftTrigger, .l2); bind(g.rightTrigger, .r2)
        bind(g.buttonMenu, .start); bind(g.buttonOptions, .select)
        bind(g.leftThumbstickButton, .l3); bind(g.rightThumbstickButton, .r3)
        g.dpad.valueChangedHandler = { [weak self] _, x, y in self?.dpad = (x, y); self?.recompute() }
        g.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in self?.stick = (x, y); self?.recompute() }
        refreshNames()
    }

    private func set(_ input: PadInput, _ pressed: Bool) {
        if pressed { held.insert(input) } else { held.remove(input) }
        fire(store.action(for: input), pressed)
        recompute()
    }

    // MARK: Keyboard

    private func attachKeyboard() {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return }
        keyboardConnected = true
        input.keyChangedHandler = { [weak self] _, _, code, pressed in
            DispatchQueue.main.async { self?.key(code, pressed) }
        }
    }

    private func key(_ code: GCKeyCode, _ pressed: Bool) {
        for a in PadAction.bindable where store.keyChoice(for: a).code == code {
            if pressed { kbHeld.insert(a) } else { kbHeld.remove(a) }
            fire(a, pressed)
        }
        recompute()
    }

    // MARK: Shared

    /// Non-keypad actions (hotkeys). Keypad bits are handled in recompute().
    private func fire(_ action: PadAction, _ pressed: Bool) {
        switch action {
        case .fastForward: emulator?.fastForward = pressed
        case .rewind: emulator?.rewinding = pressed
        case .saveState where pressed: emulator?.saveState()
        case .loadState where pressed: emulator?.loadState()
        case .menu where pressed: emulator?.onMenu?()
        default: break
        }
    }

    private func dirBits(_ v: (x: Float, y: Float), _ t: Float) -> UInt32 {
        var m: UInt32 = 0
        if v.y > t { m |= GBABit.up };   if v.y < -t { m |= GBABit.down }
        if v.x > t { m |= GBABit.right }; if v.x < -t { m |= GBABit.left }
        return m
    }

    private func recompute() {
        var mask: UInt32 = 0
        for i in held { if let b = store.action(for: i).bit { mask |= b } }
        for a in kbHeld { if let b = a.bit { mask |= b } }
        mask |= dirBits(dpad, 0.5) | dirBits(stick, Float(store.prefs.stickDeadzone))
        emulator?.padKeys = mask
    }
}
