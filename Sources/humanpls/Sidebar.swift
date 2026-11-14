import SwiftUI
import AppKit
import HumanplsCore

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
                    ForEach(picked) { entry in
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
