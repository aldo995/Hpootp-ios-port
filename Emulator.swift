import SwiftUI
import AVFoundation
import QuartzCore

/// Small FIFO between the emulation thread (writer) and the real-time audio callback (reader).
/// The lock is only held for a memcpy, so the audio thread never waits on a whole emulated frame.
final class AudioRing {
    private let capacity = 4096                       // frames (~85 ms): bounds audio latency
    private var buf: [Int16]
    private var head = 0, count = 0
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        buf = [Int16](repeating: 0, count: 4096 * 2)
        lock = .allocate(capacity: 1); lock.initialize(to: os_unfair_lock())
    }
    deinit { lock.deallocate() }

    func clear() { os_unfair_lock_lock(lock); head = 0; count = 0; os_unfair_lock_unlock(lock) }

    func write(_ p: UnsafePointer<Int16>, frames: Int) {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        let n = min(frames, capacity)
        if count + n > capacity { let drop = count + n - capacity; head = (head + drop) % capacity; count -= drop }   // drop oldest
        for i in 0..<n {
            let w = ((head + count + i) % capacity) * 2
            buf[w] = p[i * 2]; buf[w + 1] = p[i * 2 + 1]
        }
        count += n
    }

    func read(_ out: UnsafeMutablePointer<Int16>, frames: Int) -> Int {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        let n = min(frames, count)
        for i in 0..<n {
            let r = ((head + i) % capacity) * 2
            out[i * 2] = buf[r]; out[i * 2 + 1] = buf[r + 1]
        }
        head = (head + n) % capacity; count -= n
        return n
    }
}

final class Emulator: ObservableObject {
    /// Latest RGBA8 frame (240x160). Written and read on the main thread only.
    private(set) var pixels = [UInt32](repeating: 0, count: 240 * 160)
    @Published var fastForward = false
    @Published var rewinding = false
    @Published var paused = false {
        didSet {
            guard oldValue != paused else { return }
            link?.isPaused = paused
            if paused { engine.pause() } else { ring.clear(); try? engine.start() }
        }
    }
    var onMenu: (() -> Void)?

    /// Touch and controller inputs are kept separately and OR'd together.
    var touchKeys: UInt32 = 0 { didSet { pushKeys() } }
    var padKeys: UInt32 = 0 { didSet { pushKeys() } }

    private let core = GBACore()
    private var link: CADisplayLink?
    private let engine = AVAudioEngine()
    private let ring = AudioRing()
    private let lock = NSLock()                    // guards `core` (main thread only now; audio thread no longer touches it)
    private var scratch = [Int16](repeating: 0, count: 8192)
    private var romURL: URL?
    private var history: [Data] = []               // rewind ring buffer (one snapshot per 6 frames)
    private var frameCounter = 0
    private var stopped = false
    private var observers: [NSObjectProtocol] = []

    func start(rom: URL) throws {
        romURL = rom
        stopped = false
        CloudSync.pull(rom: rom)
        try core.loadROM(atPath: rom.path)
        CheatStore.shared.load(game: rom.deletingPathExtension().lastPathComponent)
        applyCheats()
        ControllerManager.shared.emulator = self
        ControllerManager.shared.start()
        setupAudio()
        observeSystemEvents()
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60)
        link?.add(to: .main, forMode: .common)
    }

    /// Safe to call more than once.
    func stop() {
        guard !stopped else { return }
        stopped = true
        link?.invalidate(); link = nil
        engine.stop()
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if ControllerManager.shared.emulator === self { ControllerManager.shared.emulator = nil }
        lock.lock(); core.shutdown(); history.removeAll(); lock.unlock()
        touchKeys = 0; padKeys = 0
        syncCloud()
    }

    func syncCloud() { if let r = romURL { CloudSync.push(rom: r) } }

    func applyCheats() {
        let blocks = CheatStore.shared.enabledBlocks()
        lock.lock(); core.applyCheats(blocks); lock.unlock()
    }

    private func pushKeys() { lock.lock(); core.setKeys(GBAKey(rawValue: touchKeys | padKeys)); lock.unlock() }

    func saveState() { lock.lock(); core.saveState(toSlot: 0); lock.unlock() }
    func loadState() { lock.lock(); core.loadState(fromSlot: 0); history.removeAll(); lock.unlock() }

    @objc private func tick() {
        let prefs = SettingsStore.shared.prefs
        let canRewind = prefs.rewindEnabled
        lock.lock()
        if rewinding && canRewind {
            if let s = history.popLast() { _ = core.restoreState(s); core.runFrame() }   // runFrame refreshes the picture
            _ = core.readAudio(&scratch, frames: 4096)                                    // drop audio while rewinding
        } else {
            let n = fastForward ? prefs.ffSpeed : 1
            for _ in 0..<n {
                core.runFrame()
                frameCounter &+= 1
                if canRewind, !fastForward, frameCounter % 6 == 0, let s = core.captureState() {
                    history.append(s)
                    let cap = max(1, prefs.rewindSeconds * 10)
                    if history.count > cap { history.removeFirst(history.count - cap) }
                }
            }
            let got = Int(core.readAudio(&scratch, frames: 2048))
            if fastForward { /* drop audio while sped up */ }
            else if got > 0 { scratch.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: got) } }
        }
        pixels.withUnsafeMutableBufferPointer { core.copyVideo(to: $0.baseAddress!) }
        lock.unlock()
    }

    // MARK: Audio + system events

    private func setupAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
        let ring = self.ring
        let src = AVAudioSourceNode(format: fmt) { _, _, n, abl in
            let b = UnsafeMutableAudioBufferListPointer(abl)[0]
            guard let p = b.mData?.assumingMemoryBound(to: Int16.self) else { return noErr }
            let got = ring.read(p, frames: Int(n))
            if got < Int(n) { memset(p + got * 2, 0, (Int(n) - got) * 4) }      // underrun -> silence, never garbage
            return noErr
        }
        engine.attach(src); engine.connect(src, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    private func observeSystemEvents() {
        let nc = NotificationCenter.default
        // Phone call / Siri / alarm interrupts audio: restart it afterwards.
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, !self.paused,
                  let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            try? self.engine.start()
        })
        // Headphones unplugged etc. can stop the engine.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, !self.paused else { return }
            try? self.engine.start()
        })
        // Rewind history is the biggest memory user: shed it under pressure instead of being killed.
        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.history.removeAll(); self.lock.unlock()
        })
    }
}
