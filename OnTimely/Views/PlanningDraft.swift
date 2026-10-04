import Foundation

enum PlanningScreen: Int {
    case due, duration, start, review

    var title: String {
        switch self {
        case .due: "When is it due?"
        case .duration: "How much time will it take?"
        case .start: "When would you like to start?"
        case .review: "Review your plan"
        }
    }
}

enum PlanningStartChoice: String, CaseIterable, Identifiable {
    case now = "Start now", latest = "Latest safe start", chosen = "Choose a time"
    var id: String { rawValue }
}

/// Presentation state only. No task changes are persisted until this becomes a TaskPlan.
struct PlanningDraft {
    var title: String
    var dueDate: Date
    var estimatedText: String
    var bufferText: String
    var intervalText: String
    var submissionLeadText: String
    var startChoice: PlanningStartChoice
    var startNowAnchor: Date
    var chosenStartDate: Date
    var overridesLatest: Bool
    var overrideDate: Date

    init(task: TaskItem, dueDay: Date? = nil, now: Date = .now) {
        let hasSavedPlan = task.dueDate != nil
        let due = task.dueDate ?? dueDay.map { Self.initialDeadline(on: $0, now: now) }
            ?? now.addingTimeInterval(4 * 60 * 60)
        let estimate = hasSavedPlan ? Int(task.estimatedDuration / 60) : 60
        let buffer = hasSavedPlan ? Int(task.safetyBuffer / 60) : ReminderDefaults.bufferMinutes
        let calculated = DeadlineCalculator.latestSafeStart(dueDate: due,
                                                            estimatedDuration: TimeInterval(estimate) * 60,
                                                            safetyBuffer: TimeInterval(buffer) * 60)
        let latest = task.latestSafeStartOverride ?? calculated
        title = task.title
        dueDate = due
        estimatedText = String(estimate)
        bufferText = String(buffer)
        intervalText = String(hasSavedPlan ? Int(task.reminderInterval / 60) : ReminderDefaults.intervalMinutes)
        submissionLeadText = String(hasSavedPlan ? Int(task.submissionReminderLeadTime / 60) : ReminderDefaults.submissionLeadMinutes)
        // Saved dates remain explicit, so editing other answers never silently moves them.
        startChoice = task.suggestedStartDate == nil ? .now : .chosen
        startNowAnchor = now
        chosenStartDate = task.suggestedStartDate ?? min(now, latest)
        overridesLatest = task.latestSafeStartOverride != nil
        overrideDate = latest
    }

    /// Seed a calendar-created draft without treating it as an already saved plan.
    private static func initialDeadline(on day: Date, now: Date) -> Date {
        let calendar = Calendar.current
        let defaultDue = now.addingTimeInterval(4 * 60 * 60)
        if calendar.isDate(day, inSameDayAs: now), let interval = calendar.dateInterval(of: .day, for: day) {
            return min(defaultDue, interval.end.addingTimeInterval(-1))
        }
        let time = calendar.dateComponents([.hour, .minute], from: defaultDue)
        return calendar.date(bySettingHour: time.hour ?? 18, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    var durationError: String? {
        MinuteText.error(estimatedText, range: 1...10_080,
                         message: "Estimated work must be between 1 minute and 7 days.")
    }
    var bufferError: String? {
        MinuteText.error(bufferText, range: 0...10_080,
                         message: "The safety buffer must be between 0 minutes and 7 days.")
    }
    var intervalError: String? {
        MinuteText.error(intervalText, range: 1...60,
                         message: "The reminder interval must be between 1 and 60 minutes.")
    }
    var submissionLeadError: String? {
        MinuteText.error(submissionLeadText, range: 1...1_440,
                         message: "Submission reminders must begin 1 minute to 24 hours before due.")
    }

    var calculatedLatest: Date? {
        guard durationError == nil, bufferError == nil,
              let estimate = MinuteText.value(estimatedText), let buffer = MinuteText.value(bufferText) else { return nil }
        return DeadlineCalculator.latestSafeStart(dueDate: dueDate,
                                                  estimatedDuration: TimeInterval(estimate) * 60,
                                                  safetyBuffer: TimeInterval(buffer) * 60)
    }

    var latestSafeStart: Date? { overridesLatest ? overrideDate : calculatedLatest }

    var suggestedStart: Date? {
        switch startChoice {
        case .now: latestSafeStart.map { min(startNowAnchor, $0) }
        case .latest: latestSafeStart
        case .chosen: chosenStartDate
        }
    }

    var plan: TaskPlan? {
        guard durationError == nil, bufferError == nil, intervalError == nil, submissionLeadError == nil,
              let estimate = MinuteText.value(estimatedText), let buffer = MinuteText.value(bufferText),
              let interval = MinuteText.value(intervalText), let lead = MinuteText.value(submissionLeadText),
              let suggested = suggestedStart else { return nil }
        return TaskPlan(title: title, dueDate: dueDate, estimatedMinutes: estimate, safetyBufferMinutes: buffer,
                        suggestedStartDate: suggested, latestSafeStartOverride: overridesLatest ? overrideDate : nil,
                        submissionLeadMinutes: lead, reminderIntervalMinutes: interval)
    }

    func startError() -> String? {
        guard durationError == nil, bufferError == nil,
              let latest = latestSafeStart, let suggested = suggestedStart else {
            return "Enter a valid duration and safety buffer before choosing a start."
        }
        if latest >= dueDate { return "Latest safe start must be before the due time." }
        if suggested > latest { return "Suggested start must be at or before latest safe start. Choose an earlier time." }
        return nil
    }

    func validationMessage(at now: Date) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the task a name." }
        if dueDate <= now { return "Choose a due time in the future." }
        if let error = durationError ?? bufferError ?? submissionLeadError ?? intervalError { return error }
        // The existing validator remains the final authority for the complete draft.
        return plan?.validationMessage(at: now) ?? startError()
    }

    mutating func selectStart(_ choice: PlanningStartChoice, now: Date = .now) {
        startChoice = choice
        if choice == .now { startNowAnchor = now }
    }

    mutating func setDueDay(offset: Int, now: Date = .now) {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return }
        let time = calendar.dateComponents([.hour, .minute, .second], from: dueDate)
        if let combined = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                        second: time.second ?? 0, of: day) {
            dueDate = combined
        }
    }
}
