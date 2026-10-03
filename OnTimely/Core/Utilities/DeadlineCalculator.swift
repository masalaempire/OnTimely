import Foundation

enum DeadlineCalculator {
    static func latestSafeStart(
        dueDate: Date, estimatedDuration: TimeInterval, safetyBuffer: TimeInterval
    ) -> Date {
        dueDate.addingTimeInterval(-estimatedDuration - safetyBuffer)
    }
}

struct TaskPlan: Equatable, Sendable {
    var title: String
    var dueDate: Date
    var estimatedMinutes: Int
    var safetyBufferMinutes: Int
    var suggestedStartDate: Date
    var latestSafeStartOverride: Date?
    var submissionLeadMinutes: Int
    var reminderIntervalMinutes: Int

    var latestSafeStartDate: Date {
        latestSafeStartOverride ?? DeadlineCalculator.latestSafeStart(
            dueDate: dueDate, estimatedDuration: TimeInterval(estimatedMinutes) * 60,
            safetyBuffer: TimeInterval(safetyBufferMinutes) * 60
        )
    }

    func validationMessage(at now: Date) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the task a name." }
        if dueDate <= now { return "Choose a due time in the future." }
        if !(1...10_080).contains(estimatedMinutes) { return "Estimated work must be between 1 minute and 7 days." }
        if !(0...10_080).contains(safetyBufferMinutes) { return "The safety buffer must be between 0 minutes and 7 days." }
        if !(1...1_440).contains(submissionLeadMinutes) { return "Submission reminders must begin 1 minute to 24 hours before due." }
        if !(1...60).contains(reminderIntervalMinutes) { return "The reminder interval must be between 1 and 60 minutes." }
        if latestSafeStartDate >= dueDate { return "Latest safe start must be before the due time." }
        if suggestedStartDate > latestSafeStartDate { return "Suggested start must be at or before latest safe start." }
        return nil
    }
}
