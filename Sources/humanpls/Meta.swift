import SwiftUI
import HumanplsCore

/// What is stored inside an image: size, camera data, and the prompt or seed that AI tools write into the file.
struct MetaView: View {
    let path: String
    @State var fields: [MetaField] = []
    @State var loaded = false

    var sections: [String] {
        var seen: [String] = []
        for f in fields where !seen.contains(f.section) { seen.append(f.section) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loaded && fields.isEmpty { Text("No information found in this file.").foregroundStyle(.secondary) }
                ForEach(sections, id: \.self) { sec in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sec).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(fields.filter { $0.section == sec }) { f in
                            if sec == "Text in file" || f.value.count > 60 || f.value.contains("\n") {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(f.key).font(.callout.weight(.medium))
                                        Spacer()
                                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.value, forType: .string) }
                                            .controlSize(.small)
                                    }
                                    Text(f.value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(f.key).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                                    Text(f.value).textSelection(.enabled)
                                }.font(.callout)
                            }
                        }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 400)
        .task(id: path) {
            let p = path
            fields = await Task.detached(priority: .userInitiated) { ImageMeta.read(path: p) }.value
            loaded = true
        }
    }
}

struct InfoButton: View {
    let path: String
    @State var open = false
    var body: some View {
        Button { open.toggle() } label: { Label("Info", systemImage: "info.circle") }
            .controlSize(.small)
            .popover(isPresented: $open, arrowEdge: .bottom) { MetaView(path: path) }
    }
}
