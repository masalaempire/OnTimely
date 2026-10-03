import Foundation

enum ReminderAction: String, Sendable {
    case working = "ONTIMELY_WORKING"
    case snooze = "ONTIMELY_SNOOZE"
    case done = "ONTIMELY_DONE"
    case open
}
