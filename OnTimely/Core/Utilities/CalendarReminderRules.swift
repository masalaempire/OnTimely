import Foundation

struct CalendarReminderTimes: Sendable {
    let suggestedStart: Date
    let latestStart: Date
}

enum CalendarReminderRules {
    static func times(dueDate: Date, timeZone: TimeZone) -> CalendarReminderTimes {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.startOfDay(for: dueDate)
        let cutoff = calendar.date(bySettingHour: 16, minute: 20, second: 0, of: day) ?? day
        let earlyDeadline = dueDate <= cutoff
        let reminderDay = earlyDeadline
            ? calendar.date(byAdding: .day, value: -1, to: day) ?? day
            : day
        let suggested = calendar.date(bySettingHour: earlyDeadline ? 19 : 18,
                                      minute: earlyDeadline ? 0 : 50, second: 0, of: reminderDay) ?? reminderDay
        let latest = calendar.date(bySettingHour: earlyDeadline ? 22 : 21,
                                   minute: 0, second: 0, of: reminderDay) ?? reminderDay
        // Both checkpoints must precede the actual submission deadline.
        if suggested >= dueDate || latest >= dueDate {
            return CalendarReminderTimes(suggestedStart: dueDate.addingTimeInterval(-2 * 60 * 60),
                                         latestStart: dueDate.addingTimeInterval(-60 * 60))
        }
        return CalendarReminderTimes(suggestedStart: suggested, latestStart: latest)
    }
}
