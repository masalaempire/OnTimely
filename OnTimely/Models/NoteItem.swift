import Foundation
import SwiftData

@Model
final class NoteItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var markdown: String
    /// Preserves rich formatting such as custom text sizes alongside the Markdown version.
    var richTextData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "", markdown: String = "", now: Date = .now) {
        id = UUID()
        self.title = title
        self.markdown = markdown
        richTextData = nil
        createdAt = now
        updatedAt = now
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled note" : trimmed
    }

    var excerpt: String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No text yet" : String(trimmed.prefix(120))
    }
}
