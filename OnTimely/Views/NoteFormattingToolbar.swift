import Foundation
import SwiftUI

struct NoteFormattingToolbar: View {
    @ObservedObject var formatting: NoteFormattingController
    @State private var showingLink = false
    private let sizes: [CGFloat] = [12, 14, 15, 16, 18, 20, 24, 28, 32, 36]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(NoteBlockStyle.allCases) { style in
                        Button { formatting.setBlockStyle(style) } label: {
                            HStack {
                                Text(style.rawValue)
                                if formatting.blockStyle == style { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(formatting.blockStyle.rawValue).font(.system(size: 12))
                        .frame(minWidth: 66, minHeight: 28)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Paragraph style").accessibilityLabel("Paragraph style")

                Menu {
                    ForEach(sizes, id: \.self) { size in
                        Button { formatting.setFontSize(size) } label: {
                            HStack {
                                Text("\(Int(size)) pt")
                                if formatting.fontSize == size { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text("\(Int(formatting.fontSize))").monospacedDigit()
                    }
                    .font(.system(size: 12)).frame(minHeight: 28)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Text size").accessibilityLabel("Text size")
                separator
                control("Bold", symbol: "bold", selected: formatting.isBold, help: "Bold (⌘B)", action: formatting.toggleBold)
                control("Italic", symbol: "italic", selected: formatting.isItalic, help: "Italic (⌘I)", action: formatting.toggleItalic)
                control("Underline", symbol: "underline", selected: formatting.isUnderlined, help: "Underline (⌘U)", action: formatting.toggleUnderline)
                control("Strikethrough", symbol: "strikethrough", selected: formatting.isStruckThrough, action: formatting.toggleStrikethrough)
                separator
                Menu {
                    Button("Bulleted list", systemImage: "list.bullet") { formatting.toggleList(.bullet) }
                    Button("Numbered list", systemImage: "list.number") { formatting.toggleList(.numbered) }
                    Button("Checklist", systemImage: "checklist") { formatting.toggleList(.checklist) }
                    if formatting.blockKind == "checklist" {
                        Button("Check or uncheck item", systemImage: "checkmark.square") { formatting.toggleChecklistItem() }
                    }
                } label: {
                    Image(systemName: "list.bullet").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Lists").accessibilityLabel("Lists")
                control("Link", symbol: "link", action: { showingLink = true })
                    .popover(isPresented: $showingLink, arrowEdge: .bottom) {
                        NoteLinkPopover(formatting: formatting)
                    }
                control("Inline code", symbol: "chevron.left.forwardslash.chevron.right", selected: formatting.isCode,
                        action: formatting.toggleCode)
                Menu {
                    Button("Quote", systemImage: "text.quote") { formatting.toggleList(.quote) }
                    Button("Code block", systemImage: "curlybraces") { formatting.setCodeBlock() }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More formatting").accessibilityLabel("More formatting")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(height: 44)
        .background(TaskStyle.content)
    }

    private var separator: some View {
        Rectangle().fill(TaskStyle.separator).frame(width: 1, height: 20).padding(.horizontal, 3)
    }

    private func control(_ title: String, symbol: String, selected: Bool = false, help: String? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13))
                .frame(width: 28, height: 28)
                .foregroundStyle(selected ? TaskStyle.coral : TaskStyle.text)
                .background(selected ? TaskStyle.selection : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help ?? title).accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct NoteLinkPopover: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var formatting: NoteFormattingController
    @State private var linkText: String
    @State private var address = ""
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    init(formatting: NoteFormattingController) {
        self.formatting = formatting
        _linkText = State(initialValue: formatting.selectedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a link").font(.system(size: 15, weight: .semibold))
            TextField("Text to display", text: $linkText)
            TextField("Web address", text: $address).focused($addressFocused)
            if let error { Text(error).font(TaskStyle.metadata).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Insert", action: insert).buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .textFieldStyle(.roundedBorder).padding(16).frame(width: 300)
        .onAppear { addressFocused = true }
        .onSubmit(insert)
    }

    private func insert() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = URLComponents(string: trimmed)?.scheme == nil ? "https://" + trimmed : trimmed
        guard !trimmed.isEmpty, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (["http", "https"].contains(scheme) && !(url.host ?? "").isEmpty) || (scheme == "mailto" && !url.path.isEmpty) else {
            error = "Enter a valid web or email address."
            return
        }
        let label = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        formatting.insertLink(label: label.isEmpty ? trimmed : label, url: url)
        dismiss()
    }
}
