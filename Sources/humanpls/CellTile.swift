import SwiftUI
import AppKit
import HumanplsCore

// MARK: image sheet cells

/// One cell of an image sheet: a square thumbnail with a key letter and a check.
struct CellTile: View {
    let item: Item
    let section: Question
    @ObservedObject var model: PickModel
    @State var thumb: NSImage? = nil
    @State var zoom = false
    @State var play = false
    @ObservedObject var watch = FileWatch.shared

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
        .task(id: "\(String(describing: item.crop)) \(watch.version(item.path))") {
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
