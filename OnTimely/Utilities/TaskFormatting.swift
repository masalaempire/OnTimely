import Foundation

enum ActiveTaskGroup: String, CaseIterable, Identifiable {
    case needsAttention = "Needs attention", working = "Working", later = "Later"
    var id: String { rawValue }
}

enum TaskFormatting {
    static func group(_ task: TaskSnapshot, now: Date) -> ActiveTaskGroup {
        switch task.attention(at: now) {
        case .overdue, .submission, .mustStart, .shouldStart: .needsAttention
        case .working: .working
        case .later, .inactive: .later
        }
    }

    static func sortedActive(_ tasks: [TaskItem], now: Date) -> [TaskItem] {
        tasks.sorted {
            let left = $0.snapshot.attention(at: now), right = $1.snapshot.attention(at: now)
            if left != right { return left.rawValue < right.rawValue }
            let leftDue = $0.dueDate ?? .distantFuture, rightDue = $1.dueDate ?? .distantFuture
            if leftDue != rightDue { return leftDue < rightDue }
            return $0.createdAt < $1.createdAt
        }
    }

    static func date(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today, \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if abs(seconds) < 60 { return "less than 1m" }
        let minutes = max(1, Int(ceil(abs(seconds) / 60)))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func status(_ task: TaskSnapshot, now: Date) -> String {
        switch task.attention(at: now) {
        case .overdue: return "Past due by \(duration(task.dueDate!.timeIntervalSince(now))) · Finish and submit"
        case .submission: return "Due in \(duration(task.dueDate!.timeIntervalSince(now))) · Finish and submit"
        case .mustStart: return "Latest start reached · Confirm you’re working"
        case .shouldStart:
            return "You should start now · Latest start in \(duration(task.latestSafeStartDate!.timeIntervalSince(now)))"
        case .working: return task.hasConfirmedLatestStart ? "Working · Latest start confirmed" : "Working · We’ll check again at latest start"
        case .later: return "Start around \(task.suggestedStartDate.map(date) ?? "later")"
        case .inactive: return ""
        }
    }
}
