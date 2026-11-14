import Foundation

public struct HistoryEntry: Codable, Sendable {
    public var job: Job
    public var picks: Picks?
    public var answer: String?
    public var status: String?       // sent, copied, cancelled, or nil while open

    public init(job: Job, picks: Picks? = nil, answer: String? = nil, status: String? = nil) {
        self.job = job; self.picks = picks; self.answer = answer; self.status = status
    }
}

/// Recent popups, one JSON file each, so a closed popup can be opened again.
public struct HistoryStore {
    public let dir: String
    public var maxEntries = 30
    public var maxAgeDays = 14

    public init(dir: String = Paths.history) { self.dir = dir }

    func file(for job: Job) -> String {
        let safe = job.id.replacingOccurrences(of: "/", with: "_")
        return (dir as NSString).appendingPathComponent("\(Int(job.createdAt.timeIntervalSince1970))-\(safe).json")
    }

    public func save(_ e: HistoryEntry) {
        guard let data = try? Coding.encoder().encode(e) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: file(for: e.job)), options: .atomic)
        prune()
    }

    /// Newest first.
    public func all() -> [HistoryEntry] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        let entries: [HistoryEntry] = names.compactMap {
            guard let d = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent($0)) else { return nil }
            return try? Coding.decoder().decode(HistoryEntry.self, from: d)
        }
        return entries.sorted { $0.job.createdAt > $1.job.createdAt }
    }

    /// nil ref = the newest. Otherwise the newest entry whose job id matches.
    public func find(_ ref: String?) -> HistoryEntry? {
        let list = all()
        guard let ref, !ref.isEmpty else { return list.first }
        return list.first { $0.job.id == ref }
    }

    public func summaries() -> [JobSummary] {
        all().map { JobSummary(id: $0.job.id, title: $0.job.heading, mode: $0.job.mode,
                               count: $0.job.sections.reduce(0) { $0 + $1.items.count }, date: $0.job.createdAt) }
    }

    public func clear() {
        for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where n.hasSuffix(".json") {
            try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(n))
        }
    }

    func prune() {
        let list = all()
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
        for (i, e) in list.enumerated() where i >= maxEntries || e.job.createdAt < cutoff {
            try? FileManager.default.removeItem(atPath: file(for: e.job))
        }
    }
}
