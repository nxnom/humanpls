import Foundation

public struct JobError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}

public enum Kinds {
    static let image: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]
    static let audio: Set<String> = ["wav", "mp3", "m4a", "aiff", "aif", "aac", "flac", "ogg", "caf"]
    static let markdown: Set<String> = ["md", "markdown"]
    static let html: Set<String> = ["html", "htm"]
    static let text: Set<String> = ["txt", "log", "csv"]
    static let code: [String: String] = [
        "swift": "swift", "py": "python", "js": "javascript", "ts": "typescript", "tsx": "typescript", "jsx": "javascript",
        "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "ini", "sh": "bash", "zsh": "bash", "bash": "bash",
        "rb": "ruby", "go": "go", "rs": "rust", "java": "java", "kt": "kotlin", "c": "c", "h": "c", "cpp": "cpp",
        "hpp": "cpp", "cs": "csharp", "css": "css", "xml": "xml", "sql": "sql", "php": "php", "lua": "lua", "diff": "diff",
    ]

    /// Known kinds only (by extension). nil = not one of the special types.
    public static func kind(ofPath path: String) -> (ItemKind, String?)? {
        let ext = (path as NSString).pathExtension.lowercased()
        if image.contains(ext) { return (.image, nil) }
        if video.contains(ext) { return (.video, nil) }
        if audio.contains(ext) { return (.audio, nil) }
        if markdown.contains(ext) { return (.markdown, nil) }
        if html.contains(ext) { return (.html, nil) }
        if ext == "pdf" { return (.pdf, nil) }
        if text.contains(ext) { return (.text, nil) }
        if let lang = code[ext] { return (.code, lang) }
        return nil
    }

    /// Any existing file gets a kind. Unknown extensions: text if the start of the file is UTF-8 text, else a generic file.
    public static func detect(path: String) -> (ItemKind, String?) {
        if let k = kind(ofPath: path) { return k }
        if let h = FileHandle(forReadingAtPath: path) {
            defer { try? h.close() }
            let head = h.readData(ofLength: 4096)
            if !head.isEmpty, !head.contains(0), String(data: head, encoding: .utf8) != nil { return (.text, nil) }
            if head.isEmpty { return (.text, nil) }
        }
        return (.file, nil)
    }
}

/// Turns CLI arguments or an items JSON file into a `Job`.
public struct JobBuilder {
    public var cwd: String
    public init(cwd: String = FileManager.default.currentDirectoryPath) { self.cwd = cwd }

    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    public static func keys(_ n: Int) -> [String] {
        (0..<n).map { i in
            i < 26 ? String(letters[i]) : String(letters[i / 26 - 1]) + String(letters[i % 26])
        }
    }

