import Foundation
import ImageIO
import CoreGraphics

/// A rectangle inside an image, as fractions (0...1) of its width and height. Origin is the top-left.
public struct CropRect: Codable, Hashable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    /// The pixel rectangle for an image of this size (rounded to whole pixels, never outside the image).
    public func pixels(width: Int, height: Int) -> CGRect {
        let x0 = max(0, Int((x * Double(width)).rounded())), y0 = max(0, Int((y * Double(height)).rounded()))
        let x1 = min(width, Int(((x + w) * Double(width)).rounded())), y1 = min(height, Int(((y + h) * Double(height)).rounded()))
        return CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
    }
}

/// How a question was made from one image sheet: rows and columns, or found automatically.
public struct SliceSpec: Codable, Hashable, Sendable {
    public var path: String
    public var rows: Int
    public var cols: Int
    public var auto: Bool
    public init(path: String, rows: Int, cols: Int, auto: Bool) { self.path = path; self.rows = rows; self.cols = cols; self.auto = auto }
}

/// Cuts one image (a logo sheet, a contact sheet) into cells that can be picked like separate options.
public enum GridSlicer {
    /// "4x3" means 4 columns and 3 rows.
    public static func parse(_ s: String) -> (cols: Int, rows: Int)? {
        let p = s.lowercased().split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, p[0] >= 1, p[1] >= 1, p[0] * p[1] >= 2, p[0] * p[1] <= 78 else { return nil }
        return (p[0], p[1])
    }

    /// The options for the cells of one sheet (keys A, B, C...). Every cell points into the same file.
    public static func cellItems(path: String, rects: [CropRect], cols: Int) -> [Item] {
        zip(rects, JobBuilder.keys(rects.count)).enumerated().map { (n, pair) in
            Item(key: pair.1, kind: .image, path: path, crop: pair.0, cellRow: n / cols + 1, cellCol: n % cols + 1)
        }
    }

    /// Equal cells, row by row.
    public static func even(rows: Int, cols: Int) -> [CropRect] {
        (0..<rows).flatMap { r in
            (0..<cols).map { c in CropRect(x: Double(c) / Double(cols), y: Double(r) / Double(rows), w: 1 / Double(cols), h: 1 / Double(rows)) }
        }
    }

    /// Finds the grid from the empty space between the marks. Works for sheets on a plain background.
    /// Small marks such as cell numbers are ignored. Returns nil when no grid of at least two cells is found.
    public static func detect(path: String) -> (cols: Int, rows: Int, cells: [CropRect])? {
        guard let (px, w, h) = load(path: path, maxSide: 800) else { return nil }
        let bg = background(px, w, h)
        // ink = pixel that differs from the background
        var colInk = [Int](repeating: 0, count: w), rowInk = [Int](repeating: 0, count: h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let d = max(abs(Int(px[i]) - bg.0), abs(Int(px[i + 1]) - bg.1), abs(Int(px[i + 2]) - bg.2))
                if d > 28 { colInk[x] += 1; rowInk[y] += 1 }
            }
        }
        guard let xs = bounds(colInk, length: h, size: w), let ys = bounds(rowInk, length: w, size: h) else { return nil }
        let cols = xs.count - 1, rows = ys.count - 1
        guard cols * rows >= 2, cols * rows <= 78 else { return nil }
        var cells: [CropRect] = []
        for r in 0..<rows { for c in 0..<cols {
            cells.append(CropRect(x: xs[c], y: ys[r], w: xs[c + 1] - xs[c], h: ys[r + 1] - ys[r]))
        } }
        return (cols, rows, cells)
    }

    /// Boundaries (0...1) between the groups of ink along one axis. The count is groups + 1.
    static func bounds(_ ink: [Int], length: Int, size: Int) -> [Double]? {
        let emptyLimit = max(1, Int(Double(length) * 0.004))
        let minGap = max(2, Int(Double(size) * 0.012))
        // runs of non-empty lines, joined when the gap between them is small
        var runs: [(start: Int, end: Int)] = []
        var i = 0
        while i < size {
            if ink[i] > emptyLimit {
                var j = i
                while j + 1 < size, ink[j + 1] > emptyLimit { j += 1 }
                runs.append((i, j)); i = j + 1
            } else { i += 1 }
        }
        var merged: [(start: Int, end: Int)] = []
        for r in runs {
            if let last = merged.last, r.start - last.end - 1 < minGap { merged[merged.count - 1].end = r.end } else { merged.append(r) }
        }
        // small groups (cell numbers, captions, noise) are not cells
        let mass = merged.map { r in (r.start...r.end).reduce(0) { $0 + ink[$1] } }
        guard let biggest = mass.max(), biggest > 0 else { return nil }
        let kept = merged.enumerated().filter { Double(mass[$0.offset]) >= Double(biggest) * 0.12 }.map { $0.element }
        guard kept.count >= 1 else { return nil }
        var b: [Double] = [0]
        for k in 1..<max(1, kept.count) {
            let mid = Double(kept[k - 1].end + 1 + kept[k].start) / 2
            b.append(mid / Double(size))
        }
        b.append(1)
        return b
    }

    static func background(_ px: [UInt8], _ w: Int, _ h: Int) -> (Int, Int, Int) {
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        let band = max(1, min(w, h) / 50)
        func add(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            let key = Int(px[i] >> 3) << 10 | Int(px[i + 1] >> 3) << 5 | Int(px[i + 2] >> 3)
            var e = counts[key] ?? (0, 0, 0, 0)
            e.n += 1; e.r += Int(px[i]); e.g += Int(px[i + 1]); e.b += Int(px[i + 2])
            counts[key] = e
        }
        for y in 0..<h { for x in 0..<w where x < band || x >= w - band || y < band || y >= h - band { add(x, y) } }
        let best = counts.values.max { $0.n < $1.n } ?? (1, 255, 255, 255)
        return (best.r / best.n, best.g / best.n, best.b / best.n)
    }

    /// RGBA pixels of the image, scaled so the longer side is at most `maxSide`.
    static func load(path: String, maxSide: Int) -> ([UInt8], Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSide]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8, let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))   // transparent areas count as white
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (buf, w, h) : nil
    }
}
