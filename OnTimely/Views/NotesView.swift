import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \NoteItem.createdAt, order: .reverse) private var notes: [NoteItem]
    @SceneStorage("notes.selectedNoteID") private var selectedNoteID = ""
    @State private var deletingNote: NoteItem?

    private var selectedNote: NoteItem? { notes.first { $0.id.uuidString == selectedNoteID } }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    PageHeading(title: "Notes", subtitle: "A little space for your thoughts.")
                    Spacer(minLength: 8)
                    if !notes.isEmpty {
                        Button(action: createNote) { Label("New note", systemImage: "plus") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                if notes.isEmpty {
                    TaskEmptyState(symbol: "note.text", title: "Your notes start here.",
                                   message: "Create a note and make it your own. Your edits save automatically.",
                                   actionTitle: "Create a note", action: createNote)
                    Spacer()
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        noteList
                            .frame(width: min(220, max(150, (geometry.size.width - 48) * 0.3)))
                        Rectangle().fill(TaskStyle.separator).frame(width: 1)
                        if let note = selectedNote {
                            NoteEditorView(note: note, onDelete: { deletingNote = $0 })
                                .id(note.id)
                                .padding(.leading, 20)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Text("Choose a note to start writing.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: notes.map(\.id)) { _, _ in selectFirstIfNeeded() }
        .task(id: runtime.newNoteRequest) {
            guard runtime.newNoteRequest != nil else { return }
            runtime.newNoteRequest = nil
            createNote()
        }
        .alert("Are you sure?", isPresented: Binding(
            get: { deletingNote != nil },
            set: { if !$0 { deletingNote = nil } }
        ), presenting: deletingNote) { note in
            Button("Delete", role: .destructive) { delete(note) }
            Button("Cancel", role: .cancel) { deletingNote = nil }
        } message: { note in
            Text("“\(note.displayTitle)” will be permanently deleted.")
        }
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(notes) { note in
                    Button { selectedNoteID = note.id.uuidString } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(verbatim: note.excerpt).font(TaskStyle.metadata).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(selectedNoteID == note.id.uuidString ? TaskStyle.selection : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(note.displayTitle)
                    .accessibilityAddTraits(selectedNoteID == note.id.uuidString ? [.isSelected] : [])
                    .contextMenu {
                        Button("Delete note", role: .destructive) { deletingNote = note }
                    }
                }
            }
            .padding(.trailing, 12)
        }
    }

    private func createNote() {
        guard let store = runtime.noteStore else { return }
        do {
            let note = try store.create()
            selectedNoteID = note.id.uuidString
        } catch {
            runtime.errorMessage = "Your note couldn’t be created. \(error.localizedDescription)"
        }
    }

    private func delete(_ note: NoteItem) {
        guard let store = runtime.noteStore else { return }
        do {
            try store.delete(note)
            if selectedNoteID == note.id.uuidString {
                selectedNoteID = notes.first { $0.id != note.id }?.id.uuidString ?? ""
            }
            deletingNote = nil
        } catch {
            runtime.errorMessage = "Your note couldn’t be deleted. \(error.localizedDescription)"
        }
    }

    private func selectFirstIfNeeded() {
        if selectedNote == nil { selectedNoteID = notes.first?.id.uuidString ?? "" }
    }
}
