import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HumanplsCore

/// Files the person adds to a note, the feedback or the message ("use this kind of style").
/// A file on disk is used where it is. An image that only exists on the clipboard or in a drag (a screenshot,
/// an image from a browser) is written as a PNG into the app's own folder.
@MainActor
enum Attachments {
    static var dir: String {
        let d = (Paths.support as NSString).appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// The field that has the keyboard focus now. Command-V with a file or an image on the clipboard goes to it.
    static var focused: (id: UUID, add: ([String]) -> Void)?
    private static var monitor: Any?

    static func focus(_ id: UUID, _ add: @escaping ([String]) -> Void) {
        focused = (id, add)
        guard monitor == nil else { return }
        // A local monitor runs before the Edit menu, so it can take Command-V when the clipboard has no text to paste.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command, e.charactersIgnoringModifiers == "v",
                  let f = focused, isTypingInTextField() else { return e }
            let files = fromPasteboard(.general)
            guard !files.isEmpty else { return e }      // normal text paste
            f.add(files)
            return nil
        }
    }
    static func blur(_ id: UUID) { if focused?.id == id { focused = nil } }

    /// Files copied in Finder, or an image copied as data. Empty when the clipboard is text.
    static func fromPasteboard(_ pb: NSPasteboard) -> [String] {
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { return urls.map { $0.path } }
        if pb.string(forType: .string) == nil, let png = pngData(pb), let p = save(png) { return [p] }
        return []
    }

    static func pngData(_ pb: NSPasteboard) -> Data? {
        if let d = pb.data(forType: .png) { return d }
        if let d = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: d) { return rep.representation(using: .png, properties: [:]) }
        return nil
    }

    static func save(_ png: Data) -> String? {
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyMMdd-HHmmss"
        var out = (dir as NSString).appendingPathComponent("attached-\(stamp.string(from: Date())).png")
        var n = 2
        while FileManager.default.fileExists(atPath: out) {
            out = (dir as NSString).appendingPathComponent("attached-\(stamp.string(from: Date()))-\(n).png"); n += 1
        }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { return nil }
        return out
    }

    /// The open panel, as a sheet on the popup (the popup floats, a free panel could open behind it).
    static func choose(_ add: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        panel.message = "Attach files for the agent, for example an image with the style you want"
        let done: (NSApplication.ModalResponse) -> Void = { r in if r == .OK { add(panel.urls.map { $0.path }) } }
        if let w = NSApp.keyWindow { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Files dropped on a field: from Finder (file URLs) or an image dragged out of another app (data).
    static func drop(_ providers: [NSItemProvider], _ add: @escaping ([String]) -> Void) -> Bool {
        var took = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in add([url.path]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                took = true
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in if let path = save(png) { add([path]) } }
                }
            }
        }
        return took
    }

    /// Delete pasted images older than two weeks.
    static func prune() {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
            let p = (dir as NSString).appendingPathComponent(n)
            if let d = (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date, d < cutoff { try? FileManager.default.removeItem(atPath: p) }
        }
    }
}

/// One attached file: a small picture (for images), the name, and a remove button. Click to Quick Look.
struct AttachmentChip: View {
    let path: String
    let all: [String]
    let remove: () -> Void
    @State var img: NSImage? = nil

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let img { Image(nsImage: img).resizable().scaledToFill() }
                else { Image(systemName: "doc").font(.caption).foregroundStyle(.secondary) }
            }.frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
            Text((path as NSString).lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
        }
        .padding(.leading, 4).padding(.trailing, 6).padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { QuickLook.shared.show(all, index: all.firstIndex(of: path) ?? 0) }
        .help(path)
        .task(id: path) { if Kinds.kind(ofPath: path)?.0 == .image { img = await Cache.thumb(path, maxPixel: 120) } }
    }
}
