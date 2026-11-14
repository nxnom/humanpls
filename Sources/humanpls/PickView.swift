import SwiftUI
import AppKit
import HumanplsCore

enum FinishAction { case send, copy, cancel }

// MARK: model

@MainActor
final class PickModel: ObservableObject {
    @Published var job: Job
    let waiting: Bool
    @Published var picks: Picks { didSet { override = nil } }
    @Published var override: String? = nil
    @Published var showPreview = false
    @Published var layouts: [String: QuestionLayout] = [:]     // what the person chose, per question
    @Published var focus: [String: String] = [:]               // the option shown large in the Detail layout, per question
    let store = AnnotationStore()
    var hovered: (question: String, key: String)?     // the option under the mouse, for Quick Look
    var onFinish: (FinishAction, String, Picks) -> Void = { _, _, _ in }

    init(job: Job, picks: Picks? = nil, waiting: Bool) {
        self.job = job; self.waiting = waiting
        self.picks = picks ?? Picks(job: job)
    }

    var computed: String { AnswerText.make(job: job, picks: picks) }
    var text: String { override ?? computed }

    // MARK: layouts

    func layout(_ q: Question) -> QuestionLayout { layouts[q.id] ?? q.effectiveLayout }
    func setLayout(_ q: Question, _ l: QuestionLayout) {
        layouts[q.id] = l
        if focus[q.id] == nil { focus[q.id] = chosen(q).sorted().first ?? q.items.first?.key }
    }
    func focusedItem(_ q: Question) -> Item? { q.items.first { $0.key == focus[q.id] } ?? q.items.first }
    func moveFocus(_ q: Question, _ d: Int) {
        guard !q.items.isEmpty else { return }
        let i = q.items.firstIndex { $0.key == focusedItem(q)?.key } ?? 0
        focus[q.id] = q.items[min(q.items.count - 1, max(0, i + d))].key
    }
    /// Everything picked so far, for the sidebar.
    var pickedItems: [(question: Question, item: Item)] {
        job.sections.flatMap { q in q.items.filter { chosen(q).contains($0.key) }.map { (q, $0) } }
    }

    func chosen(_ s: Question) -> Set<String> { picks.chosen[s.id] ?? [] }
    func isRetry(_ s: Question) -> Bool { picks.retry.contains(s.id) }

    func toggle(_ s: Question, _ key: String) {
        var cur = chosen(s)
        if s.multi { if cur.contains(key) { cur.remove(key) } else { cur.insert(key) } }
        else { cur = cur.contains(key) ? [] : [key] }
        picks.chosen[s.id] = cur
        if !cur.isEmpty { picks.retry.remove(s.id) }
    }
    func toggleRetry(_ s: Question) {
        if picks.retry.contains(s.id) { picks.retry.remove(s.id) }
        else { picks.retry.insert(s.id); picks.chosen[s.id] = [] }
    }
    func selectAll(_ s: Question, _ on: Bool) {
        picks.chosen[s.id] = on ? Set(s.items.map { $0.key }) : []
        if on { picks.retry.remove(s.id) }
    }
    func answered(_ s: Question) -> Bool { isRetry(s) || !chosen(s).isEmpty }
    var answeredCount: Int { job.sections.filter(answered).count }

    func sectionNote(_ s: Question) -> Binding<String> {
        Binding(get: { self.picks.sectionNotes[s.id] ?? "" }, set: { self.picks.sectionNotes[s.id] = $0 })
    }
    var feedback: Binding<String> { Binding(get: { self.picks.feedback }, set: { self.picks.feedback = $0 }) }

    /// Annotated images are written to PNG files when the answer is sent.
    func exportAnnotations() {
        for q in job.sections {
            for it in q.items {
                if it.kind == .image, let p = it.path, store.has(p), let out = store.export(p) {
                    picks.annotated[q.id, default: [:]][it.key] = out
                }
            }
        }
    }

    /// Quick Look the files of one question, starting at the option under the mouse (or the first picked one).
    func quickLook(_ q: Question) {
        let files = q.items.filter { $0.path != nil }
        guard !files.isEmpty else { NSSound.beep(); return }
        let start = (layout(q) == .detail ? focus[q.id] : nil) ?? (hovered?.question == q.id ? hovered?.key : nil) ?? chosen(q).sorted().first
        QuickLook.shared.show(files.map { $0.path! }, index: files.firstIndex { $0.key == start } ?? 0)
    }

