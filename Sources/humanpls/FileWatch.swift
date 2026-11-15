import SwiftUI
import HumanplsCore

/// Watches the files of the open popups. When an agent writes a file again at the same path (renders the video again,
/// deletes it and makes a new one), the views that show it load it again, while the popup is open.
///
/// It looks at the files once a second. A file system event source would stop working when the file is deleted
/// and made again, which is exactly the case here.
@MainActor
final class FileWatch: ObservableObject {
    static let shared = FileWatch()

    /// Goes up by one each time the file was loaded again. Views use it as their identity.
    @Published private(set) var versions: [String: Int] = [:]
    private var watched: [String: Int] = [:]          // path -> how many open popups show it
    private var pending: [String: String] = [:]       // path -> the changed stamp we saw on the last look
    private var timer: Timer?

    func version(_ path: String?) -> Int { path.flatMap { versions[$0] } ?? 0 }

    func add(_ paths: Set<String>) {
        for p in paths { watched[p, default: 0] += 1 }
        guard timer == nil, !watched.isEmpty else { return }
        let t = Timer(timeInterval: 1, repeats: true) { _ in Task { @MainActor in FileWatch.shared.look() } }
        RunLoop.main.add(t, forMode: .common)         // also while a menu is open or the window is resized
        timer = t
    }

    func remove(_ paths: Set<String>) {
        for p in paths {
            if let n = watched[p], n > 1 { watched[p] = n - 1 } else { watched[p] = nil; pending[p] = nil }
        }
        if watched.isEmpty { timer?.invalidate(); timer = nil }
    }

    /// One look at all files. Returns the paths that were loaded again.
    @discardableResult
    func look() -> [String] {
        var reloaded: [String] = []
        for p in watched.keys {
            let now = Cache.stamp(p)
            if now == Cache.stamps[p] { pending[p] = nil; continue }
            // The file changed. Wait until it exists and is the same on two looks: the agent may still be writing it,
            // and between "delete" and "create" there is no file at all (the old one stays on screen meanwhile).
            if FileManager.default.fileExists(atPath: p), pending[p] == now {
                pending[p] = nil
                Cache.refresh(p)
                versions[p, default: 0] += 1
                reloaded.append(p)
            } else {
                pending[p] = now
            }
        }
        return reloaded
    }
}

/// Builds its content again when the file at `path` was written again.
struct Fresh<Content: View>: View {
    let path: String?
    @ObservedObject private var watch = FileWatch.shared
    @ViewBuilder var content: () -> Content
    var body: some View { content().id(watch.version(path)) }
}
