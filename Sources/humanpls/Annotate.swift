import SwiftUI
import AppKit
import HumanplsCore

enum Tool: String, CaseIterable, Identifiable {
    case hand, pen, rect, arrow, text
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .hand: return "hand.draw"
        case .pen: return "pencil.tip"
        case .rect: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }
    var help: String {
        switch self {
        case .hand: return "Move and zoom"
        case .pen: return "Draw"
        case .rect: return "Rectangle"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count != 6 { h = "FF3B30" }
        let v = UInt32(h, radix: 16) ?? 0xFF3B30
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

/// Draws shapes. The same code paints the live canvas and the exported PNG, so they always match.
/// The drawing context must be flipped (origin top-left, image pixels).
enum AnnotationRenderer {
    static func lineWidth(_ size: NSSize) -> CGFloat { max(3, max(size.width, size.height) / 280) }
    static func fontSize(_ size: NSSize) -> CGFloat { max(16, max(size.width, size.height) / 40) }

    static func draw(_ shapes: [Drawing], imageSize: NSSize) {
        let lw = lineWidth(imageSize)
        for s in shapes {
            let color = NSColor(hex: s.color)
            color.setStroke(); color.setFill()
            let pts = s.points.map { NSPoint(x: $0.x, y: $0.y) }
            switch s.kind {
            case .pen:
                guard let first = pts.first else { continue }
                let p = NSBezierPath()
                p.move(to: first); pts.dropFirst().forEach { p.line(to: $0) }
                p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round
                p.stroke()
            case .rect:
                guard pts.count == 2 else { continue }
                let r = NSRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y), width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y))
                let p = NSBezierPath(roundedRect: r, xRadius: lw, yRadius: lw)
                p.lineWidth = lw; p.stroke()
            case .arrow:
                guard pts.count == 2 else { continue }
                let (a, b) = (pts[0], pts[1])
                let angle = atan2(b.y - a.y, b.x - a.x)
                let head = lw * 6
                let line = NSBezierPath()
                line.move(to: a)
                line.line(to: NSPoint(x: b.x - cos(angle) * head * 0.6, y: b.y - sin(angle) * head * 0.6))
                line.lineWidth = lw; line.lineCapStyle = .round; line.stroke()
                let tri = NSBezierPath()
                tri.move(to: b)
                tri.line(to: NSPoint(x: b.x - cos(angle - 0.45) * head, y: b.y - sin(angle - 0.45) * head))
                tri.line(to: NSPoint(x: b.x - cos(angle + 0.45) * head, y: b.y - sin(angle + 0.45) * head))
                tri.close(); tri.fill()
            case .text:
                guard let p = pts.first, let t = s.text else { continue }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSize(imageSize)),
                    .foregroundColor: color,
                    .backgroundColor: NSColor.black.withAlphaComponent(0.45),
                ]
                NSAttributedString(string: " \(t) ", attributes: attrs).draw(at: p)
            }
        }
    }

    /// The image with the drawings on it, as PNG data, at the image's own pixel size. Colors are exact sRGB.
    static func png(image: NSImage, shapes: [Drawing]) -> Data? {
        var w = Int(image.size.width), h = Int(image.size.height)
        if let rep = image.representations.first, rep.pixelsWide > 0 { w = rep.pixelsWide; h = rep.pixelsHigh }
        guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let size = NSSize(width: w, height: h)
        // the context starts bottom-left; flip it so drawings use image pixels from the top-left
        cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        draw(shapes, imageSize: size)
        NSGraphicsContext.restoreGraphicsState()
        guard let out = cg.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

// MARK: store

/// The drawings for every image in one popup. Exported to PNG files only when the answer is sent.
@MainActor
final class AnnotationStore: ObservableObject {
    @Published private(set) var sets: [String: AnnotationSet] = [:]
    @Published var tool: Tool = .hand
    @Published var color = AnnotationPalette.colors[0]

    func shapes(_ path: String) -> [Drawing] { sets[path]?.shapes ?? [] }
    func has(_ path: String) -> Bool { !(sets[path]?.isEmpty ?? true) }
    func canUndo(_ path: String) -> Bool { sets[path]?.canUndo ?? false }
    func canRedo(_ path: String) -> Bool { sets[path]?.canRedo ?? false }

    func add(_ path: String, _ s: Drawing) { var set = sets[path] ?? AnnotationSet(); set.add(s); sets[path] = set }
    func undo(_ path: String) { sets[path]?.undo(); objectWillChange.send() }
    func redo(_ path: String) { sets[path]?.redo(); objectWillChange.send() }
    func clear(_ path: String) { sets[path]?.clear(); objectWillChange.send() }

    static var dir: String {
        let d = (Paths.support as NSString).appendingPathComponent("annotations")
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// Writes the annotated PNG into the app's own folder (never next to the agent's file). Returns its path.
    func export(_ path: String) -> String? {
        guard has(path), let img = NSImage(contentsOfFile: path), let data = AnnotationRenderer.png(image: img, shapes: shapes(path)) else { return nil }
        let stamp = DateFormatter(); stamp.dateFormat = "yyMMdd-HHmmss"
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let out = (Self.dir as NSString).appendingPathComponent("\(stem)-annotated-\(stamp.string(from: Date())).png")
        do { try data.write(to: URL(fileURLWithPath: out)) } catch { return nil }
        return out
    }

    /// Delete exported files older than two weeks.
    static func prune() {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
            let p = (dir as NSString).appendingPathComponent(n)
            if let d = (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date, d < cutoff { try? FileManager.default.removeItem(atPath: p) }
        }
    }
}

// MARK: canvas

final class CanvasView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    let image: NSImage
    var shapes: [Drawing] = [] { didSet { needsDisplay = true } }
    var live: Drawing? { didSet { needsDisplay = true } }
    var tool: Tool = .hand { didSet { window?.invalidateCursorRects(for: self); commitText() } }
    var colorHex = AnnotationPalette.colors[0]
    var onCommit: ((Drawing) -> Void)?
    private var textField: NSTextField?
    private var textOrigin = NSPoint.zero

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        AnnotationRenderer.draw(shapes + (live.map { [$0] } ?? []), imageSize: image.size)
    }

    override func resetCursorRects() { addCursorRect(visibleRect, cursor: tool == .hand ? .openHand : (tool == .text ? .iBeam : .crosshair)) }

    func pt(_ e: NSEvent) -> NSPoint { convert(e.locationInWindow, from: nil) }

    override func mouseDown(with e: NSEvent) {
        commitText()
        let p = pt(e)
        switch tool {
        case .hand:
            if e.clickCount == 2 { (enclosingScrollView as? FitScrollView)?.toggleFit() }
        case .pen: live = Drawing(kind: .pen, points: [Pt(p.x, p.y)], color: colorHex)
        case .rect: live = Drawing(kind: .rect, points: [Pt(p.x, p.y), Pt(p.x, p.y)], color: colorHex)
        case .arrow: live = Drawing(kind: .arrow, points: [Pt(p.x, p.y), Pt(p.x, p.y)], color: colorHex)
        case .text: startText(at: p)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = pt(e)
        switch tool {
        case .hand:
            guard let sv = enclosingScrollView else { return }
            let clip = sv.contentView
            var o = clip.bounds.origin
            o.x -= e.deltaX / sv.magnification; o.y -= e.deltaY / sv.magnification
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
            sv.reflectScrolledClipView(clip)
        case .pen: live?.points.append(Pt(p.x, p.y))
        case .rect, .arrow: if live != nil { live?.points[1] = Pt(p.x, p.y) }
        case .text: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if let s = live { onCommit?(s) }
        live = nil
    }

    func startText(at p: NSPoint) {
        let fs = AnnotationRenderer.fontSize(image.size)
        let tf = NSTextField(frame: NSRect(x: p.x, y: p.y, width: max(240, fs * 12), height: fs * 1.7))
        tf.font = .boldSystemFont(ofSize: fs)
        tf.textColor = NSColor(hex: colorHex)
        tf.isBordered = false; tf.drawsBackground = true
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        tf.focusRingType = .none
        tf.placeholderString = "Type, then Enter"
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)
        textField = tf; textOrigin = p
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func commitText() {
        guard let tf = textField else { return }
        textField = nil
        let t = tf.stringValue
        tf.removeFromSuperview()
        if !t.isEmpty { onCommit?(Drawing(kind: .text, points: [Pt(textOrigin.x, textOrigin.y)], text: t, color: colorHex)) }
    }
}

/// The zoomable image with drawing on it. The pixels are read from the agent's file in place.
struct AnnotatableImage: NSViewRepresentable {
    let path: String
    @ObservedObject var store: AnnotationStore

    func makeNSView(context: Context) -> FitScrollView {
        let sv = FitScrollView()
        sv.contentView = CenteringClipView()
        sv.allowsMagnification = true
        sv.minMagnification = 0.05; sv.maxMagnification = 16
        sv.hasVerticalScroller = true; sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = true; sv.backgroundColor = NSColor(white: 0.1, alpha: 1)
        if let img = NSImage(contentsOfFile: path) {
            if let rep = img.representations.first, rep.pixelsWide > 0 { img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh) }  // 100% = real pixels
            let canvas = CanvasView(image: img)
            canvas.onCommit = { [weak store] s in MainActor.assumeIsolated { store?.add(path, s) } }
            sv.documentView = canvas; sv.imgSize = img.size
        }
        return sv
    }

    func updateNSView(_ sv: FitScrollView, context: Context) {
        guard let c = sv.documentView as? CanvasView else { return }
        c.shapes = store.shapes(path)
        c.colorHex = store.color
        if c.tool != store.tool { c.tool = store.tool }
    }
}

/// Tools above the image: move, pen, rectangle, arrow, text, colors, undo, redo, clear.
struct AnnotateBar: View {
    @ObservedObject var store: AnnotationStore
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $store.tool) {
                ForEach(Tool.allCases) { Image(systemName: $0.symbol).help($0.help).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
            HStack(spacing: 5) {
                ForEach(AnnotationPalette.colors, id: \.self) { c in
                    Circle().fill(Color(nsColor: NSColor(hex: c))).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: store.color == c ? 2.5 : 0).padding(-3))
                        .onTapGesture { store.color = c }
                }
            }
            Button { store.undo(path) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo(path)).keyboardShortcut("z", modifiers: .command).help("Undo")
            Button { store.redo(path) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo(path)).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
            Button("Clear") { store.clear(path) }.disabled(!store.has(path)).controlSize(.small)
            Spacer()
            if store.has(path) {
                Label("Marked up: the annotated image is sent with your answer", systemImage: "pencil.and.outline")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 10).padding(.vertical, 6).background(.bar)
    }
}
