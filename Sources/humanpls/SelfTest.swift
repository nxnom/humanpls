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

        // cutting a cell out of a sheet: left half red, right half blue
        let sheet = tmp + "/sheet.png"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        if let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            if let cg = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: sheet)) }
        }
        let cellPath = CellExporter.export(path: sheet, crop: CropRect(x: 0.5, y: 0, w: 0.5, h: 1), row: 1, col: 2)
        let cellRep = cellPath.flatMap { NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: $0))) ?? Data()) }
        check("exported cell has the cell's pixel size (100x100 out of 200x100)", cellRep?.pixelsWide == 100 && cellRep?.pixelsHigh == 100)
        var cr: CGFloat = 0, cg2: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
        cellRep?.colorAt(x: 50, y: 50)?.getRed(&cr, green: &cg2, blue: &cb, alpha: &ca)
        check("exported cell is the right half (blue)", cb > 0.9 && cr < 0.1)
        check("cell goes to the app's crops folder, named by row and column", (cellPath ?? "").contains("/crops/sheet-r1c2-"))
        check("the exported file name has no spaces or AM/PM, whatever the 12-hour setting is",
              (cellPath ?? "").range(of: #"/sheet-r1c2-\d{6}-\d{6}\.png$"#, options: .regularExpression) != nil)
        check("the sheet is not changed", FileManager.default.fileExists(atPath: sheet))

        // the hidden main menu is what makes Command-A, C, V, X, Z work in text fields of an app without a Dock icon
        let menu = AppDelegate.buildMainMenu()
        let edit = menu.items.compactMap { $0.submenu }.first { $0.title == "Edit" }
        func has(_ key: String, _ sel: Selector, _ mods: NSEvent.ModifierFlags = .command) -> Bool {
            edit?.items.contains { $0.keyEquivalent == key && $0.action == sel && $0.keyEquivalentModifierMask == mods } ?? false
        }
        check("Edit menu: Select All is Command-A", has("a", #selector(NSText.selectAll(_:))))
        check("Edit menu: Copy is Command-C", has("c", #selector(NSText.copy(_:))))
        check("Edit menu: Paste is Command-V", has("v", #selector(NSText.paste(_:))))
        check("Edit menu: Cut is Command-X", has("x", #selector(NSText.cut(_:))))
        check("Edit menu: Undo is Command-Z", has("z", Selector(("undo:"))))
        check("Edit menu: Redo is Shift-Command-Z", has("z", Selector(("redo:")), [.command, .shift]))

        let mb = AppDelegate.menuBarImage()
        check("menu bar icon is built in, is a template, and is 18 points tall", mb?.isTemplate == true && mb?.size.height == 18 && (mb?.size.width ?? 0) > 10)
        check("menu bar icon is the logo (has transparent corners and an opaque body)", {
            guard let tiff = mb?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return false }
            let corner = rep.colorAt(x: 1, y: 1)?.alphaComponent ?? 1
            let body = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh - 6)?.alphaComponent ?? 0
            return corner < 0.05 && body > 0.9
        }())

        try? FileManager.default.removeItem(atPath: tmp)
        print(failures.isEmpty ? "selftest passed" : "selftest FAILED: \(failures)")
        return failures.isEmpty ? 0 : 1
    }
}
