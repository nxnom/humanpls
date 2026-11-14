import SwiftUI
import HumanplsCore

/// Markdown and code. Stage 1: plain text. (Stage 3 swaps this for a rendered view with syntax colors.)
struct RichText: View {
    let item: Item
    var text: String {
        if let t = item.text { return t }
        if let p = item.path, let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
        return ""
    }
    var body: some View {
        ScrollView {
            Text(text).font(.system(.callout, design: item.kind == .code ? .monospaced : .default))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.background(.background.secondary)
    }
}
