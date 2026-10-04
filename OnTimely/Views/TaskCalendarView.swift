import SwiftData
import SwiftUI

private enum TaskCalendarMode: String, CaseIterable, Identifiable {
    case month = "Month", day = "Day"
    var id: String { rawValue }
}

private struct CalendarTaskCreationRequest: Identifiable {
    let id = UUID()
    let day: Date
}

struct TaskCalendarView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.showsNotificationNotice) private var showsNotificationNotice
    @Environment(\.calendar) private var calendar
    let tasks: [TaskItem]
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    @State private var mode: TaskCalendarMode = .month
    @State private var focusedDate = Date.now
    @State private var creationRequest: CalendarTaskCreationRequest?

    private var schedules: [CalendarTaskSchedule] { tasks.compactMap { CalendarTaskSchedule(task: $0) } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    PageHeading(title: "Calendar", subtitle: "Your plans, one day at a time.")
                    Spacer(minLength: 8)
                    Button { runtime.requestCalendarImport() } label: {
                        Label("Import calendar", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                if showsNotificationNotice && runtime.permission != .allowed && runtime.permission != .unknown {
                    NotificationNotice()
                }
                navigation
                if mode == .month {
                    CalendarMonthView(month: focusedDate, schedules: schedules, now: timeline.date,
                                      onDay: openDay, onCreate: createTask, onPlan: onPlan, onRename: onRename)
                } else {
                    CalendarDayTimeline(day: focusedDate, schedules: schedules, now: timeline.date,
                                        onCreate: createTask, onPlan: onPlan, onRename: onRename)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .sheet(item: $creationRequest) { request in
            CalendarTaskCreationView(day: request.day)
        }
    }

    private var navigation: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                dateNavigation
                Spacer(minLength: 8)
                modePicker
            }
            VStack(alignment: .leading, spacing: 12) {
                dateNavigation
                modePicker
            }
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(mode == .month ? "Previous month" : "Previous day")
            Button("Today") { focusedDate = .now }.buttonStyle(QuietButtonStyle())
            Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(mode == .month ? "Next month" : "Next day")
            Text(dateTitle).font(.system(size: 16, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var modePicker: some View {
        Picker("Calendar view", selection: $mode) {
            ForEach(TaskCalendarMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 136)
    }

    private var dateTitle: String {
        if mode == .month { return focusedDate.formatted(.dateTime.month(.wide).year()) }
        return focusedDate.formatted(.dateTime.month(.wide).day().year())
    }

    private func navigate(_ offset: Int) {
        let component: Calendar.Component = mode == .month ? .month : .day
        let anchor = mode == .month ? calendar.dateInterval(of: .month, for: focusedDate)?.start ?? focusedDate : focusedDate
        if let date = calendar.date(byAdding: component, value: offset, to: anchor) { focusedDate = date }
    }

    private func openDay(_ day: Date) {
        focusedDate = day
        mode = .day
    }

    private func createTask(on day: Date) {
        focusedDate = day
        creationRequest = CalendarTaskCreationRequest(day: day)
    }
}

private struct CalendarMonthView: View {
    @Environment(\.calendar) private var calendar
    let month: Date
    let schedules: [CalendarTaskSchedule]
    let now: Date
    let onDay: (Date) -> Void
    let onCreate: (Date) -> Void
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void

    private var days: [Date] { TaskCalendarLayout.days(in: month, calendar: calendar) }
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }

    var body: some View {
        VStack(spacing: 0) {
            if schedules.isEmpty {
                Text("Right-click a day to create a task and plan it.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
            }
            HStack(spacing: 0) {
                ForEach(0..<7) { index in
                    Text(weekdaySymbols[index]).font(TaskStyle.metadata).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
            TaskSeparator()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<(days.count / 7), id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7) { weekday in
                                let day = days[week * 7 + weekday]
                                CalendarMonthDay(day: day,
                                                 inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                                 schedules: TaskCalendarLayout.schedules(schedules, on: day, calendar: calendar),
                                                 now: now, onDay: onDay, onCreate: onCreate,
                                                 onPlan: onPlan, onRename: onRename)
                                if weekday < 6 { Rectangle().fill(TaskStyle.separator).frame(width: 1) }
                            }
                        }
                        .frame(height: 188)
                        TaskSeparator()
                    }
                }
            }
            .overlay { Rectangle().strokeBorder(TaskStyle.separator, lineWidth: 1).allowsHitTesting(false) }
        }
    }
}

private struct CalendarMonthDay: View {
    @Environment(\.calendar) private var calendar
    let day: Date
    let inMonth: Bool
    let schedules: [CalendarTaskSchedule]
    let now: Date
    let onDay: (Date) -> Void
    let onCreate: (Date) -> Void
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    private var isToday: Bool { calendar.isDate(day, inSameDayAs: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { onDay(day) } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? TaskStyle.onCoral : inMonth ? TaskStyle.text : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(isToday ? TaskStyle.coral : Color.clear, in: Circle())
                }
                .frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(day.formatted(date: .complete, time: .omitted)), \(schedules.count) planned tasks")
            ForEach(schedules.prefix(3)) { schedule in
                CalendarTaskButton(task: schedule.task, onPlan: onPlan, onRename: onRename) {
                    CalendarMonthTask(schedule: schedule, day: day, now: now)
                }
            }
            if schedules.count > 3 {
                Button("+\(schedules.count - 3) more") { onDay(day) }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                    .foregroundStyle(TaskStyle.coral)
                    .accessibilityLabel("Show all \(schedules.count) plans for \(day.formatted(date: .complete, time: .omitted))")
            }
            Button { onDay(day) } label: {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHidden(true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(!inMonth || calendar.isDateInWeekend(day) ? TaskStyle.hover.opacity(0.6) : TaskStyle.content)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onCreate(day) } label: { Label("New task…", systemImage: "plus") }
        }
    }
}

private struct CalendarMonthTask: View {
    @Environment(\.calendar) private var calendar
    let schedule: CalendarTaskSchedule
    let day: Date
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(CalendarTaskAppearance.color(schedule.task, now: now)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Text(schedule.task.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if schedule.task.status == .completed {
                Image(systemName: "checkmark").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(CalendarTaskAppearance.color(schedule.task, now: now).opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private var timeLabel: String {
        if calendar.isDate(schedule.end, inSameDayAs: day) {
            return "Due \(schedule.end.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDate(schedule.start, inSameDayAs: day) {
            return "Start \(schedule.start.formatted(date: .omitted, time: .shortened))"
        }
        return "Continues"
    }
}

enum CalendarTaskAppearance {
    static func color(_ task: TaskItem, now: Date) -> Color {
        if task.status == .completed { return .secondary }
        if task.snapshot.isSnoozed(at: now) { return TaskStyle.calendarPlanned }
        switch task.snapshot.attention(at: now) {
        case .overdue, .mustStart: return .red
        case .submission, .shouldStart: return TaskStyle.coral
        case .working: return TaskStyle.calendarWorking
        case .later, .inactive: return TaskStyle.calendarPlanned
        }
    }
}

struct CalendarTaskButton<Content: View>: View {
    let task: TaskItem
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    @ViewBuilder let content: () -> Content
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: { content() }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title), \(task.status == .completed ? "completed" : "planned task")")
            .help("\(task.title) · \(task.suggestedStartDate.map(TaskFormatting.date) ?? "") → \(task.dueDate.map(TaskFormatting.date) ?? "")")
            .popover(isPresented: $presented, arrowEdge: .trailing) {
                CalendarTaskPopover(task: task, onPlan: onPlan, onRename: onRename)
            }
    }
}

private struct CalendarTaskPopover: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(task.status == .completed ? "Completed task" : "Planned task", systemImage: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close task details")
            }
            .padding(16)
            TaskSeparator()
            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                ScrollView {
                    PlannedTaskDetails(task: task, now: timeline.date,
                                       onPlan: { dismiss(); onPlan($0) },
                                       onRename: { dismiss(); onRename($0) }, initiallyExpanded: true)
                        .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
        .frame(width: 440, height: 420)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onChange(of: task.status) { _, status in if status == .inbox { dismiss() } }
        .onExitCommand { dismiss() }
    }
}
