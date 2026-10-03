import Foundation

enum ReminderPhase: String, Codable, Sendable {
    case suggestedStart, latestStart, submission
}

enum TaskAttention: Int, Sendable {
    case overdue = 0, submission, mustStart, shouldStart, working, later, inactive
}

struct TaskSnapshot: Sendable {
    var id: UUID
    var title: String
    var status: TaskStatus
    var dueDate: Date?
    var suggestedStartDate: Date?
    var latestSafeStartDate: Date?
    var submissionLeadTime: TimeInterval
    var reminderInterval: TimeInterval
    var hasConfirmedWorking: Bool
    var hasConfirmedLatestStart: Bool
    var activatedAt: Date?
    var snoozedUntil: Date?
    var snoozedPhase: ReminderPhase?
    var revision: UUID

    var submissionStartDate: Date? {
        dueDate?.addingTimeInterval(-submissionLeadTime)
    }

    func phase(at now: Date) -> ReminderPhase? {
        guard status == .active, let dueDate, let suggestedStartDate, let latestSafeStartDate else {
            return nil
        }
        if now >= dueDate.addingTimeInterval(-submissionLeadTime) { return .submission }
        if now >= latestSafeStartDate { return .latestStart }
        if now >= suggestedStartDate { return .suggestedStart }
        return nil
    }

    func attention(at now: Date) -> TaskAttention {
        guard status == .active else { return .inactive }
        if let dueDate, now >= dueDate { return .overdue }
        switch phase(at: now) {
        case .submission: return .submission
        case .latestStart: return hasConfirmedLatestStart ? .working : .mustStart
        case .suggestedStart: return hasConfirmedWorking ? .working : .shouldStart
        case nil: return hasConfirmedWorking ? .working : .later
        }
    }

    func isConfirmed(_ phase: ReminderPhase) -> Bool {
        switch phase {
        case .suggestedStart: hasConfirmedWorking
        case .latestStart: hasConfirmedLatestStart
        case .submission: false
        }
    }

    func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil, let snoozedPhase else { return false }
        return snoozedUntil > now && snoozedPhase == phase(at: now)
    }
}
