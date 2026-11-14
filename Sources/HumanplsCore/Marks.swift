import Foundation

/// A note at a moment in a video or audio file ("0:02.4 hand glitch").
public struct Mark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var time: Double
    public var note: String
    public init(id: UUID = UUID(), time: Double, note: String = "") { self.id = id; self.time = time; self.note = note }

    /// m:ss.t, for example 0:02.4
    public var timeText: String { Mark.format(time) }

    public static func format(_ t: Double) -> String {
        let t = max(0, t)
        let tenths = Int((t * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}

/// What the person added while looking at files in `show`: marks, annotated copies, and a message.
public struct ShowState: Codable, Sendable {
    public var marks: [String: [Mark]] = [:]          // item key -> marks, in time order
    public var annotated: [String: String] = [:]      // item key -> path of the annotated PNG
    public var message: String = ""
    public init() {}

    public mutating func addMark(_ key: String, time: Double) -> Mark {
        let m = Mark(time: time)
        var list = marks[key] ?? []
        list.append(m)
        list.sort { $0.time < $1.time }
        marks[key] = list
        return m
    }
    public mutating func removeMark(_ key: String, id: UUID) { marks[key]?.removeAll { $0.id == id } }
    public mutating func setNote(_ key: String, id: UUID, note: String) {
        guard let i = marks[key]?.firstIndex(where: { $0.id == id }) else { return }
        marks[key]?[i].note = note
    }
}

public enum ShowAnswer {
    /// [look]
    /// clip.mp4: @0:02.4 "hand glitch"; @0:03.1 "cut here"
    /// face.png: annotated /path/face-annotated.png
    /// message
    public static func make(job: Job, state: ShowState) -> String {
        var lines = ["[\(job.id)]"]
        for it in job.sections.flatMap({ $0.items }) {
            var parts: [String] = []
            for m in state.marks[it.key] ?? [] {
                let n = m.note.trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append(n.isEmpty ? "@\(m.timeText)" : "@\(m.timeText) \"\(n)\"")
            }
            if !parts.isEmpty { lines.append("\(it.fileName ?? it.key): " + parts.joined(separator: "; ")) }
            if let a = state.annotated[it.key] { lines.append("\(it.fileName ?? it.key): annotated \(AnswerText.quoted(a))") }
        }
        let m = state.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { lines.append(m) }
        return lines.joined(separator: "\n")
    }
}
