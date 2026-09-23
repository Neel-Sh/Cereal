import SwiftUI

/// Centers content in a readable column, matching the note page width everywhere.
struct PageColumn<Content: View>: View {
    var maxWidth: CGFloat = 640
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: maxWidth, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Lays out children left to right, wrapping onto new rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > width && !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], proposedWidth, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Serif page title used by notes, the recorder, and the library.
struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .regular, design: .serif))
            .lineLimit(2)
    }
}

/// Compact glass capsule for metadata.
struct MetaChip: View {
    let symbol: String
    let text: String
    var tint: Color? = nil

    var body: some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .secondary)
        }
        .labelStyle(ChipLabelStyle())
        .glassEffect(in: .capsule)
    }
}

struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .contentShape(Capsule())
    }
}

/// A metadata chip that edits its value in a popover. Shows a placeholder when empty.
struct EditableChip: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var suggestions: [String] = []
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            Label {
                Text(text.isEmpty ? placeholder : text)
                    .lineLimit(1)
                    .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            .labelStyle(ChipLabelStyle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(text.isEmpty ? "Add \(placeholder.lowercased())" : "Edit \(placeholder.lowercased())")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { isEditing = false }
                let matches = suggestions.filter { !$0.isEmpty && $0 != text && (text.isEmpty || $0.localizedCaseInsensitiveContains(text)) }.prefix(5)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(matches), id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                isEditing = false
                            } label: {
                                Text(suggestion)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

/// Glass chip that opens a menu of note templates.
struct TemplateChip: View {
    @Binding var template: NoteTemplate

    var body: some View {
        Menu {
            Picker("Template", selection: $template) {
                ForEach(NoteTemplate.allCases) { template in
                    Label(template.title, systemImage: template.symbol).tag(template)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(template.title, systemImage: template.symbol)
                .labelStyle(ChipLabelStyle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Template — shapes how notes are enhanced")
    }
}

/// Small secondary heading above a content section.
struct SectionHeading: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Fades scrolling content out before it reaches the floating glass controls at the bottom.
    func bottomFade(_ height: CGFloat = 56) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        }
    }
}

/// Timestamp button that jumps to the cited moment in the recording.
struct SourceButton: View {
    let time: TimeInterval
    var edited = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "waveform").imageScale(.small)
                Text(time.formattedDuration).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(edited ? "Edited — jump to the original source" : "Jump to this moment")
    }
}
