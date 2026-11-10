import SwiftUI

struct Cheat: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var code: String          // one or more GameShark / Action Replay lines
    var enabled = true
    /// GameShark / Action Replay / CodeBreaker line: 8 hex digits, optional separator, 4-8 hex digits.
    static func isValid(_ line: String) -> Bool {
        line.range(of: #"^[0-9A-Fa-f]{8}[ :-]?[0-9A-Fa-f]{4,8}$"#, options: .regularExpression) != nil
    }
}

/// Cheats are stored per game (by ROM file name). No codes are bundled — users enter their own.
final class CheatStore: ObservableObject {
    static let shared = CheatStore()
    @Published var cheats: [Cheat] = [] { didSet { save() } }
    private var game = ""

    func load(game: String) {
        self.game = game
        let d = UserDefaults.standard.data(forKey: "PhoenixGBA.cheats.\(game)")
        cheats = d.flatMap { try? JSONDecoder().decode([Cheat].self, from: $0) } ?? []
    }
    private func save() {
        guard !game.isEmpty, let d = try? JSONEncoder().encode(cheats) else { return }
        UserDefaults.standard.set(d, forKey: "PhoenixGBA.cheats.\(game)")
    }
    func enabledBlocks() -> [String] { cheats.filter { $0.enabled }.map { $0.code } }
}

struct CheatsView: View {
    let emu: Emulator
    @ObservedObject private var store = CheatStore.shared
    @State private var adding = false
    @State private var name = ""
    @State private var code = ""
    @State private var badLine: String?

    var body: some View {
        List {
            Section(footer: Text("Enter GameShark / Action Replay codes (8 hex digits, a space, 8 hex digits), one per line. No codes are included — use ones made for your game version. Cheats can corrupt saves, so make a quick save first.")) {
                if store.cheats.isEmpty { Text("No cheats yet. Tap + to add one.").foregroundColor(.secondary) }
                ForEach($store.cheats) { $c in Toggle(c.name, isOn: $c.enabled) }
                    .onDelete { store.cheats.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("Cheats")
        .toolbar { Button { name = ""; code = ""; adding = true } label: { Image(systemName: "plus") } }
        .onChange(of: store.cheats) { _ in emu.applyCheats() }
        .alert("Can't save cheat", isPresented: Binding(get: { badLine != nil }, set: { _ in badLine = nil })) { Button("OK") {} } message: { Text(badLine ?? "") }
        .sheet(isPresented: $adding) {
            NavigationView {
                Form {
                    TextField("Name", text: $name)
                    TextEditor(text: $code).frame(minHeight: 140)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters).disableAutocorrection(true)
                }
                .navigationTitle("New cheat")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let lines = code.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            if lines.count > 64 { badLine = "Too many lines (max 64 per cheat)."; return }
                            if let bad = lines.first(where: { !Cheat.isValid($0) }) { badLine = "\"\(bad)\" isn't a valid code line."; return }
                            let n = String(name.trimmingCharacters(in: .whitespaces).prefix(60))
                            store.cheats.append(Cheat(name: n.isEmpty ? "Cheat \(store.cheats.count + 1)" : n, code: lines.joined(separator: "\n").uppercased()))
                            adding = false
                        }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
