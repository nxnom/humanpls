import Foundation

/// What the person chose. The app edits this; `AnswerText` turns it into the text for the chat.
public struct Picks: Codable, Sendable {
    public var chosen: [String: Set<String>] = [:]       // section id -> option keys
    public var retry: Set<String> = []                    // section ids with "none of these"
    public var sectionNotes: [String: String] = [:]
    public var annotated: [String: [String: String]] = [:]    // question id -> option key -> annotated PNG path
    public var crops: [String: [String: String]] = [:]        // question id -> option key -> exported crop PNG path
    public var feedback: String = ""
    public var sectionFiles: [String: [String]] = [:]    // question id -> files the person attached to the note
    public var feedbackFiles: [String] = []               // files the person attached to the feedback

    public init() {}

    /// Every key is optional, so an older history file (written before a field existed) still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chosen = try c.decodeIfPresent([String: Set<String>].self, forKey: .chosen) ?? [:]
        retry = try c.decodeIfPresent(Set<String>.self, forKey: .retry) ?? []
        sectionNotes = try c.decodeIfPresent([String: String].self, forKey: .sectionNotes) ?? [:]
        annotated = try c.decodeIfPresent([String: [String: String]].self, forKey: .annotated) ?? [:]
        crops = try c.decodeIfPresent([String: [String: String]].self, forKey: .crops) ?? [:]
        feedback = try c.decodeIfPresent(String.self, forKey: .feedback) ?? ""
        sectionFiles = try c.decodeIfPresent([String: [String]].self, forKey: .sectionFiles) ?? [:]
        feedbackFiles = try c.decodeIfPresent([String].self, forKey: .feedbackFiles) ?? []
    }

    public init(job: Job) {
        for s in job.sections {
            chosen[s.id] = Set(s.items.filter { $0.selected }.map { $0.key })
        }
    }
}

public enum AnswerText {
    /// A path with spaces is put in quotes so an agent can read it as one path.
    public static func quoted(_ path: String) -> String {
        path.contains(where: { $0.isWhitespace }) ? "\"\(path)\"" : path
    }

    /// Files the person attached: `attached: /a/ref.png; "/b/my style.png"`. nil when there are none.
    public static func attached(_ files: [String]) -> String? {
        files.isEmpty ? nil : "attached: " + files.map(quoted).joined(separator: "; ")
    }

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
        if let a = attached(picks.feedbackFiles) { lines.append(fb.isEmpty ? "feedback: \(a)" : a) }
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
        if let a = attached(picks.sectionFiles[s.id] ?? []) { out += " | \(a)" }
        // the picked cells of an image sheet, cut out as files
        let cropped = items(of: s, picks).compactMap { i in picks.crops[s.id]?[i.key].map { (i, $0) } }
        if !cropped.isEmpty { out += " | crops: " + cropped.map { "\($0.key) \(quoted($1))" }.joined(separator: "; ") }
        // annotated images are part of the answer even when the option was not picked
        let marked = s.items.compactMap { i in picks.annotated[s.id]?[i.key].map { (i, $0) } }
        if !marked.isEmpty {
            out += " | annotated: " + marked.map { "\($0.key)\($0.answerName.map { " \"\($0)\"" } ?? "") \(quoted($1))" }.joined(separator: "; ")
        }
        return out
    }

    static func items(of s: Question, _ picks: Picks) -> [Item] {
        let keys = picks.chosen[s.id] ?? []
        return s.items.filter { keys.contains($0.key) }
    }

    static func itemText(_ i: Item) -> String {
        var t = i.key
        if let n = i.answerName { t += " \"\(n)\"" }
        if let r = i.cellRow, let c = i.cellCol, let f = i.fileName { t += " (\(f) row \(r) col \(c))" }
        else if let f = i.fileName, f != i.answerName { t += " (\(f))" }
        return t
    }
}