    // MARK: image sheets cut into cells

    func question(_ id: String) -> Int? { job.sections.firstIndex { $0.id == id } }

    /// Cut the sheet again with another grid. Picks in that question start over.
    func reslice(_ id: String, cols: Int, rows: Int) {
        guard let qi = question(id), let spec = job.sections[qi].slice, cols >= 1, rows >= 1, cols * rows >= 2, cols * rows <= 78 else { return }
        apply(id, spec: SliceSpec(path: spec.path, rows: rows, cols: cols, auto: false), rects: GridSlicer.even(rows: rows, cols: cols))
    }

    func autoSlice(_ id: String) {
        guard let qi = question(id), let spec = job.sections[qi].slice else { return }
        let path = spec.path
        Task {
            let found = await Task.detached { GridSlicer.detect(path: path) }.value
            guard let f = found else { NSSound.beep(); return }
            apply(id, spec: SliceSpec(path: path, rows: f.rows, cols: f.cols, auto: true), rects: f.cells)
        }
    }

    private func apply(_ id: String, spec: SliceSpec, rects: [CropRect]) {
        guard let qi = question(id) else { return }
        job.sections[qi].items = GridSlicer.cellItems(path: spec.path, rects: rects, cols: spec.cols)
        job.sections[qi].slice = spec
        picks.chosen[id] = []; picks.retry.remove(id)
    }

    /// The picked cells are cut out of the sheet at full resolution and written to the app's own folder.
    func exportCrops() {
        for q in job.sections where q.slice != nil {
            for it in q.items where chosen(q).contains(it.key) {
                if picks.crops[q.id]?[it.key] != nil, FileManager.default.fileExists(atPath: picks.crops[q.id]![it.key]!) { continue }   // already cut out
                if let p = it.path, let c = it.crop, let out = CellExporter.export(path: p, crop: c, row: it.cellRow, col: it.cellCol) {
                    picks.crops[q.id, default: [:]][it.key] = out
                }
            }
        }
    }

    @Published var copied = false

    /// Put the answer on the clipboard. The popup stays open, so you can still change it or press Send.
    func copyAnswer() {
        exportAnnotations(); exportCrops()
        Sender.copy(text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.copied = false }
    }

    func finish(_ a: FinishAction) {
        QuickLook.shared.close()
        if a != .cancel { exportAnnotations(); exportCrops() }
        onFinish(a, text, picks)
    }
}

// MARK: style

struct KeyCap: View {
    let t: String
    var body: some View {
        Text(t).font(.system(.caption, design: .rounded).weight(.semibold)).frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 2).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The "select" click lives in a layer behind the content, so buttons inside a card get their own click first.
struct CardStyle: ViewModifier {
    let on: Bool
    let pick: () -> Void
    @State var hover = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12).fill(.background.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hover && !on ? 0.06 : 0)))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture(perform: pick)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.accentColor : Color.clear, lineWidth: 2.5).allowsHitTesting(false))
            .onHover { hover = $0 }
    }
}
extension View {
    func selectable(_ on: Bool, _ pick: @escaping () -> Void) -> some View { modifier(CardStyle(on: on, pick: pick)) }
}

// MARK: one option

struct OptionCard: View {
    let item: Item
    let section: Question
    @ObservedObject var model: PickModel
    @State var zoom = false
    @State var play = false
    @State var thumb: NSImage? = nil

    var on: Bool { model.chosen(section).contains(item.key) }
    func pick() { model.toggle(section, item.key) }
    var title: String { displayTitle(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            if let n = item.note, !n.isEmpty { Text(n).font(.caption).foregroundStyle(.secondary).allowsHitTesting(false) }
        }
        .padding(item.kind == .chip ? 16 : 12)
        .frame(maxWidth: .infinity, minHeight: item.kind == .chip ? 92 : 0, alignment: .topLeading)
        .selectable(on, pick)
        .modifier(DragOut(path: item.crop == nil ? item.path : nil))
        .onHover { if $0 { model.hovered = (section.id, item.key) } }
    }

