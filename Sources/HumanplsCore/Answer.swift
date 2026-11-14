import Foundation

/// What the person chose. The app edits this; `AnswerText` turns it into the text for the chat.
public struct Picks: Codable, Sendable {
    public var chosen: [String: Set<String>] = [:]       // section id -> option keys
    public var retry: Set<String> = []                    // section ids with "none of these"
    public var sectionNotes: [String: String] = [:]
    public var annotated: [String: [String: String]] = [:]    // question id -> option key -> annotated PNG path
    public var feedback: String = ""

    public init() {}

    public init(job: Job) {
        for s in job.sections {
            chosen[s.id] = Set(s.items.filter { $0.selected }.map { $0.key })
        }
    }
}

public enum AnswerText {
    /// One line per question. A single question uses the short form:
    ///   [narrator-voice] picked: B "older, raspy" (take2.wav)
    public static func make(job: Job, picks: Picks) -> String {
        let many = job.sections.count > 1
        var lines: [String] = []
        for s in job.sections {
            let body = describe(section: s, picks: picks)
            if many {
                lines.append("\(s.heading): \(body)")
            } else {
                lines.append("[\(job.id)] \(body.hasPrefix("none of these") || body.hasPrefix("no pick") ? body : "picked: " + body)")
            }
        }
        if many { lines.insert("[\(job.id)]", at: 0) }
        let fb = picks.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fb.isEmpty { lines.append("feedback: \(fb)") }
        return lines.joined(separator: "\n")
    }

    static func describe(section s: Question, picks: Picks) -> String {
        var out: String
        if picks.retry.contains(s.id) {
            out = "none of these: try again"
        } else {
            let keys = picks.chosen[s.id] ?? []
            let items = s.items.filter { keys.contains($0.key) }
            if items.isEmpty {
                out = "no pick"
            } else {
                out = items.map(itemText).joined(separator: "; ")
            }
        }
        if let n = picks.sectionNotes[s.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            out += " | note: \(n)"
        }
        // annotated images are part of the answer even when the option was not picked
        let marked = s.items.compactMap { i in picks.annotated[s.id]?[i.key].map { (i, $0) } }
        if !marked.isEmpty {
            out += " | annotated: " + marked.map { "\($0.key)\($0.answerName.map { " \"\($0)\"" } ?? "") \($1)" }.joined(separator: "; ")
        }
        return out
    }

    static func itemText(_ i: Item) -> String {
        var t = i.key
        if let n = i.answerName { t += " \"\(n)\"" }
        if let f = i.fileName, f != i.answerName { t += " (\(f))" }
        return t
    }
}
