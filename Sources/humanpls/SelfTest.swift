import AppKit
import HumanplsCore

/// `humanpls selftest`: draws shapes on an image, exports a PNG and reads the pixels back. No window.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ name: String, _ ok: Bool) { if !ok { failures.append(name) }; print(ok ? "ok   \(name)" : "FAIL \(name)") }

        // a white 200x120 image
        let size = NSSize(width: 200, height: 120)
        let img = NSImage(size: size)
        // a bitmap of exactly 200x120 pixels (lockFocus would make a 2x retina image)
        let base = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        if let gc = NSGraphicsContext(bitmapImageRep: base) {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: 120).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        img.addRepresentation(base)

        var set = AnnotationSet()
        set.add(Drawing(kind: .rect, points: [Pt(20, 20), Pt(100, 70)], color: "#FF0000"))          // red box, top-left area
        set.add(Drawing(kind: .pen, points: [Pt(120, 100), Pt(180, 100), Pt(180, 110)], color: "#0000FF"))   // blue line near the bottom right
        set.add(Drawing(kind: .arrow, points: [Pt(150, 20), Pt(190, 20)], color: "#00FF00"))        // green arrow, top right
        guard let data = AnnotationRenderer.png(image: img, shapes: set.shapes), let rep = NSBitmapImageRep(data: data) else {
            print("FAIL export png"); return 1
        }
        check("exported PNG has the image size", rep.pixelsWide == 200 && rep.pixelsHigh == 120)

        func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            // raw stored values, no color conversion
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            (rep.colorAt(x: x, y: y) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        func near(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Bool {
            abs(a.0 - b.0) < 0.15 && abs(a.1 - b.1) < 0.15 && abs(a.2 - b.2) < 0.15
        }
        check("background stays white", near(px(150, 60), (1, 1, 1)))
        check("rectangle edge is red, y counted from the top", near(px(60, 20), (1, 0, 0)))
        check("inside the rectangle stays white", near(px(60, 45), (1, 1, 1)))
        check("pen line is blue", near(px(150, 100), (0, 0, 1)))
        check("arrow is green", near(px(165, 20), (0, 1, 0)))
        check("below the rectangle is not red (no vertical flip)", near(px(60, 100), (1, 1, 1)))

        // export through the store into a temp folder
        let tmp = NSTemporaryDirectory() + "humanpls-selftest-\(getpid())"
        setenv("HUMANPLS_HOME", tmp, 1)
        let src = tmp + "/src.png"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        if let png = base.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: src)) }
        let srcBefore = try? Data(contentsOf: URL(fileURLWithPath: src))
        let store = AnnotationStore()
        store.add(src, Drawing(kind: .rect, points: [Pt(5, 5), Pt(50, 50)]))
        let out = store.export(src)
        check("store writes the annotated copy into the app folder, not next to the source",
              out != nil && out!.hasPrefix(tmp + "/annotations/") && FileManager.default.fileExists(atPath: out!))
        check("the source file is not changed", (try? Data(contentsOf: URL(fileURLWithPath: src))) == srcBefore)
        let profile = out.flatMap { ImageMeta.read(path: $0).first { $0.key == "Profile" }?.value }
        print("  exported profile:", profile ?? "(none)")
        check("exported PNG is tagged sRGB or untagged (other apps show the right colors)", profile == nil || profile!.contains("sRGB"))
        check("an image without drawings exports nothing", store.export(tmp + "/other.png") == nil)
        try? FileManager.default.removeItem(atPath: tmp)

        print(failures.isEmpty ? "selftest passed" : "selftest FAILED: \(failures)")
        return failures.isEmpty ? 0 : 1
    }
}
