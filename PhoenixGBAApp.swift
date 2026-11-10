import SwiftUI
import UniformTypeIdentifiers

@main struct PhoenixGBAApp: App {
    var body: some Scene { WindowGroup { LibraryView().onAppear { ControllerManager.shared.start(); CloudSync.prepare() } } }
}

struct LibraryView: View {
    @State private var roms: [URL] = []
    @State private var importing = false
    @State private var showSettings = false
    @State private var importError: String?
    @State private var playing: URL?
    private var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    var body: some View {
        NavigationView {
            List(roms, id: \.self) { r in
                Button(r.deletingPathExtension().lastPathComponent) { playing = r }
            }
            .overlay { if roms.isEmpty { Text("Import your own .gba file to play.").foregroundColor(.secondary) } }
            .navigationTitle("Phoenix GBA")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Import ROM") { importing = true } }
            }
        }
        .sheet(isPresented: $showSettings) { NavigationView { SettingsView() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gba") ?? .data]) { res in
            switch res {
            case .failure(let e): importError = e.localizedDescription
            case .success(let url): importROM(url)
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("OK") {}
        } message: { Text(importError ?? "") }
        .fullScreenCover(item: $playing) { GameView(rom: $0) }
        .onAppear(perform: refresh)
    }
    /// Validates and copies a ROM into the app's Documents folder (atomically, so a failed copy never leaves a half-written file).
    private func importROM(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "gba" else { importError = "Only .gba files can be imported."; return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size >= 192, size <= 32 * 1024 * 1024 else { importError = "That file isn't the size of a GBA ROM (max 32 MB)."; return }
        let fm = FileManager.default
        let name = url.lastPathComponent.replacingOccurrences(of: "/", with: "_")
        let dest = dir.appendingPathComponent(name), tmp = dir.appendingPathComponent(name + ".importing")
        do {
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: url, to: tmp)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
            refresh()
        } catch { try? fm.removeItem(at: tmp); importError = error.localizedDescription }
    }

    private func refresh() {
        roms = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "gba" }
    }
}
extension URL: Identifiable { public var id: String { absoluteString } }

struct GameView: View {
    let rom: URL
    @StateObject private var emu = Emulator()
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var pads = ControllerManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showMenu = false
    @State private var editing = false
    @State private var selected: TouchControl?
    @State private var error: String?
    @GestureState private var rewindHeld = false

    private var touchVisible: Bool {
        store.prefs.showTouch && !(store.prefs.hideTouchWithController && !pads.names.isEmpty) || editing
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                screen.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: land ? .center : .top)
                if touchVisible { TouchControlsView(emu: emu, editing: editing, selected: $selected) }
                if editing { editBar } else { menuButton }
            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showMenu) { pauseMenu }
        .onChange(of: showMenu) { shown in emu.paused = shown || scenePhase != .active }
        .onChange(of: scenePhase) { phase in
            emu.paused = showMenu || phase != .active        // pause in background: Metal/audio can't run there anyway
            if phase == .background { emu.syncCloud() }
        }
        .onAppear {
            store.beginGame(rom.deletingPathExtension().lastPathComponent, allowProfiles: true)
            emu.onMenu = { showMenu = true }
            do { try emu.start(rom: rom) } catch { self.error = error.localizedDescription }
        }
        .onDisappear { store.endGame(); emu.stop() }   // stop() is idempotent
        .alert(error ?? "", isPresented: .constant(error != nil)) { Button("OK") { dismiss() } }
    }

    private var screen: some View { MetalScreen(emu: emu).aspectRatio(3 / 2, contentMode: .fit) }

    private var menuButton: some View {
        VStack { HStack(spacing: 14) {
            Button { showMenu = true } label: { Image(systemName: "line.3.horizontal.circle.fill").font(.title).foregroundColor(.white.opacity(0.5)) }
            if store.prefs.rewindEnabled { rewindButton }
            if emu.fastForward { Text("⏩").foregroundColor(.white) }
            if emu.rewinding { Text("⏪").foregroundColor(.white) }
            Spacer()
        }.padding(10); Spacer() }
    }

    /// Hold to rewind.
    private var rewindButton: some View {
        Image(systemName: "backward.circle.fill").font(.title).foregroundColor(.white.opacity(0.5))
            .gesture(DragGesture(minimumDistance: 0).updating($rewindHeld) { _, st, _ in st = true })
            .onChange(of: rewindHeld) { held in
                emu.rewinding = held
            }
    }

    private var editBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text(selected.map { "Editing \($0.title)" } ?? "Drag a control to move it").foregroundColor(.white)
                Spacer()
                Button("Reset") { store.resetLayout() }
                Button("Done") { editing = false; selected = nil }.bold()
            }
            if let c = selected {
                HStack { Text("Size").foregroundColor(.white)
                    Slider(value: Binding(get: { store.size(c) }, set: { store.setSize($0, c) }), in: 0.5...2.0) }
            }
        }
        .padding(10).background(Color.black.opacity(0.7)).cornerRadius(12).padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var pauseMenu: some View {
        NavigationView {
            List {
                Button("Resume") { showMenu = false }
                Button("Quick save") { emu.saveState(); showMenu = false }
                Button("Quick load") { emu.loadState(); showMenu = false }
                Toggle("Fast-forward", isOn: $emu.fastForward)
                Button("Edit touch controls") { showMenu = false; editing = true }
                NavigationLink("Cheats") { CheatsView(emu: emu) }
                Toggle("Per-game control profile", isOn: Binding(
                    get: { store.gameProfileActive },
                    set: { store.setGameProfile($0) }))
                NavigationLink("Settings & controller mapping") { SettingsView() }
                Button("Quit game", role: .destructive) { showMenu = false; emu.stop(); dismiss() }
            }
            .navigationTitle("Paused")
        }
    }
}
