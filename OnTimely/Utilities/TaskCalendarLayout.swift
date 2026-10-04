import Foundation

/// A saved plan occupies the full window from its suggested start to its deadline.
struct CalendarTaskSchedule: Identifiable {
    let task: TaskItem
    let start: Date
    let end: Date
    var id: UUID { task.id }

    init?(task: TaskItem) {
        guard task.status != .inbox, let start = task.suggestedStartDate,
              let end = task.dueDate, start < end else { return nil }
        self.task = task
        self.start = start
        self.end = end
    }

    func clipped(to interval: DateInterval) -> DateInterval? {
        let start = max(self.start, interval.start)
        let end = min(self.end, interval.end)
        return start < end ? DateInterval(start: start, end: end) : nil
    }
}

struct CalendarTaskPlacement: Identifiable {
    let schedule: CalendarTaskSchedule
    let interval: DateInterval
    let column: Int
    let columnCount: Int
    var id: UUID { schedule.id }
}

enum TaskCalendarLayout {
    static func days(in month: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let cellCount = ((leading + count + 6) / 7) * 7
        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0 - leading, to: interval.start)
        }
    }

    static func schedules(_ schedules: [CalendarTaskSchedule], on day: Date,
                          calendar: Calendar) -> [CalendarTaskSchedule] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return schedules.filter { $0.clipped(to: interval) != nil }.sorted {
            let left = max($0.start, interval.start), right = max($1.start, interval.start)
            if left != right { return left < right }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Connected overlap groups share a width; independent groups use the full width again.
    static func placements(_ schedules: [CalendarTaskSchedule], in day: DateInterval) -> [CalendarTaskPlacement] {
        let entries = schedules.compactMap { schedule -> (CalendarTaskSchedule, DateInterval)? in
            guard let interval = schedule.clipped(to: day) else { return nil }
            return (schedule, interval)
        }.sorted {
            if $0.1.start != $1.1.start { return $0.1.start < $1.1.start }
            if $0.1.end != $1.1.end { return $0.1.end > $1.1.end }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }

        var result: [CalendarTaskPlacement] = []
        var group: [(CalendarTaskSchedule, DateInterval)] = []
        var groupEnd = Date.distantPast

        func layoutGroup(_ entries: [(CalendarTaskSchedule, DateInterval)]) -> [CalendarTaskPlacement] {
            var columnEnds: [Date] = []
            var assigned: [(CalendarTaskSchedule, DateInterval, Int)] = []
            for (schedule, interval) in entries {
                let column: Int
                if let available = columnEnds.firstIndex(where: { $0 <= interval.start }) {
                    column = available
                    columnEnds[available] = interval.end
                } else {
                    column = columnEnds.count
                    columnEnds.append(interval.end)
                }
                assigned.append((schedule, interval, column))
            }
            return assigned.map {
                CalendarTaskPlacement(schedule: $0.0, interval: $0.1,
                                      column: $0.2, columnCount: columnEnds.count)
            }
        }

        for entry in entries {
            if !group.isEmpty && entry.1.start >= groupEnd {
                result.append(contentsOf: layoutGroup(group))
                group.removeAll(keepingCapacity: true)
            }
            group.append(entry)
            groupEnd = group.count == 1 ? entry.1.end : max(groupEnd, entry.1.end)
        }
        result.append(contentsOf: layoutGroup(group))
        return result
    }
}
