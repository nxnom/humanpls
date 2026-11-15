import SwiftUI
import AppKit
import HumanplsCore

/// The large view of one option, used by the viewer (`show`).
struct ItemViewer: View {
    let item: Item
    var store: AnnotationStore? = nil               // image drawing tools, when given
    var onMark: ((Double) -> Void)? = nil           // video: M adds a mark, when given

    var body: some View {
        if !fileExists(item.path) {
            MissingFile(path: item.path ?? "").padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Fresh(path: item.path) { content }
        }
    }

    @ViewBuilder var content: some View {
        switch item.kind {
        case .file: FileInfoView(path: item.path ?? "", big: true)
        case .image:
            if item.crop != nil {
                ZoomImage(path: item.path ?? "", crop: item.crop)                  // a cell of a sheet: only that part
            } else if let store {
                VStack(spacing: 0) {
                    AnnotateBar(store: store, path: item.path ?? "")
                    AnnotatableImage(path: item.path ?? "", store: store)
                }
            } else {
                ZoomImage(path: item.path ?? "")
            }
        case .video: VideoViewer(path: item.path ?? "", onMark: onMark)
        case .audio: AudioViewer(path: item.path ?? "")
        case .pdf: PDFRep(path: item.path ?? "")
        case .html: WebRep(path: item.path, html: item.path == nil ? item.text : nil)
        case .markdown, .code, .text: RichText(item: item)
        case .chip:
            Text(item.text ?? "").font(.system(size: 44, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .url:
            if let u = item.url, let url = URL(string: u) { Link(u, destination: url).font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

/// The name shown for an option: its label, its text, the cell position, or the file name.
func displayTitle(_ item: Item) -> String {
    if let r = item.cellRow, let c = item.cellCol { return item.answerName ?? "R\(r) · C\(c)" }
    return item.answerName ?? item.fileName ?? "Option \(item.key)"
}
