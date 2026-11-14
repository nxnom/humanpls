import SwiftUI
import AppKit
import AVKit
import AVFoundation
import PDFKit
import WebKit
import Combine

// MARK: caches (decode once, never in a view body)

@MainActor
enum Cache {
    static var thumbs: [String: NSImage] = [:]
    static var posters: [String: NSImage] = [:]
    static var players: [String: AVPlayer] = [:]
    static var audio: [String: AudioModel] = [:]

    static func thumb(_ path: String, maxPixel: Int = 900) async -> NSImage? {
        if let t = thumbs[path] { return t }
        let cg: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maxPixel]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
        }.value
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbs[path] = img
        return img
    }

    static func poster(_ path: String) async -> NSImage? {
        if let p = posters[path] { return p }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 900, height: 600)
        guard let r = try? await gen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return nil }
        let img = NSImage(cgImage: r.image, size: NSSize(width: r.image.width, height: r.image.height))
        posters[path] = img
        return img
    }

    static func player(_ path: String) -> AVPlayer {
        if let p = players[path] { return p }
        let p = AVPlayer(url: URL(fileURLWithPath: path))
        players[path] = p
        return p
    }

    static func audioModel(_ path: String) -> AudioModel {
        if let m = audio[path] { return m }
        let m = AudioModel(path: path)
        audio[path] = m
        return m
    }

    static func stopAll() {
        players.values.forEach { $0.pause() }
        audio.values.forEach { $0.stop() }
    }
}

func fmtTime(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

// MARK: audio

@MainActor
final class AudioModel: ObservableObject {
    static weak var current: AudioModel?
    let player: AVAudioPlayer?
    @Published var progress = 0.0
    @Published var playing = false
    @Published var bars: [Float] = []
    private var timer: Timer?
    private let path: String

    init(path: String) {
        self.path = path
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player?.prepareToPlay()
    }

    var duration: Double { player?.duration ?? 0 }

    func loadBars() async {
        guard bars.isEmpty else { return }
        let p = path
        let result: [Float] = await Task.detached(priority: .utility) {
            guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: p)),
                  f.length > 0, f.length < 60_000_000,
                  let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return [] }
            try? f.read(into: buf)
            guard let ch = buf.floatChannelData?[0] else { return [] }
            let n = Int(buf.frameLength), count = 90, step = max(1, n / count)
            var out: [Float] = []
            for i in 0..<count {
                var s: Float = 0; let a = i * step, b = min(n, a + step)
                if a < b { for j in a..<b { s += abs(ch[j]) }; s /= Float(b - a) }
                out.append(s)
            }
            let m = out.max() ?? 1
            return out.map { $0 / max(m, 0.0001) }
        }.value
        bars = result
    }

    func toggle() {
        guard let p = player else { return }
        if playing { p.pause(); playing = false; timer?.invalidate(); return }
        if AudioModel.current !== self { AudioModel.current?.stop() }
        AudioModel.current = self
        p.play(); playing = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
                if !p.isPlaying { self.playing = false; self.timer?.invalidate(); if self.progress > 0.99 { self.progress = 0 } }
            }
        }
    }
    func stop() { player?.stop(); player?.currentTime = 0; playing = false; progress = 0; timer?.invalidate() }
    func seek(_ f: Double) { player?.currentTime = f * duration; progress = f }
}

struct Wave: View {
    let bars: [Float]; let progress: Double
    var body: some View {
        Canvas { ctx, size in
            let n = bars.count; guard n > 0 else { return }
            let w = size.width / CGFloat(n)
            for (i, b) in bars.enumerated() {
                let h = max(3, CGFloat(b) * size.height)
                let r = CGRect(x: CGFloat(i) * w + 1, y: (size.height - h) / 2, width: max(1, w - 2), height: h)
                let on = Double(i) / Double(n) < progress
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(on ? .accentColor : .secondary.opacity(0.4)))
            }
        }
    }
}

