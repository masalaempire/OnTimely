import AppKit
import SwiftUI
import SwiftData

private struct NoteDraft: Equatable {
    var title: String
    var content: RichNoteContent
}

struct NoteEditorView: View {
    @Environment(AppRuntime.self) private var runtime
    let note: NoteItem
    let onDelete: (NoteItem) -> Void
    @State private var draft: NoteDraft
    @StateObject private var formatting = NoteFormattingController()
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(note: NoteItem, onDelete: @escaping (NoteItem) -> Void) {
        self.note = note
        self.onDelete = onDelete
        _draft = State(initialValue: NoteDraft(title: note.title,
                                              content: RichNoteContent(markdown: note.markdown, richTextData: note.richTextData)))
    }

    private var hasChanges: Bool {
        draft.title != note.title || draft.content.markdown != note.markdown || draft.content.richTextData != note.richTextData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Untitled note", text: $draft.title)
                    .textFieldStyle(.plain).font(.system(size: 22, weight: .semibold))
                    .focused($titleFocused).accessibilityLabel("Note title")
                TaskOverflowMenu(title: note.displayTitle) {
                    Button("Delete note", role: .destructive) { onDelete(note) }
                }
            }
            VStack(spacing: 0) {
                RichNoteEditor(content: $draft.content, formatting: formatting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TaskSeparator()
                NoteFormattingToolbar(formatting: formatting)
            }
            .background(TaskStyle.hover.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(TaskStyle.separator, lineWidth: 1) }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let saveError {
                    Text(saveError).font(TaskStyle.metadata).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Retry") { save() }.buttonStyle(.link).font(TaskStyle.metadata)
                } else {
                    Text(hasChanges ? "Saving…" : "Saved").font(TaskStyle.metadata).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Save") { save() }.buttonStyle(.link).font(TaskStyle.metadata)
                        .keyboardShortcut("s").disabled(!hasChanges)
                }
            }
        }
        .onAppear { titleFocused = note.title.isEmpty && draft.content.markdown.isEmpty }
        .task(id: draft) {
            guard hasChanges else { return }
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard !Task.isCancelled else { return }
            save()
        }
        // Flush the local draft when leaving Notes, switching notes, closing a window, or quitting.
        .onDisappear { save(reportGlobally: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            save(reportGlobally: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            save(reportGlobally: true)
        }
    }

    private func save(reportGlobally: Bool = false) {
        guard note.modelContext != nil, hasChanges, let store = runtime.noteStore else { return }
        do {
            try store.update(note, title: draft.title, markdown: draft.content.markdown,
                             richTextData: draft.content.richTextData)
            saveError = nil
        } catch {
            let message = "Your edits couldn’t be saved. \(error.localizedDescription)"
            saveError = message
            if reportGlobally { runtime.errorMessage = message }
        }
    }
}
