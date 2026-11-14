import Foundation

public struct Pt: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public enum DrawingKind: String, Codable, Sendable { case pen, rect, arrow, text }

/// One drawing on an image. Points are in image pixels, origin top-left, so zoom does not change them.
public struct Drawing: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: DrawingKind
    public var points: [Pt]          // pen: the path. rect and arrow: 2 points. text: 1 point.
    public var text: String?
    public var color: String         // #RRGGBB
    public init(id: UUID = UUID(), kind: DrawingKind, points: [Pt], text: String? = nil, color: String = "#FF3B30") {
        self.id = id; self.kind = kind; self.points = points; self.text = text; self.color = color
    }
}

/// The shapes on one image, with undo and redo.
public struct AnnotationSet: Codable, Sendable {
    public private(set) var shapes: [Drawing] = []
    private var undone: [Drawing] = []
    public init() {}

    public var isEmpty: Bool { shapes.isEmpty }
    public var canUndo: Bool { !shapes.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    public mutating func add(_ s: Drawing) {
        // a stray click is not a shape
        switch s.kind {
        case .pen: guard s.points.count >= 2 else { return }
        case .rect, .arrow:
            guard s.points.count == 2, hypot(s.points[1].x - s.points[0].x, s.points[1].y - s.points[0].y) >= 4 else { return }
        case .text: guard let t = s.text, !t.trimmingCharacters(in: .whitespaces).isEmpty, s.points.count == 1 else { return }
        }
        shapes.append(s)
        undone.removeAll()
    }
    public mutating func undo() { if let s = shapes.popLast() { undone.append(s) } }
    public mutating func redo() { if let s = undone.popLast() { shapes.append(s) } }
    public mutating func clear() { shapes.removeAll(); undone.removeAll() }
}

public enum AnnotationPalette {
    public static let colors = ["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF", "#000000"]
}
