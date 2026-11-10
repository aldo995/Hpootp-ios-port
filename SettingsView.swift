import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var pads = ControllerManager.shared
    var onEditLayout: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("Rewind & saves") {
                Toggle("Rewind", isOn: $store.prefs.rewindEnabled)
                Stepper("Rewind length: \(store.prefs.rewindSeconds)s", value: $store.prefs.rewindSeconds, in: 5...20, step: 5)
                    .disabled(!store.prefs.rewindEnabled)
                Toggle("iCloud save sync", isOn: $store.prefs.iCloudSync)
                if store.prefs.iCloudSync && !CloudSync.available {
                    Text("iCloud isn't available in this build. It needs the iCloud capability (a paid Apple Developer account) and being signed in to iCloud. See the README.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Text("Cheats and per-game control profiles are in the in-game pause menu.").font(.footnote).foregroundColor(.secondary)
            }
            Section("Touch controls") {
                Toggle("Show on-screen controls", isOn: $store.prefs.showTouch)
                Toggle("Hide when a controller is connected", isOn: $store.prefs.hideTouchWithController)
                slider("Opacity", $store.prefs.opacity, 0.15...1)
                slider("Size", $store.prefs.scale, 0.6...1.6)
                slider("D-pad dead zone", $store.prefs.dpadDeadzone, 0.1...0.6)
                Toggle("Haptic feedback", isOn: $store.prefs.haptics)
                Toggle("Combine A/B (slide between them)", isOn: $store.prefs.abCluster)
                if let onEditLayout { Button("Edit layout (drag & resize)", action: onEditLayout) }
                Button("Reset layout", role: .destructive) { store.resetLayout() }
            }
            Section("Controller") {
                if pads.names.isEmpty { Text("No controller connected").foregroundColor(.secondary) }
                ForEach(pads.names, id: \.self) { Text("🎮 \($0)") }
                slider("Stick dead zone", $store.prefs.stickDeadzone, 0.1...0.8)
                ForEach(PadInput.allCases) { input in
                    Picker(input.title, selection: Binding(get: { store.action(for: input) }, set: { store.setAction($0, for: input) })) {
                        ForEach(PadAction.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Text("D-pad and left stick always control the direction keys.").font(.footnote).foregroundColor(.secondary)
            }
            Section("Keyboard") {
                Text(pads.keyboardConnected ? "⌨️ Hardware keyboard connected" : "No keyboard connected").foregroundColor(.secondary)
                ForEach(PadAction.bindable) { a in
                    Picker(a.rawValue, selection: Binding(get: { store.keyChoice(for: a) }, set: { store.setKey($0, for: a) })) {
                        ForEach(KeyChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            Section("Display") {
                Picker("Screen filter", selection: $store.prefs.filter) {
                    ForEach(ScreenFilter.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("GBA LCD color correction", isOn: $store.prefs.colorCorrect)
            }
            Section("Emulation") {
                Stepper("Fast-forward: \(store.prefs.ffSpeed)×", value: $store.prefs.ffSpeed, in: 2...8)
            }
            Section { Button("Reset everything", role: .destructive) { store.resetAll() } }
        }
        .navigationTitle("Settings")
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text("\(title): \(String(format: "%.2f", v.wrappedValue))").font(.subheadline); Slider(value: v, in: r) }
    }
}
