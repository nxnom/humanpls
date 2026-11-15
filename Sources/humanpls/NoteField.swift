import SwiftUI
import UniformTypeIdentifiers

/// A text box that is easy to see and to type in: rounded, roomy, grows with the text, and shows a clear border when focused.
/// With `files` it also takes attachments: the paperclip button, a drop, or Command-V of a file or an image.
struct NoteField: View {
    let placeholder: String
    @Binding var text: String
    var minLines = 2
    var maxLines = 8
    var files: Binding<[String]>? = nil
    @FocusState private var focused: Bool
    @State private var id = UUID()
    @State private var dropping = false

    func add(_ paths: [String]) {
        guard let files else { return }
        for p in paths where !files.wrappedValue.contains(p) { files.wrappedValue.append(p) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(minLines...maxLines)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                if files != nil {
                    Button { Attachments.choose(add) } label: { Image(systemName: "paperclip").font(.system(size: 14)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Attach files (or drop them here, or paste an image with ⌘V)")
                }
            }
            if let files, !files.wrappedValue.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(files.wrappedValue, id: \.self) { p in
                            AttachmentChip(path: p, all: files.wrappedValue) { files.wrappedValue.removeAll { $0 == p } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minHeight: CGFloat(minLines) * 19 + 22, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(focused ? 0.09 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused || dropping ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: focused || dropping ? 2 : 1))
        .animation(.easeOut(duration: 0.12), value: focused)
        .onChange(of: focused) { _, on in
            guard files != nil else { return }
            if on { Attachments.focus(id, add) } else { Attachments.blur(id) }
        }
        .onDisappear { Attachments.blur(id) }
        .modifier(DropFiles(on: files != nil, dropping: $dropping, add: add))
    }
}

private struct DropFiles: ViewModifier {
    let on: Bool
    @Binding var dropping: Bool
    let add: ([String]) -> Void
    func body(content: Content) -> some View {
        if on { content.onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropping) { Attachments.drop($0, add) } }
        else { content }
    }
}