struct AudioPlayerRow: View {
    let path: String
    @ObservedObject var m: AudioModel
    init(path: String) { self.path = path; _m = ObservedObject(wrappedValue: Cache.audioModel(path)) }
    var body: some View {
        HStack(spacing: 12) {
            Button { m.toggle() } label: {
                Image(systemName: m.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
            }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            VStack(alignment: .trailing, spacing: 2) {
                GeometryReader { g in
                    Wave(bars: m.bars, progress: m.progress).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { v in m.seek(min(1, max(0, v.location.x / g.size.width))) })
                }.frame(height: 34)
                Text("\(fmtTime(m.progress * m.duration)) / \(fmtTime(m.duration))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }.task { await m.loadBars() }
    }
}

// MARK: image: native zoom (NSScrollView magnification = trackpad pinch)

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        if let d = documentView {
            if r.width > d.frame.width { r.origin.x = (d.frame.width - r.width) / 2 }
            if r.height > d.frame.height { r.origin.y = (d.frame.height - r.height) / 2 }
        }
        return r
    }
}

final class FitScrollView: NSScrollView {
    var imgSize = NSSize.zero
    var fitted = false
    override func layout() {
        super.layout()
        if !fitted, bounds.width > 0, imgSize.width > 0 { fitted = true; fit() }
    }
    func fit() { magnify(toFit: NSRect(origin: .zero, size: imgSize)) }
    func toggleFit() {
        if abs(magnification - 1) < 0.01 { fit() }
        else { setMagnification(1, centeredAt: NSPoint(x: imgSize.width / 2, y: imgSize.height / 2)) }
    }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { toggleFit() } else { super.mouseDown(with: e) }
    }
}

struct ZoomImage: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> FitScrollView {
        let sv = FitScrollView()
        sv.contentView = CenteringClipView()
        sv.allowsMagnification = true
        sv.minMagnification = 0.05; sv.maxMagnification = 16
        sv.hasVerticalScroller = true; sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = true; sv.backgroundColor = NSColor(white: 0.1, alpha: 1)
        if let img = NSImage(contentsOfFile: path) {
            // use pixel size so 100% really is 100%
            if let rep = img.representations.first, rep.pixelsWide > 0 { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }
            let iv = NSImageView(frame: NSRect(origin: .zero, size: img.size))
            iv.image = img; iv.imageScaling = .scaleAxesIndependently
            sv.documentView = iv; sv.imgSize = img.size
        }
        return sv
    }
    func updateNSView(_ v: FitScrollView, context: Context) {}
}

// MARK: video: native player with J K L, frame step

final class KeyVideoView: AVPlayerView {
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    var onMark: ((Double) -> Void)?
    override func keyDown(with e: NSEvent) {
        guard let p = player else { super.keyDown(with: e); return }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "k": p.pause()
        case "l": let r = p.rate; p.rate = r > 0 ? min(r * 2, 8) : 1
        case "j": let r = p.rate; p.rate = r < 0 ? max(r * 2, -8) : -1
        case " ": if p.rate == 0 { p.play() } else { p.pause() }
        case "m": onMark?(p.currentTime().seconds)
        default:
            if e.keyCode == 123 { p.pause(); p.currentItem?.step(byCount: -1) }
            else if e.keyCode == 124 { p.pause(); p.currentItem?.step(byCount: 1) }
            else { super.keyDown(with: e) }
        }
    }
}

struct KeyVideo: NSViewRepresentable {
    let player: AVPlayer
    var onMark: ((Double) -> Void)? = nil
    func makeNSView(context: Context) -> KeyVideoView {
        let v = KeyVideoView()
        v.player = player; v.controlsStyle = .floating
        v.showsFrameSteppingButtons = true; v.showsFullScreenToggleButton = false
        v.onMark = onMark
        return v
    }
    func updateNSView(_ v: KeyVideoView, context: Context) { v.onMark = onMark }
}

struct VideoViewer: View {
    let path: String
    var onMark: ((Double) -> Void)? = nil
    @State var rate: Float = 0
    var body: some View {
        let player = Cache.player(path)
        KeyVideo(player: player, onMark: onMark).background(Color.black)
            .overlay(alignment: .topLeading) {
                if rate != 0 && rate != 1 {
                    Text(rate < 0 ? "◀◀ \(String(format: "%g", Double(-rate)))×" : "▶▶ \(String(format: "%g", Double(rate)))×")
                        .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.6), in: Capsule()).padding(14)
                }
            }
            .onReceive(player.publisher(for: \.rate)) { rate = $0 }
            .onAppear { player.seek(to: .zero); player.play() }
            .onDisappear { player.pause() }
    }
}

// MARK: other native views

struct PDFRep: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = PDFDocument(url: URL(fileURLWithPath: path))
        v.autoScales = true; v.displayMode = .singlePageContinuous
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}

/// A web view for HTML (the option's own page, or markdown and code rendered to HTML).
struct WebRep: NSViewRepresentable {
    var path: String? = nil
    var html: String? = nil
    var baseDir: String? = nil
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.setValue(false, forKey: "drawsBackground")
        if let p = path {
            let u = URL(fileURLWithPath: p)
            w.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
        } else if let h = html {
            let base = baseDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            w.loadHTMLString(h, baseURL: base)
        }
        return w
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
}

struct Badge: View {
    var body: some View {
        Text("Recommended").font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.18), in: Capsule()).foregroundStyle(Color.accentColor)
    }
}
