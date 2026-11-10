import SwiftUI

/// Multitouch on-screen controls. Each control tracks its own finger, so D-pad + A + B + shoulders all work at once.
struct TouchControlsView: View {
    @ObservedObject var emu: Emulator
    @ObservedObject private var store = SettingsStore.shared
    var editing: Bool
    @Binding var selected: TouchControl?

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack {
                ForEach(store.visibleControls) { c in
                    let sz = store.prefs.scale * store.size(c)
                    let p = store.position(c, landscape: land)
                    control(c, size: sz)
                        .opacity(store.prefs.opacity)
                        .allowsHitTesting(!editing)
                        .overlay {
                            if editing {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selected == c ? Color.yellow : Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5]))
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("pad")).onChanged { v in
                                        selected = c
                                        store.setPosition(CGPoint(x: v.location.x / geo.size.width, y: v.location.y / geo.size.height), c, landscape: land)
                                    })
                            }
                        }
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            }
            .coordinateSpace(name: "pad")
        }
    }

    @ViewBuilder private func control(_ c: TouchControl, size s: Double) -> some View {
        switch c {
        case .dpad:   DPadView(emu: emu, size: 150 * s)
        case .ab:     ABCluster(emu: emu, base: 64 * s)
        case .a:      HoldButton(emu: emu, bit: GBABit.a, label: "A", width: 64 * s, height: 64 * s, round: true)
        case .b:      HoldButton(emu: emu, bit: GBABit.b, label: "B", width: 64 * s, height: 64 * s, round: true)
        case .l:      HoldButton(emu: emu, bit: GBABit.l, label: "L", width: 88 * s, height: 40 * s, round: false)
        case .r:      HoldButton(emu: emu, bit: GBABit.r, label: "R", width: 88 * s, height: 40 * s, round: false)
        case .start:  HoldButton(emu: emu, bit: GBABit.start, label: "START", width: 72 * s, height: 30 * s, round: false)
        case .select: HoldButton(emu: emu, bit: GBABit.select, label: "SELECT", width: 72 * s, height: 30 * s, round: false)
        }
    }
}

/// Mutates bits of the touch mask. Shared by all touch widgets.
private func setBits(_ emu: Emulator, _ bits: UInt32, _ on: Bool) {
    if on { emu.touchKeys |= bits } else { emu.touchKeys &= ~bits }
}

// All three widgets use @GestureState: SwiftUI resets it automatically when a touch is cancelled
// (menu sheet appears, system gesture, app switch), so buttons can never get stuck "pressed".

struct HoldButton: View {
    let emu: Emulator; let bit: UInt32; let label: String
    let width: Double; let height: Double; let round: Bool
    @GestureState private var touching = false

    var body: some View {
        ZStack {
            if round { Circle().fill(Color.white.opacity(touching ? 0.55 : 0.22)) }
            else { Capsule().fill(Color.white.opacity(touching ? 0.55 : 0.22)) }
            Text(label).font(.system(size: min(width, height) * 0.42, weight: .bold)).foregroundColor(.white)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle().inset(by: -10))      // forgiving hit area
        .gesture(DragGesture(minimumDistance: 0).updating($touching) { _, s, _ in s = true })
        .onChange(of: touching) { on in if on { Haptics.tap() }; setBits(emu, bit, on) }
        .onDisappear { setBits(emu, bit, false) }
    }
}

/// 8-way D-pad: slide your thumb around without lifting.
struct DPadView: View {
    let emu: Emulator; let size: Double
    @ObservedObject private var store = SettingsStore.shared
    @GestureState private var touch: CGPoint? = nil
    @State private var mask: UInt32 = 0

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            arm(GBABit.up, 0, -1); arm(GBABit.down, 0, 1); arm(GBABit.left, -1, 0); arm(GBABit.right, 1, 0)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).updating($touch) { v, s, _ in s = v.location })
        .onChange(of: touch) { p in if let p { update(p) } else { apply(0) } }
        .onDisappear { apply(0) }
    }

    private func arm(_ bit: UInt32, _ dx: Double, _ dy: Double) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(mask & bit != 0 ? Color.white.opacity(0.6) : Color.white.opacity(0.25))
            .frame(width: size * (dx == 0 ? 0.30 : 0.34), height: size * (dy == 0 ? 0.30 : 0.34))
            .offset(x: dx * size * 0.31, y: dy * size * 0.31)
    }

    private func update(_ p: CGPoint) {
        let r = size / 2
        let nx = (p.x - r) / r, ny = (p.y - r) / r
        let dz = store.prefs.dpadDeadzone
        var m: UInt32 = 0
        if hypot(nx, ny) > dz * 0.6 {
            let t = max(dz * 0.8, 0.2)
            if nx > t { m |= GBABit.right }; if nx < -t { m |= GBABit.left }
            if ny > t { m |= GBABit.down };  if ny < -t { m |= GBABit.up }
        }
        apply(m)
    }

    private func apply(_ m: UInt32) {
        guard m != mask else { return }
        if m & ~mask != 0 { Haptics.tap() }
        mask = m
        let all = GBABit.up | GBABit.down | GBABit.left | GBABit.right
        emu.touchKeys = (emu.touchKeys & ~all) | m
    }
}

/// A and B on one pad: slide between them without lifting, or touch the middle to hold both.
struct ABCluster: View {
    let emu: Emulator; let base: Double
    @GestureState private var touch: CGPoint? = nil
    @State private var mask: UInt32 = 0

    private var w: Double { base * 2.3 }
    private var h: Double { base * 1.7 }
    private var aCenter: CGPoint { CGPoint(x: w - base * 0.6, y: base * 0.6) }
    private var bCenter: CGPoint { CGPoint(x: base * 0.6, y: h - base * 0.6) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(Color.white.opacity(0.08)).frame(width: w, height: h)
            face("B", bCenter, mask & GBABit.b != 0)
            face("A", aCenter, mask & GBABit.a != 0)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).updating($touch) { v, s, _ in s = v.location })
        .onChange(of: touch) { p in if let p { update(p) } else { apply(0) } }
        .onDisappear { apply(0) }
    }

    private func face(_ t: String, _ c: CGPoint, _ on: Bool) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(on ? 0.55 : 0.22))
            Text(t).font(.system(size: base * 0.42, weight: .bold)).foregroundColor(.white)
        }
        .frame(width: base, height: base)
        .position(x: c.x, y: c.y)
    }

    private func update(_ p: CGPoint) {
        let hit = base * 0.75
        let dA = hypot(p.x - aCenter.x, p.y - aCenter.y), dB = hypot(p.x - bCenter.x, p.y - bCenter.y)
        var m: UInt32 = 0
        if dA < hit { m |= GBABit.a }
        if dB < hit { m |= GBABit.b }
        if m == 0 && min(dA, dB) < base * 1.1 { m = dA < dB ? GBABit.a : GBABit.b }   // forgiving edge
        apply(m)
    }

    private func apply(_ m: UInt32) {
        guard m != mask else { return }
        if m & ~mask != 0 { Haptics.tap() }
        mask = m
        let ab = GBABit.a | GBABit.b
        emu.touchKeys = (emu.touchKeys & ~ab) | m
    }
}
