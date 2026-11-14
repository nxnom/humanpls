import Foundation
import ImageIO

public struct MetaField: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var section: String
    public var key: String
    public var value: String
    public init(section: String, key: String, value: String) { self.section = section; self.key = key; self.value = value }
}

/// Reads what is stored inside an image file: size, camera data and the text chunks that AI tools write
/// (Stable Diffusion "parameters", ComfyUI "prompt" and "workflow").
public enum ImageMeta {
    /// PNG text chunks (tEXt, zTXt, iTXt). Reads chunk by chunk and skips the pixel data, so big files are fine.
    public static func pngTextChunks(path: String) -> [(String, String)] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        guard let sig = try? h.read(upToCount: 8), sig == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return [] }
        var out: [(String, String)] = []
        while let head = try? h.read(upToCount: 8), head.count == 8 {
            let len = Int(head[0]) << 24 | Int(head[1]) << 16 | Int(head[2]) << 8 | Int(head[3])
            let type = String(decoding: head[4..<8], as: UTF8.self)
            if type == "IEND" { break }
            if ["tEXt", "zTXt", "iTXt"].contains(type) {
                guard len < 8_000_000, let body = try? h.read(upToCount: len), body.count == len else { break }
                if let kv = parse(type: type, body) { out.append(kv) }
                _ = try? h.read(upToCount: 4)   // crc
            } else {
                guard let pos = try? h.offset() else { break }
                try? h.seek(toOffset: pos + UInt64(len) + 4)
            }
        }
        return out
    }

    static func latin1(_ d: Data) -> String { String(data: d, encoding: .isoLatin1) ?? "" }

    static func inflate(_ d: Data) -> Data? {
        guard d.count > 2 else { return nil }
        return try? (d.dropFirst(2) as NSData).decompressed(using: .zlib) as Data   // strip the zlib header, rest is deflate
    }

    static func parse(type: String, _ body: Data) -> (String, String)? {
        guard let z = body.firstIndex(of: 0) else { return nil }
        let key = latin1(body[body.startIndex..<z])
        let rest = body[(z + 1)...]
        switch type {
        case "tEXt":
            return (key, String(data: rest, encoding: .utf8) ?? latin1(rest))
        case "zTXt":
            guard rest.count > 1, let raw = inflate(Data(rest.dropFirst())) else { return nil }
            return (key, String(data: raw, encoding: .utf8) ?? latin1(raw))
        default: // iTXt: flag, method, language\0, translated key\0, text
            guard rest.count > 2 else { return nil }
            let compressed = rest[rest.startIndex] == 1
            var i = rest.startIndex + 2
            for _ in 0..<2 {   // skip language tag and translated keyword
                guard let n = rest[i...].firstIndex(of: 0) else { return nil }
                i = n + 1
            }
            let text = Data(rest[i...])
            if compressed { guard let raw = inflate(text) else { return nil }; return (key, String(decoding: raw, as: UTF8.self)) }
            return (key, String(decoding: text, as: UTF8.self))
        }
    }

    public static func read(path: String) -> [MetaField] {
        var f: [MetaField] = []
        let url = URL(fileURLWithPath: path)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            f.append(MetaField(section: "File", key: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            if let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
                f.append(MetaField(section: "Image", key: "Size", value: "\(w) × \(h) px"))
            }
            if let d = p[kCGImagePropertyDPIWidth] as? Double, d > 0 { f.append(MetaField(section: "Image", key: "DPI", value: String(Int(d)))) }
            if let c = p[kCGImagePropertyColorModel] as? String { f.append(MetaField(section: "Image", key: "Color model", value: c)) }
            if let n = p[kCGImagePropertyProfileName] as? String { f.append(MetaField(section: "Image", key: "Profile", value: n)) }
            if let d = p[kCGImagePropertyDepth] as? Int { f.append(MetaField(section: "Image", key: "Bit depth", value: String(d))) }
            if let t = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                for (k, label) in [(kCGImagePropertyTIFFMake, "Make"), (kCGImagePropertyTIFFModel, "Model"), (kCGImagePropertyTIFFSoftware, "Software")] {
                    if let v = t[k] as? String { f.append(MetaField(section: "Camera", key: label, value: v)) }
                }
            }
            if let e = p[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let v = e[kCGImagePropertyExifDateTimeOriginal] as? String { f.append(MetaField(section: "Camera", key: "Taken", value: v)) }
                if let v = e[kCGImagePropertyExifLensModel] as? String { f.append(MetaField(section: "Camera", key: "Lens", value: v)) }
                if let v = e[kCGImagePropertyExifFNumber] as? Double { f.append(MetaField(section: "Camera", key: "Aperture", value: "f/\(v)")) }
                if let v = e[kCGImagePropertyExifExposureTime] as? Double, v > 0 { f.append(MetaField(section: "Camera", key: "Exposure", value: "1/\(Int((1 / v).rounded())) s")) }
                if let v = (e[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { f.append(MetaField(section: "Camera", key: "ISO", value: String(v))) }
                if let v = e[kCGImagePropertyExifUserComment] as? String, !v.isEmpty { f.append(MetaField(section: "Text in file", key: "UserComment", value: v)) }
            }
        }
        for (k, v) in pngTextChunks(path: path) where !v.isEmpty {
            f.append(MetaField(section: "Text in file", key: k, value: v))
        }
        return f
    }
}