    func resolve(_ p: String, base: String? = nil) -> String {
        let expanded = (p as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return ((base ?? cwd) as NSString).appendingPathComponent(expanded)
    }

    // MARK: options

    /// One option from the command line: "file::label", "text:Aung", "text:Aung::note". A leading * = recommended.
    func item(fromArg raw: String, key: String) throws -> Item {
        var s = raw
        let rec = s.hasPrefix("*")
        if rec { s.removeFirst() }
        if s.hasPrefix("text:") {
            let body = String(s.dropFirst(5))
            let parts = body.components(separatedBy: "::")
            return textItem(key: key, text: parts[0], note: parts.count > 1 ? parts[1] : nil, recommended: rec)
        }
        let parts = s.components(separatedBy: "::")
        return try fileItem(key: key, file: parts[0], label: parts.count > 1 ? parts[1] : nil, note: nil, recommended: rec, base: nil)
    }

    func textItem(key: String, text: String, note: String?, recommended: Bool) -> Item {
        let short = text.count <= 80 && !text.contains("\n")
        return Item(key: key, kind: short ? .chip : .text, note: note, text: text, recommended: recommended)
    }

    func fileItem(key: String, file: String, label: String?, note: String?, recommended: Bool, base: String?) throws -> Item {
        let p = resolve(file, base: base)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue else {
            throw JobError("option \(key): \(p) is not a file")
        }
        let (kind, lang) = Kinds.detect(path: p)
        return Item(key: key, kind: kind, label: label?.isEmpty == true ? nil : label, note: note, path: p, language: lang, recommended: recommended)
    }

    /// One option from JSON: {file|html|text|markdown|code|url, label, note, recommended, selected, language}
    func item(fromJSON d: [String: Any], key: String, base: String) throws -> Item {
        let label = d["label"] as? String
        let note = d["note"] as? String
        let rec = d["recommended"] as? Bool ?? false
        var it: Item
        if let f = d["file"] as? String {
            it = try fileItem(key: key, file: f, label: label, note: note, recommended: rec, base: base)
        } else if let h = d["html"] as? String {
            it = Item(key: key, kind: .html, label: label, note: note, text: h, recommended: rec)
        } else if let m = d["markdown"] as? String {
            it = Item(key: key, kind: .markdown, label: label, note: note, text: m, recommended: rec)
        } else if let c = d["code"] as? String {
            it = Item(key: key, kind: .code, label: label, note: note, text: c, language: d["language"] as? String, recommended: rec)
        } else if let t = d["text"] as? String {
            it = textItem(key: key, text: t, note: note, recommended: rec)
            it.label = label
        } else if let u = d["url"] as? String {
            it = Item(key: key, kind: .url, label: label ?? u, note: note, url: u, recommended: rec)
        } else {
            throw JobError("option \(key): needs file, html, text, markdown, code or url")
        }
        if let s = d["selected"] as? Bool { it.selected = s }
        return it
    }

    // MARK: sections

    func section(id: String, title: String?, question: String?, multi: Bool, items: [Item],
                 recommend: [String], defaults: [String]?, preselect: Bool, explicitSelected: Set<String>) throws -> Question {
        guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$", options: .regularExpression) != nil else {
            throw JobError("question id \(id): use letters, digits, . _ -")
        }
        guard !items.isEmpty else { throw JobError("question \(id) has no options") }
        guard items.count <= 78 else { throw JobError("question \(id): too many options (\(items.count)); split it") }
        let known = Set(items.map { $0.key })
        for k in recommend + (defaults ?? []) where !known.contains(k) {
            throw JobError("question \(id): no option \(k) to recommend or pre-pick")
        }
        var out = items
        for i in out.indices {
            if recommend.contains(out[i].key) { out[i].recommended = true }
            if explicitSelected.contains(out[i].key) { continue }   // JSON said selected
            if let d = defaults { out[i].selected = d.contains(out[i].key) }
            else { out[i].selected = preselect && out[i].recommended }
        }
        if !multi {
            var seen = false
            for i in out.indices where out[i].selected { if seen { out[i].selected = false } else { seen = true } }
        }
        return Question(id: id, title: title, question: question, multi: multi, items: out)
    }

    static func slug(_ s: String, fallback: String) -> String {
        let r = s.lowercased().replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return r.isEmpty ? fallback : r
    }

    // MARK: options that repeat the built-in "None of these"

    /// Every question already has a "None of these: make new options" choice and a note field.
    /// Agents that do not know this add their own. This finds them, so the command can say so.
    public static func repeatsBuiltInNone(_ i: Item) -> Bool {
        let t = (i.answerName ?? i.text ?? "").lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if t.hasPrefix("none of") || t.hasPrefix("neither of") { return true }
        return ["none", "neither", "try again", "retry", "regenerate", "make new options", "new options", "generate more", "more options"].contains(t)
    }

    /// One warning line per option that repeats the built-in choice. Empty when the job is fine.
    public static func warnings(_ job: Job) -> [String] {
        guard job.mode == .pick else { return [] }
        return job.sections.flatMap { q in
            q.items.filter(repeatsBuiltInNone).map { i in
                "option \(i.key) \"\(i.answerName ?? i.text ?? "")\"\(job.sections.count > 1 ? " in \(q.heading)" : "") repeats a built-in choice: "
                + "every question already has \"None of these: make new options\" (the answer says `none of these: try again`). Leave this option out next time."
            }
        }
    }

    // MARK: pick

    public struct PickArgs {
        public var id = ""
        public var title: String?
        public var question: String?
        public var multi = false
        public var recommend: [String] = []
        public var defaults: [String]?
        public var noPreselect = false
        public var optional = false              // the questions may be sent without an answer
        public var itemsFile: String?
        public var slice: String?                 // "auto" or "4x3" (columns x rows): cut one image sheet into cells
        public var positional: [String] = []
        public var sections: [[String]] = []     // each: [TITLE, OPTION...]
        public init() {}
    }

