import AppKit
import HumanplsCore

/// Cuts one cell out of a sheet at full resolution and writes it as a PNG into the app's own folder.
/// The agent's sheet is never changed and nothing is written next to it.
@MainActor
enum CellExporter {
    static var dir: String {
        let d = (Paths.support as NSString).appendingPathComponent("crops")
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    static func png(path: String, crop: CropRect) -> Data? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let part = full.cropping(to: crop.pixels(width: full.width, height: full.height)) else { return nil }
        return NSBitmapImageRep(cgImage: part).representation(using: .png, properties: [:])
    }

    static func export(path: String, crop: CropRect, row: Int?, col: Int?) -> String? {
        guard let data = png(path: path, crop: crop) else { return nil }
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyMMdd-HHmmss"
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.replacingOccurrences(of: " ", with: "-")
        let cell = (row != nil && col != nil) ? "-r\(row!)c\(col!)" : ""
        let out = (dir as NSString).appendingPathComponent("\(stem)\(cell)-\(stamp.string(from: Date())).png")
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
