import SwiftUI
import AppKit
import AVFoundation
import HumanplsCore

@MainActor
final class ShowModel: ObservableObject {
    let job: Job
    let waiting: Bool
    var items: [Item] { job.sections.first?.items ?? [] }
    @Published var selection: String?
    @Published var state = ShowState()
    let store = AnnotationStore()
    var onFinish: (FinishAction, String) -> Void = { _, _ in }

    init(job: Job, waiting: Bool) {
        self.job = job; self.waiting = waiting
        selection = job.sections.first?.items.first?.key
    }

    var current: Item? { items.first { $0.key == selection } ?? items.first }
    var index: Int { items.firstIndex { $0.key == current?.key } ?? 0 }
    func move(_ d: Int) { guard !items.isEmpty else { return }; selection = items[min(items.count - 1, max(0, index + d))].key }

    var text: String { ShowAnswer.make(job: job, state: state) }

    func finish(_ a: FinishAction) {
        if a != .cancel {
            for it in items where it.kind == .image {
                if let p = it.path, store.has(p), let out = store.export(p) { state.annotated[it.key] = out }
            }
        }
        onFinish(a, text)
    }
}

struct Thumb: View {
    let item: Item
    @State var img: NSImage? = nil
    var body: some View {
        Color.black.opacity(0.25)
            .overlay {
                ZStack {
                    if let img { Image(nsImage: img).resizable().scaledToFill() }
                    switch item.kind {
                    case .video: Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.9)).shadow(radius: 2)
                    case .audio: Image(systemName: "waveform").font(.title3).foregroundStyle(.secondary)
                    case .markdown, .text, .code, .html, .url: Image(systemName: "doc.text").font(.title3).foregroundStyle(.secondary)
                    case .file: Image(systemName: "doc").font(.title3).foregroundStyle(.secondary)
                    case .pdf: Image(systemName: "doc.richtext").font(.title3).foregroundStyle(.secondary)
                    default: EmptyView()
                    }
                }
            }
            .clipped()
            .task(id: item.key) {
                guard let p = item.path else { return }
                if item.kind == .image { img = await Cache.thumb(p, maxPixel: 300) }
                else if item.kind == .video { img = await Cache.poster(p) }
            }
    }
}

enum Info {
    @MainActor static var cache: [String: String] = [:]
    @MainActor static func make(_ it: Item) async -> String {
        guard let path = it.path else { return "" }
        if let c = cache[path] { return c }
        var parts: [String] = []
        if let sz = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(sz), countStyle: .file))
        }
        if it.kind == .image, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let pr = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = pr[kCGImagePropertyPixelWidth] as? Int, let h = pr[kCGImagePropertyPixelHeight] as? Int {
            parts.append("\(w) × \(h)")
        }
        if it.kind == .video || it.kind == .audio,
           let d = try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration).seconds, d.isFinite {
            parts.append(fmtTime(d))
        }
        let t = parts.joined(separator: " · ")
        cache[path] = t
        return t
    }
}

struct InfoText: View {
    let item: Item
    @State var text = ""
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).task(id: item.key) { text = await Info.make(item) }
    }
}

struct AudioViewer: View {
    let path: String
    @ObservedObject var m: AudioModel
    init(path: String) { self.path = path; _m = ObservedObject(wrappedValue: Cache.audioModel(path)) }
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            GeometryReader { g in
                Wave(bars: m.bars, progress: m.progress).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in m.seek(min(1, max(0, v.location.x / g.size.width))) })
            }.frame(height: 140).padding(.horizontal, 40)
            HStack(spacing: 16) {
                Button { m.toggle() } label: { Image(systemName: m.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 54)) }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                Text("\(fmtTime(m.progress * m.duration)) / \(fmtTime(m.duration))").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await m.loadBars() }
        .onDisappear { m.stop() }
    }
}

struct ShowRoot: View {
    @ObservedObject var model: ShowModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(model.items, selection: Binding(get: { model.current?.key }, set: { model.selection = $0 })) { it in
                    HStack(spacing: 10) {
                        Thumb(item: it).frame(width: 52, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(it.fileName ?? it.key).lineLimit(1).font(.callout)
                    }.tag(it.key).padding(.vertical, 2)
                }.listStyle(.sidebar).frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
                VStack(spacing: 0) {
                    if let it = model.current {
                        viewer(it).id(it.key)
                        Text(hint(it)).font(.caption).foregroundStyle(.secondary).padding(6).frame(maxWidth: .infinity).background(.bar)
                    }
                }.frame(minWidth: 520)
            }
            Divider()
            HStack(spacing: 10) {
                if let it = model.current {
                    Text(it.fileName ?? "").font(.callout.weight(.medium)).lineLimit(1)
                    InfoText(item: it)
                }
                Spacer()
                if let it = model.current, it.kind == .image, let p = it.path { InfoButton(path: p) }
                if let it = model.current, let p = it.path {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                    Button("Copy path") { Sender.copy(p) }
                }
                TextField("Message (optional)", text: $model.state.message).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button(model.waiting ? "Send answer" : "Send") { model.finish(.send) }
                    .keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
            }.padding(10)
        }
    }

    @ViewBuilder func viewer(_ it: Item) -> some View {
        if !fileExists(it.path) { MissingFile(path: it.path ?? "").padding(30).frame(maxWidth: .infinity, maxHeight: .infinity) } else { kindViewer(it) }
    }

    @ViewBuilder func kindViewer(_ it: Item) -> some View {
        switch it.kind {
        case .file: FileInfoView(path: it.path ?? "", big: true)
        case .image:
            VStack(spacing: 0) {
                AnnotateBar(store: model.store, path: it.path ?? "")
                AnnotatableImage(path: it.path ?? "", store: model.store)
            }
        case .video: VideoViewer(path: it.path ?? "")
        case .audio: AudioViewer(path: it.path ?? "")
        case .pdf: PDFRep(path: it.path ?? "")
        case .html: WebRep(path: it.path)
        case .markdown, .code, .text: RichText(item: it)
        default: Text("No preview").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func hint(_ it: Item) -> String {
        switch it.kind {
        case .image: return "Pinch or scroll to zoom  ·  pick the hand to move  ·  double-click: fit / 100%"
        case .video: return "J ◀◀   K pause   L ▶▶   (press again for faster)   ·   ← → one frame   ·   Space play"
        case .audio: return "Click the waveform to seek"
        default: return ""
        }
    }
}