    var header: some View {
        HStack(spacing: 8) {
            Group {
                if item.kind != .chip { KeyCap(t: item.key) }
                if item.kind == .chip {
                    Text(item.text ?? "").font(.system(size: 26, weight: .semibold, design: .rounded)).lineLimit(2)
                } else {
                    Text(title).font(.headline).lineLimit(1)
                }
                if item.recommended && item.kind != .chip { Badge() }
                Spacer()
            }.allowsHitTesting(false)
            Button(action: pick) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(on ? Color.accentColor : .secondary)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder var content: some View {
        if !fileExists(item.path) { MissingFile(path: item.path ?? "") } else { kindContent }
    }

    @ViewBuilder var kindContent: some View {
        switch item.kind {
        case .file:
            FileInfoView(path: item.path ?? "")
        case .chip:
            if item.recommended { Badge().allowsHitTesting(false) }
        case .text:
            ScrollView { Text(item.text ?? "").font(.system(.body, design: .serif)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture(perform: pick) }
                .frame(maxHeight: 220)
        case .markdown, .code:
            RichText(item: item).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))
        case .image where item.crop != nil:
            // a cell of a sheet: show the whole cell on white (logos sit on white), click the arrows to zoom
            Color.white.frame(maxWidth: .infinity).frame(height: 150)
                .overlay { if let thumb { Image(nsImage: thumb).resizable().scaledToFit().padding(6) } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                .allowsHitTesting(false)
                .overlay(alignment: .topTrailing) {
                    Button { zoom = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.white).padding(7)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }.buttonStyle(.plain).padding(8)
                }
                .task(id: item.crop) { if let p = item.path, let c = item.crop { thumb = await Cache.cell(p, c) } }
                .sheet(isPresented: $zoom) { CellSheet(path: item.path ?? "", crop: item.crop, title: "\(item.key)  \(title)") }
        case .image:
            // the whole image, never cropped: it fits inside the card and the card follows its shape
            ZStack {
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 240)
                } else {
                    Color.clear.frame(height: 150)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06))          // a quiet plate behind images with transparency or a different shape
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
                .overlay(alignment: .topTrailing) {
                    Button { zoom = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.white).padding(7)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }.buttonStyle(.plain).padding(8)
                }
                .task { if let p = item.path { thumb = await Cache.thumb(p) } }
                .sheet(isPresented: $zoom) { ImageSheet(path: item.path ?? "", title: "\(item.key)  \(title)", store: model.store) }
        case .video:
            Color.black.frame(maxWidth: .infinity).frame(height: 200)
                .overlay { if let thumb { Image(nsImage: thumb).resizable().scaledToFit() } }
                .overlay { Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.9)) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { play = true }
                .task { if let p = item.path { thumb = await Cache.poster(p) } }
                .sheet(isPresented: $play) { VideoSheet(path: item.path ?? "", title: "\(item.key)  \(title)") }
        case .audio:
            if let p = item.path { AudioPlayerRow(path: p) }
        case .html:
            WebRep(path: item.path, html: item.path == nil ? item.text : nil).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 8))
        case .pdf:
            if let p = item.path { PDFRep(path: p).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 8)) }
        case .url:
            if let u = item.url, let url = URL(string: u) { Link(u, destination: url).font(.callout) }
        }
    }
}

/// Drag the file out of the popup into Finder or another app. Only for options that are files.
struct DragOut: ViewModifier {
    let path: String?
    func body(content: Content) -> some View {
        if let path { content.onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() } }
        else { content }
    }
}

/// Zoom into one cell of a sheet. Only that part of the image is shown.
struct CellSheet: View {
    let path: String; let crop: CropRect?; let title: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.headline); Spacer()
                Text("Pinch to zoom · double-click: fit / 100%").font(.caption).foregroundStyle(.secondary)
                Button("Done") { dismiss() }.keyboardShortcut(.escape, modifiers: []) }.padding(10)
            Divider()
            ZoomImage(path: path, crop: crop)
        }.frame(minWidth: 700, minHeight: 520)
    }
}

struct ImageSheet: View {
    let path: String; let title: String
    @ObservedObject var store: AnnotationStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.headline); Spacer()
                Text("Pinch to zoom · double-click: fit / 100%").font(.caption).foregroundStyle(.secondary)
                InfoButton(path: path)
                Button("Done") { dismiss() }.keyboardShortcut(.escape, modifiers: []) }.padding(10)
            Divider()
            AnnotateBar(store: store, path: path)
            AnnotatableImage(path: path, store: store)
        }.frame(minWidth: 800, minHeight: 580)
    }
}

