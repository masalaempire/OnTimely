import Foundation
import SwiftData

@MainActor
final class NoteStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create() throws -> NoteItem {
        let note = NoteItem()
        context.insert(note)
        try save()
        return note
    }

    func update(_ note: NoteItem, title: String, markdown: String, richTextData: Data? = nil, now: Date = .now) throws {
        guard note.modelContext != nil,
              note.title != title || note.markdown != markdown || note.richTextData != richTextData else { return }
        note.title = title
        note.markdown = markdown
        note.richTextData = richTextData
        note.updatedAt = now
        try save()
    }

    func delete(_ note: NoteItem) throws {
        context.delete(note)
        try save()
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
