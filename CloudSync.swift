import UIKit

/// Syncs battery saves (.sav) and quick-save states (.ss0) through the app's iCloud container. Newest file wins;
/// an older local copy that gets replaced is kept as <name>.bak.
enum CloudSync {
    private static var cached: URL?
    private static let queue = DispatchQueue(label: "phoenixgba.cloudsync")
    private static let exts = ["sav", "ss0"]
    static var available: Bool { cached != nil }

    /// Call once at launch; looking up the container can block, so it runs off the main thread.
    static func prepare() {
        queue.async {
            let u = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true)
            if let u { try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
            DispatchQueue.main.async { cached = u }
        }
    }

    private static func modDate(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }

    /// Before a game starts: take newer saves from iCloud.
    static func pull(rom: URL) {
        guard SettingsStore.shared.prefs.iCloudSync, let cloud = cached else { return }
        let fm = FileManager.default
        let base = rom.deletingPathExtension()
        for e in exts {
            let remote = cloud.appendingPathComponent("\(base.lastPathComponent).\(e)")
            let local = base.appendingPathExtension(e)
            try? fm.startDownloadingUbiquitousItem(at: remote)          // if only a placeholder, it arrives for next time
            guard fm.fileExists(atPath: remote.path), let rd = modDate(remote) else { continue }
            if let ld = modDate(local), ld >= rd { continue }
            if fm.fileExists(atPath: local.path) {
                let bak = local.appendingPathExtension("bak")
                try? fm.removeItem(at: bak); try? fm.copyItem(at: local, to: bak)
            }
            try? fm.removeItem(at: local); try? fm.copyItem(at: remote, to: local)
        }
    }

    /// After quitting / backgrounding: upload newer local saves.
    static func push(rom: URL) {
        guard SettingsStore.shared.prefs.iCloudSync, let cloud = cached else { return }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
        queue.async {
            let fm = FileManager.default
            let base = rom.deletingPathExtension()
            for e in exts {
                let local = base.appendingPathExtension(e)
                let remote = cloud.appendingPathComponent("\(base.lastPathComponent).\(e)")
                guard fm.fileExists(atPath: local.path), let ld = modDate(local) else { continue }
                if fm.fileExists(atPath: remote.path), let rd = modDate(remote), rd >= ld { continue }
                try? fm.removeItem(at: remote); try? fm.copyItem(at: local, to: remote)
            }
            DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(bg) }
        }
    }
}