struct VideoSheet: View {
    let path: String; let title: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.headline); Spacer()
                Text("J ◀◀  K pause  L ▶▶  ·  ← → one frame  ·  Esc to close").font(.caption).foregroundStyle(.secondary)
                Button("Done") { dismiss() }.keyboardShortcut(.escape, modifiers: []) }.padding(10)
            Divider()
            VideoViewer(path: path)
        }.frame(minWidth: 820, minHeight: 560)
    }
}

// MARK: a question

struct SecKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

struct SectionView: View {
    let section: Question
    @ObservedObject var model: PickModel

    var only: Bool { model.job.sections.count == 1 }
    /// The title of the question. With a single question, the title of the whole popup question is used.
    var titleText: String { section.question ?? (only ? model.job.question : nil) ?? section.heading }
    var subtitle: String {
        let how = section.multi ? "Pick any" : "Pick one"
        return only ? how : "\(section.heading) · \(how.lowercased())"
    }

    var gridColumns: [GridItem] {
        let kinds = Set(section.items.map { $0.kind })
        if kinds.isSubset(of: [.chip]) { return [GridItem(.adaptive(minimum: 200), spacing: 12)] }
        if kinds.isSubset(of: [.image, .video]) { return [GridItem(.adaptive(minimum: 260), spacing: 14)] }
        return [GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if section.slice != nil { sliceControls }
                layoutPicker
                if section.multi {
                    let all = model.chosen(section).count == section.items.count
                    Text("\(model.chosen(section).count) of \(section.items.count)").font(.caption).foregroundStyle(.secondary)
                    Button(all ? "Clear" : "Select all") { model.selectAll(section, !all) }.controlSize(.small)
                }
            }
            switch model.layout(section) {
            case .grid:
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(section.items) { OptionCard(item: $0, section: section, model: model) }
                }
            case .dense:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 230), spacing: 6)], spacing: 6) {
                    ForEach(section.items) { it in
                        if isVisual(it) { DenseTile(item: it, section: section, model: model) }
                        else { OptionCard(item: it, section: section, model: model) }
                    }
                }
            case .detail:
                DetailLayout(section: section, model: model)
            }
            retryCard
            TextField("Note on \(only ? "your choice" : section.heading.lowercased()) (optional)", text: model.sectionNote(section)).textFieldStyle(.roundedBorder)
        }
    }

    /// Grid, Detail or Dense.
    var layoutPicker: some View {
        Picker("", selection: Binding(get: { model.layout(section) }, set: { model.setLayout(section, $0) })) {
            Image(systemName: "square.grid.2x2").tag(QuestionLayout.grid).help("Grid: a card for each option")
            Image(systemName: "sidebar.left").tag(QuestionLayout.detail).help("Detail: a list and a large preview")
            Image(systemName: "square.grid.3x3").tag(QuestionLayout.dense).help("Dense: only big thumbnails")
        }.pickerStyle(.segmented).labelsHidden().frame(width: 120)
    }

    /// Fix the grid by hand when the automatic one is wrong.
    var sliceControls: some View {
        let s = section.slice!
        return HStack(spacing: 6) {
            Text("Grid").font(.caption).foregroundStyle(.secondary)
            Stepper("\(s.cols) col", onIncrement: { model.reslice(section.id, cols: s.cols + 1, rows: s.rows) },
                    onDecrement: { model.reslice(section.id, cols: s.cols - 1, rows: s.rows) }).font(.caption).fixedSize()
            Stepper("\(s.rows) row", onIncrement: { model.reslice(section.id, cols: s.cols, rows: s.rows + 1) },
                    onDecrement: { model.reslice(section.id, cols: s.cols, rows: s.rows - 1) }).font(.caption).fixedSize()
            Button("Auto") { model.autoSlice(section.id) }.controlSize(.small).disabled(s.auto).help("Find the grid from the empty space")
        }
    }

    var retryCard: some View {
        let on = model.isRetry(section)
        return HStack {
            KeyCap(t: "0")
            Image(systemName: "arrow.counterclockwise")
            Text("None of these: make new options").font(.headline)
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? Color.accentColor : .secondary)
        }.allowsHitTesting(false).padding(12).selectable(on) { model.toggleRetry(section) }
    }
}

