import SwiftUI

struct NotesEditor: View {
    @Binding var text: String
    var placeholder = "Write notes"
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .textEditorStyle(.plain)
            .writingToolsAffordanceVisibility(.hidden)
            .font(.system(size: 15))
            .lineSpacing(5)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, -5)
            .bottomFade(40)
            .accessibilityLabel("Notes")
    }
}
