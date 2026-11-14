import SwiftUI

/// A text box that is easy to see and to type in: rounded, roomy, grows with the text, and shows a clear border when focused.
struct NoteField: View {
    let placeholder: String
    @Binding var text: String
    var minLines = 2
    var maxLines = 8
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(minLines...maxLines)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: CGFloat(minLines) * 19 + 22, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(focused ? 0.09 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: focused ? 2 : 1))
            .focused($focused)
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}