// MARK: sidebar + page

@MainActor
final class Nav: ObservableObject {
    @Published var q: String
    var jumping = false
    init(first: String) { q = first }
}

struct PickRoot: View {
    @ObservedObject var model: PickModel
    @State var nav: Nav
    @FocusState var focused: Bool

    init(model: PickModel) {
        self.model = model
        _nav = State(initialValue: Nav(first: model.job.sections.first?.id ?? ""))
    }

    var secs: [Question] { model.job.sections }
    var currentSection: Question? { secs.first { $0.id == nav.q } ?? secs.first }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HSplitView {
                    Sidebar(nav: nav, model: model) { n in
                        nav.q = n; nav.jumping = true
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(n, anchor: .top) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nav.jumping = false }
                    }
                    page(proxy)
                }
                Divider()
                bottom
            }
            .focusable().focusEffectDisabled().focused($focused)
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { k in handle(k, proxy) }
        }
    }

    func page(_ proxy: ScrollViewProxy) -> some View {
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    ForEach(secs) { s in
                        SectionView(section: s, model: model).id(s.id)
                            .background(GeometryReader { g in Color.clear.preference(key: SecKey.self, value: [s.id: g.frame(in: .named("scroll")).minY]) })
                    }
                    Color.clear.frame(height: max(0, outer.size.height - 320))
                }.padding(20)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(SecKey.self) { v in
                guard !nav.jumping else { return }
                let cur = secs.last(where: { (v[$0.id] ?? .infinity) <= 80 })?.id ?? secs.first?.id ?? ""
                if cur != nav.q { nav.q = cur }
            }
        }.frame(minWidth: 520)
    }

    func go(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard let i = secs.firstIndex(where: { $0.id == nav.q }) else { return }
        let n = secs[min(secs.count - 1, max(0, i + delta))].id
        nav.q = n; nav.jumping = true
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(n, anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nav.jumping = false }
    }

    func handle(_ k: KeyPress, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        if isTypingInTextField() { return .ignored }      // typing in a note or the feedback field is not a shortcut
        if k.modifiers.contains(.command) { return .ignored }
        let c = k.characters
        if c == "]" { go(1, proxy); return .handled }
        if c == "[" { go(-1, proxy); return .handled }
        guard let s = currentSection else { return .ignored }
        if model.layout(s) == .detail {
            if k.key == .upArrow { model.moveFocus(s, -1); return .handled }
            if k.key == .downArrow { model.moveFocus(s, 1); return .handled }
            if k.key == .return, let it = model.focusedItem(s) { model.toggle(s, it.key); return .handled }
        }
        if c == "0" { model.toggleRetry(s); return .handled }
        if c == " " { model.quickLook(s); return .handled }
        if c.count == 1, let ch = c.uppercased().first, ch.isLetter,
           let it = s.items.first(where: { $0.key == String(ch) }) {
            model.focus[s.id] = it.key
            model.toggle(s, it.key); return .handled
        }
        return .ignored
    }

    var bottom: some View {
        VStack(spacing: 8) {
            if model.showPreview {
                TextEditor(text: Binding(get: { model.text }, set: { model.override = $0 }))
                    .font(.system(.callout, design: .monospaced)).frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            HStack(spacing: 10) {
                Text("\(model.answeredCount) of \(secs.count) answered").font(.caption).foregroundStyle(.secondary)
                Button { model.showPreview.toggle() } label: {
                    Label("Answer", systemImage: model.showPreview ? "chevron.down" : "chevron.up").labelStyle(.titleAndIcon)
                }.controlSize(.small)
                TextField("Feedback (optional)", text: model.feedback).textFieldStyle(.roundedBorder)
                Button { if let s = currentSection { model.quickLook(s) } } label: { Image(systemName: "eye") }
                    .keyboardShortcut("y", modifiers: .command).help("Quick Look (Space)").controlSize(.small)
                Button { model.copyAnswer() } label: {
                    Label(model.copied ? "Copied" : "Copy answer", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                }.keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy the answer text (⇧⌘C). The popup stays open.")
                Button(model.waiting ? "Send answer" : "Send") { model.finish(.send) }
                    .keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
            }
        }.padding(12)
    }
}