    public func pick(_ a: PickArgs) throws -> Job {
        guard a.id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$", options: .regularExpression) != nil else {
            throw JobError("--id must be letters, digits, . _ - (for example narrator-voice)")
        }
        var sections: [Question] = []
        let rec = a.recommend.map { $0.uppercased() }
        let def = a.defaults?.map { $0.uppercased() }

        if let spec = a.slice {
            guard a.positional.count == 1, a.sections.isEmpty, a.itemsFile == nil else {
                throw JobError("--slice needs exactly one image (the sheet) and no --section or --items")
            }
            let file = a.positional[0].components(separatedBy: "::")[0].replacingOccurrences(of: "*", with: "", options: .anchored)
            sections.append(try slicedQuestion(id: a.id, title: nil, question: nil, multi: a.multi, file: resolve(file), spec: spec,
                                               recommend: rec, defaults: def, preselect: !a.noPreselect))
        } else if !a.positional.isEmpty {
            let ks = Self.keys(a.positional.count)
            let items = try zip(a.positional, ks).map { try item(fromArg: $0, key: $1) }
            sections.append(try section(id: a.id, title: nil, question: nil, multi: a.multi, items: items,
                                        recommend: rec, defaults: def, preselect: !a.noPreselect, explicitSelected: []))
        }
        for (i, sec) in a.sections.enumerated() {
            guard let title = sec.first, sec.count > 1 else { throw JobError("--section needs a title and at least one option") }
            let opts = Array(sec.dropFirst())
            let items = try zip(opts, Self.keys(opts.count)).map { try item(fromArg: $0, key: $1) }
            sections.append(try section(id: Self.slug(title, fallback: "q\(i + 1)"), title: title, question: nil, multi: a.multi, items: items,
                                        recommend: [], defaults: nil, preselect: !a.noPreselect, explicitSelected: []))
        }
        if let f = a.itemsFile {
            sections += try jsonSections(file: f, args: a, rec: rec, def: def)
        }
        guard !sections.isEmpty else { throw JobError("give options: file paths, --section TITLE OPTION..., or --items file.json") }
        let ids = sections.map { $0.id }
        guard Set(ids).count == ids.count else { throw JobError("question ids must be unique: \(ids)") }
        if a.optional { for i in sections.indices where sections[i].optional == nil { sections[i].optional = true } }
        return Job(id: a.id, mode: .pick, title: a.title, question: a.question, sections: sections)
    }

    /// One image sheet cut into cells. Every cell is an image option that shows only its part of the sheet.
    func slicedQuestion(id: String, title: String?, question: String?, multi: Bool, file: String, spec: String,
                        recommend: [String], defaults: [String]?, preselect: Bool) throws -> Question {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file, isDirectory: &isDir), !isDir.boolValue else { throw JobError("\(file) is not a file") }
        guard Kinds.kind(ofPath: file)?.0 == .image else { throw JobError("--slice needs an image: \((file as NSString).lastPathComponent)") }
        let rects: [CropRect], cols: Int, rows: Int, auto: Bool
        if spec.lowercased() == "auto" {
            guard let found = GridSlicer.detect(path: file) else {
                throw JobError("could not find a grid in \((file as NSString).lastPathComponent): cells need empty space between them. Give the grid yourself, for example --slice 4x3 (columns x rows)")
            }
            (cols, rows, rects, auto) = (found.cols, found.rows, found.cells, true)
        } else {
            guard let g = GridSlicer.parse(spec) else { throw JobError("--slice must be auto or COLSxROWS, for example 4x3 (got \(spec))") }
            (cols, rows, rects, auto) = (g.cols, g.rows, GridSlicer.even(rows: g.rows, cols: g.cols), false)
        }
        let items = GridSlicer.cellItems(path: file, rects: rects, cols: cols)
        var q = try section(id: id, title: title, question: question, multi: multi, items: items,
                            recommend: recommend, defaults: defaults, preselect: preselect, explicitSelected: [])
        q.slice = SliceSpec(path: file, rows: rows, cols: cols, auto: auto)
        return q
    }

    func jsonSections(file: String, args a: PickArgs, rec: [String], def: [String]?) throws -> [Question] {
        let path = resolve(file)
        guard let data = FileManager.default.contents(atPath: path) else { throw JobError("\(path) is not a file") }
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data) } catch { throw JobError("\(path): invalid JSON: \(error.localizedDescription)") }
        let base = (path as NSString).deletingLastPathComponent

        func build(id: String, title: String?, question: String?, multi: Bool, raw: [Any], recommend: [String], defaults: [String]?, preselect: Bool) throws -> Question {
            var items: [Item] = []
            let ks = Self.keys(raw.count)
            var picked = Set<String>()
            for (r, k) in zip(raw, ks) {
                if let s = r as? String { items.append(try item(fromArg: s, key: k)); continue }
                guard let d = r as? [String: Any] else { throw JobError("option \(k) must be an object or a string") }
                let it = try item(fromJSON: d, key: k, base: base)
                if d["selected"] != nil { picked.insert(k) }
                if it.selected { picked.insert(k) }
                items.append(it)
            }
            return try section(id: id, title: title, question: question, multi: multi, items: items,
                               recommend: recommend, defaults: defaults, preselect: preselect, explicitSelected: picked)
        }
        func opt(_ s: [String: Any], _ q: Question) -> Question { var q = q; q.optional = s["optional"] as? Bool; return q }

        if let obj = any as? [String: Any], let secs = obj["sections"] as? [[String: Any]] {
            return try secs.enumerated().map { (i, s) in
                let title = s["title"] as? String
                let id = (s["id"] as? String) ?? Self.slug(title ?? "", fallback: "q\(i + 1)")
                let recS = (s["recommend"] as? String).map { [$0.uppercased()] } ?? (s["recommend"] as? [String])?.map { $0.uppercased() } ?? []
                var defS: [String]? = nil
                if let d = s["default"] as? String { defS = [d.uppercased()] } else if let d = s["default"] as? [String] { defS = d.map { $0.uppercased() } }
                if let spec = s["slice"] as? String {
                    guard let raw = s["items"] as? [Any], raw.count == 1,
                          let f = (raw[0] as? [String: Any])?["file"] as? String ?? (raw[0] as? String)?.components(separatedBy: "::")[0] else {
                        throw JobError("question \(id): slice needs exactly one item with a file (the sheet)")
                    }
                    return opt(s, try slicedQuestion(id: id, title: title, question: s["question"] as? String, multi: s["multi"] as? Bool ?? a.multi,
                                              file: resolve(f, base: base), spec: spec, recommend: recS, defaults: defS,
                                              preselect: s["preselect"] as? Bool ?? !a.noPreselect))
                }
                return opt(s, try build(id: id, title: title, question: s["question"] as? String, multi: s["multi"] as? Bool ?? a.multi,
                                 raw: s["items"] as? [Any] ?? [], recommend: recS, defaults: defS, preselect: s["preselect"] as? Bool ?? !a.noPreselect))
            }
        }
        let list: [Any]
        if let l = any as? [Any] { list = l } else if let o = any as? [String: Any], let l = o["items"] as? [Any] { list = l }
        else { throw JobError("\(path): expected a list of options, {\"items\": [...]} or {\"sections\": [...]}") }
        return [try build(id: a.id, title: nil, question: nil, multi: a.multi, raw: list, recommend: rec, defaults: def, preselect: !a.noPreselect)]
    }

    // MARK: show

    /// Files and folders to look at. Folders are expanded (not recursive), sorted by name.
    public func show(id: String?, title: String?, paths: [String], compare: Bool = false) throws -> Job {
        var files: [String] = []
        for p in paths {
            let r = resolve(p)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: r, isDirectory: &isDir) else { throw JobError("\(r) does not exist") }
            if isDir.boolValue {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: r)) ?? []
                files += names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { (r as NSString).appendingPathComponent($0) }
                    .filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &d) && !d.boolValue }
            } else {
                files.append(r)
            }
        }
        guard !files.isEmpty else { throw JobError("nothing to show: give files or a folder that has files") }
        let ks = Self.keys(files.count)
        let items: [Item] = zip(files, ks).map { f, k in
            let (kind, lang) = Kinds.detect(path: f)
            return Item(key: k, kind: kind, path: f, language: lang)
        }
        let jid = id ?? "show-\(Int(Date().timeIntervalSince1970))"
        if compare, items.filter({ $0.kind == .image }).count < 2 { throw JobError("--compare needs at least two images") }
        var job = Job(id: jid, mode: .show, title: title, sections: [Question(id: "files", title: "Files", multi: false, items: items)])
        if compare { job.compare = true }
        return job
    }
}
