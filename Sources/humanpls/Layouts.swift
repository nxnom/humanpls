import SwiftUI
import AppKit
import HumanplsCore

// MARK: dense: big thumbnails only

/// One square thumbnail with a key letter and a check. For many images or logos.
struct DenseTile: View {
    let item: Item
    let section: Question
    @ObservedObject var model: PickModel
    @State var thumb: NSImage? = nil
    @State var zoom = false
    @State var play = false

    var on: Bool { model.chosen(section).contains(item.key) }
    func pick() { model.toggle(section, item.key) }

    var body: some View {
        ZStack {
            (item.crop != nil ? Color.white : Color.primary.opacity(0.06))
            if let thumb { Image(nsImage: thumb).resizable().scaledToFit().padding(item.crop != nil ? 8 : 0) }
            if item.kind == .video { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 3) }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Text(item.key).font(.system(.caption, design: .rounded).weight(.bold))
                if item.recommended { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).help("Recommended") }
            }
            .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            .padding(6).allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: pick) {
                ZStack {
                    if on { Circle().fill(Color.accentColor); Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                    else { Circle().fill(Color.white.opacity(0.92)); Circle().stroke(Color.gray.opacity(0.7), lineWidth: 1.5) }
                }.frame(width: 22, height: 22).shadow(color: .black.opacity(0.25), radius: 1.5)
            }.buttonStyle(.plain).padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { if item.kind == .video { play = true } else { zoom = true } } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption).foregroundStyle(.white).padding(6)
                    .background(Color.black.opacity(0.5), in: Circle())
            }.buttonStyle(.plain).padding(6)
        }
        .padding(6)
        .selectable(on, pick)
        .onHover { if $0 { model.hovered = (section.id, item.key) } }
        .task(id: item.crop) {
            guard let p = item.path else { return }
            if let c = item.crop { thumb = await Cache.cell(p, c, maxPixel: 420) }
            else if item.kind == .video { thumb = await Cache.poster(p) }
            else { thumb = await Cache.thumb(p, maxPixel: 600) }
        }
        .sheet(isPresented: $zoom) {
            if item.crop != nil { CellSheet(path: item.path ?? "", crop: item.crop, title: "\(item.key)  \(displayTitle(item))") }
            else { ImageSheet(path: item.path ?? "", title: "\(item.key)  \(displayTitle(item))", store: model.store) }
        }
        .sheet(isPresented: $play) { VideoSheet(path: item.path ?? "", title: "\(item.key)  \(displayTitle(item))") }
    }
}

/// Only images and videos make good dense tiles. Everything else keeps its normal card.
func isVisual(_ item: Item) -> Bool { item.kind == .image || item.kind == .video }

// MARK: detail: a list on the left, a large preview on the right

struct DetailRow: View {
    let item: Item
    let section: Question
    @ObservedObject var model: PickModel
    var on: Bool { model.chosen(section).contains(item.key) }
    var focused: Bool { model.focusedItem(section)?.key == item.key }

    var body: some View {
        HStack(spacing: 10) {
            Thumb(item: item).frame(width: 48, height: 38).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) { Text(item.key).font(.caption2.weight(.bold)).foregroundStyle(.secondary); if item.recommended { Badge() } }
                Text(displayTitle(item)).font(.callout.weight(.medium)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.toggle(section, item.key) } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? Color.accentColor : .secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(focused ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(RoundedRectangle(cornerRadius: 9)).onTapGesture { model.focus[section.id] = item.key })
    }
}

struct DetailLayout: View {
    let section: Question
    @ObservedObject var model: PickModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) { ForEach(section.items) { DetailRow(item: $0, section: section, model: model) } }.padding(8)
            }.frame(width: 270)
            Divider()
            if let it = model.focusedItem(section) { pane(it) } else { Spacer() }
        }
        .frame(height: 580)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func pane(_ it: Item) -> some View {
        let on = model.chosen(section).contains(it.key)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                KeyCap(t: it.key)
                Text(displayTitle(it)).font(.headline).lineLimit(1)
                if it.recommended { Badge() }
                Spacer()
                Button { model.moveFocus(section, -1) } label: { Image(systemName: "chevron.up") }.help("Previous (↑)")
                Button { model.moveFocus(section, 1) } label: { Image(systemName: "chevron.down") }.help("Next (↓)")
                Button { model.toggle(section, it.key) } label: {
                    Label(on ? "Picked" : "Pick this", systemImage: on ? "checkmark.circle.fill" : "circle")
                }.buttonStyle(.borderedProminent).tint(on ? .green : .accentColor).help("Pick or unpick (Return)")
            }.padding(10)
            Divider()
            ItemViewer(item: it, store: it.crop == nil ? model.store : nil).id(it.key)
            if let n = it.note, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            }
        }
    }
}

// MARK: sidebar: the title, the questions and what you picked so far

struct Sidebar: View {
    @ObservedObject var nav: Nav
    @ObservedObject var model: PickModel
    let jump: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.job.heading).font(.headline).lineLimit(2)
                if let q = model.job.question { Text(q).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            List(selection: Binding(get: { nav.q }, set: { if let n = $0 { jump(n) } })) {
                if model.job.sections.count > 1 {
                    Section("Questions") {
                        ForEach(model.job.sections) { s in
                            HStack {
                                Text(s.heading).lineLimit(1)
                                Spacer()
                                if model.answered(s) {
                                    let c = model.chosen(s).count
                                    Text(model.isRetry(s) ? "↻" : (s.multi ? "\(c)" : "✓")).font(.caption.weight(.semibold)).foregroundStyle(.green)
                                }
                            }.tag(s.id)
                        }
                    }
                }
                Section("Your picks") {
                    let picked = model.pickedItems
                    if picked.isEmpty {
                        Text("Nothing picked yet").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(picked, id: \.item.id) { entry in
                        HStack(spacing: 8) {
                            Thumb(item: entry.item).frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(displayTitle(entry.item)).font(.callout).lineLimit(1)
                                if model.job.sections.count > 1 { Text(entry.question.heading).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            Button { model.toggle(entry.question, entry.item.key) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
                        }
                    }
                }
            }.listStyle(.sidebar)
        }.frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
    }
}
