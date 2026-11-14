import Foundation

/// What an option is. The viewer picks the right native view from this.
public enum ItemKind: String, Codable, Sendable {
    case chip      // short text (a name, a title): shown as big text
    case text      // long plain text
    case markdown
    case code
    case image
    case video
    case audio
    case html
    case pdf
    case url
    case file      // anything else: shown with a Quick Look thumbnail, Open and Reveal
}

public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var key: String               // A, B, C ...
    public var kind: ItemKind
    public var label: String?
    public var note: String?
    public var path: String?             // absolute file path
    public var text: String?             // inline content (chip, text, markdown, code, html)
    public var language: String?         // for code
    public var url: String?
    public var recommended: Bool
    public var selected: Bool
    public var crop: CropRect?           // a cell of an image sheet: only this part of the image
    public var cellRow: Int?             // 1-based, for cells
    public var cellCol: Int?

    public var id: String { key }

    public init(key: String, kind: ItemKind, label: String? = nil, note: String? = nil, path: String? = nil,
                text: String? = nil, language: String? = nil, url: String? = nil,
                recommended: Bool = false, selected: Bool = false, crop: CropRect? = nil, cellRow: Int? = nil, cellCol: Int? = nil) {
        self.key = key; self.kind = kind; self.label = label; self.note = note; self.path = path
        self.text = text; self.language = language; self.url = url
        self.recommended = recommended; self.selected = selected
        self.crop = crop; self.cellRow = cellRow; self.cellCol = cellCol
    }

    public var fileName: String? { path.map { ($0 as NSString).lastPathComponent } }

    /// The name used in the answer: the label, else the short text, else nothing.
    public var answerName: String? {
        if let l = label, !l.isEmpty { return l }
        if kind == .chip, let t = text, !t.isEmpty { return t }
        return nil
    }
}

/// How the options of one question are laid out. The person can switch in the popup.
public enum QuestionLayout: String, Codable, Sendable, CaseIterable {
    case grid      // a card per option, as many per row as fit
    case detail    // a list on the left and a large preview of one option on the right
    case dense     // only big thumbnails, for many images or logos
}

public struct Question: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var question: String?
    public var multi: Bool
    public var items: [Item]
    public var slice: SliceSpec?         // set when the options are the cells of one image sheet
    public var layout: QuestionLayout?   // nil = automatic (dense for image sheets, else grid)

    public init(id: String, title: String? = nil, question: String? = nil, multi: Bool = false, items: [Item], slice: SliceSpec? = nil) {
        self.id = id; self.title = title; self.question = question; self.multi = multi; self.items = items; self.slice = slice
    }
    public var heading: String { title ?? id }

    /// The layout to start with when the caller did not choose one.
    public var effectiveLayout: QuestionLayout { layout ?? (slice != nil ? .dense : .grid) }
}

public enum JobMode: String, Codable, Sendable { case pick, show }

public struct Job: Codable, Identifiable, Sendable {
    public var id: String
    public var mode: JobMode
    public var title: String?
    public var question: String?
    public var sections: [Question]
    public var createdAt: Date
    public var compare: Bool?            // show: open with the first two images side by side

    public init(id: String, mode: JobMode, title: String? = nil, question: String? = nil, sections: [Question], createdAt: Date = Date()) {
        self.id = id; self.mode = mode; self.title = title; self.question = question
        self.sections = sections; self.createdAt = createdAt
    }
    public var heading: String { title ?? id }
}

/// Facts about the caller's terminal, so the app can send the answer back to the right chat.
public struct ClientEnv: Codable, Sendable {
    public var tmuxPane: String?
    public var tmuxSocket: String?
    public var tmuxPath: String?
    public var bundleId: String?
    public var cwd: String?
    public var autoAnswer: String?       // tests only: send, copy or cancel = answer at once, no window

    public init(tmuxPane: String? = nil, tmuxSocket: String? = nil, tmuxPath: String? = nil, bundleId: String? = nil,
                cwd: String? = nil, autoAnswer: String? = nil) {
        self.tmuxPane = tmuxPane; self.tmuxSocket = tmuxSocket; self.tmuxPath = tmuxPath
        self.bundleId = bundleId; self.cwd = cwd; self.autoAnswer = autoAnswer
    }
}

public struct JobSummary: Codable, Sendable {
    public var id: String
    public var title: String
    public var mode: JobMode
    public var count: Int
    public var date: Date
}

// MARK: protocol (one JSON object per line over a unix socket)

public struct Request: Codable, Sendable {
    public var cmd: String               // ping, pick, show, reopen, list, quit
    public var job: Job?
    public var env: ClientEnv?
    public var wait: Bool
    public var ref: String?              // reopen: a history id (nil = the last one)

    public init(cmd: String, job: Job? = nil, env: ClientEnv? = nil, wait: Bool = false, ref: String? = nil) {
        self.cmd = cmd; self.job = job; self.env = env; self.wait = wait; self.ref = ref
    }
}

public struct Response: Codable, Sendable {
    public var type: String              // pong, accepted, answer, jobs, error
    public var message: String?
    public var answer: String?
    public var status: String?           // sent, copied, cancelled
    public var jobs: [JobSummary]?

    public init(type: String, message: String? = nil, answer: String? = nil, status: String? = nil, jobs: [JobSummary]? = nil) {
        self.type = type; self.message = message; self.answer = answer; self.status = status; self.jobs = jobs
    }
}

public enum Coding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
