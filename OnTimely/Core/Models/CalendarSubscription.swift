import Foundation
import SwiftData

@Model
final class CalendarSubscription {
    @Attribute(.unique) var id: UUID
    var feedFingerprint: String
    var name: String
    var host: String
    var timeZoneIdentifier: String
    var createdAt: Date
    var lastSyncedAt: Date?
    var lastSyncError: String?
    var dismissedEventIDs: [String] = []

    // The private subscription URL is kept in Keychain, not in the task database.
    init(feedFingerprint: String, name: String, host: String, timeZoneIdentifier: String) {
        id = UUID()
        self.feedFingerprint = feedFingerprint
        self.name = name
        self.host = host
        self.timeZoneIdentifier = timeZoneIdentifier
        createdAt = .now
    }
}

struct ImportedCalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCancelled: Bool
}

struct ImportedCalendarFeed: Sendable {
    let name: String?
    let events: [ImportedCalendarEvent]
    let excludedEntryCount: Int
}

struct CalendarImportResult: Sendable {
    var added = 0
    var updated = 0
    var skippedPastDue = 0
}
