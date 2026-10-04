import SwiftUI

struct CalendarDayTimeline: View {
    @Environment(\.calendar) private var calendar
    let day: Date
    let schedules: [CalendarTaskSchedule]
    let now: Date
    let onCreate: (Date) -> Void
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void
    @State private var jumpToNow = UUID()
    @State private var agendaExpanded = false

    private var interval: DateInterval {
        calendar.dateInterval(of: .day, for: day)
            ?? DateInterval(start: calendar.startOfDay(for: day), duration: 24 * 60 * 60)
    }
    private var daySchedules: [CalendarTaskSchedule] {
        TaskCalendarLayout.schedules(schedules, on: day, calendar: calendar)
    }
    private var placements: [CalendarTaskPlacement] { TaskCalendarLayout.placements(daySchedules, in: interval) }
    private var isToday: Bool { calendar.isDate(day, inSameDayAs: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(day.formatted(.dateTime.weekday(.wide))).font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !daySchedules.isEmpty {
                    Button {
                        agendaExpanded.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Text("\(daySchedules.count) \(daySchedules.count == 1 ? "plan" : "plans")")
                            Image(systemName: agendaExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.plain).font(TaskStyle.metadata).foregroundStyle(.secondary)
                    .accessibilityLabel(agendaExpanded ? "Hide day’s task list" : "Show day’s task list")
                }
                if isToday {
                    Button("Now") { jumpToNow = UUID() }.buttonStyle(QuietButtonStyle())
                        .help("Scroll to the current time")
                }
            }
            if daySchedules.isEmpty {
                Text("No plans for this day. Right-click to create a task and plan it.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            } else if agendaExpanded {
                agenda
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        CalendarTimelineCanvas(interval: interval, placements: placements, now: now,
                                               showsNow: isToday, onPlan: onPlan, onRename: onRename)
                            .frame(width: canvasWidth(viewport: geometry.size.width),
                                   height: CGFloat(interval.duration / 3600) * CalendarTimelineCanvas.hourHeight + 32)
                    }
                    .task(id: interval.start) {
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scroll(to: initialScrollDate, proxy: proxy)
                    }
                    .onChange(of: jumpToNow) { _, _ in scroll(to: now.addingTimeInterval(-3600), proxy: proxy) }
                }
                .overlay { Rectangle().strokeBorder(TaskStyle.separator, lineWidth: 1).allowsHitTesting(false) }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { onCreate(day) } label: { Label("New task…", systemImage: "plus") }
        }
    }

    private var agenda: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(daySchedules) { schedule in
                    CalendarTaskButton(task: schedule.task, onPlan: onPlan, onRename: onRename) {
                        HStack(spacing: 10) {
                            Circle().fill(CalendarTaskAppearance.color(schedule.task, now: now)).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(schedule.task.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(CalendarTimelineTask.timeRange(schedule))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if schedule.task.status == .completed {
                                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                            }
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(TaskStyle.hover, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .frame(height: min(CGFloat(daySchedules.count) * 52, 156))
    }

    private func canvasWidth(viewport: CGFloat) -> CGFloat {
        let columns = placements.map(\.columnCount).max() ?? 1
        return max(viewport, CalendarTimelineCanvas.timeGutter + CGFloat(columns) * 104 + 12)
    }

    private var initialScrollDate: Date {
        if isToday { return now.addingTimeInterval(-3600) }
        if let first = daySchedules.first, let clipped = first.clipped(to: interval) {
            return clipped.start.addingTimeInterval(-1800)
        }
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? interval.start
    }

    private func scroll(to date: Date, proxy: ScrollViewProxy) {
        let hours = Int(ceil(interval.duration / 3600))
        let index = min(max(0, Int(date.timeIntervalSince(interval.start) / 3600)), max(0, hours - 1))
        proxy.scrollTo("calendar-hour-\(index)", anchor: .top)
    }
}

private struct CalendarTimelineCanvas: View {
    static let hourHeight: CGFloat = 84
    static let timeGutter: CGFloat = 68
    private let inset: CGFloat = 16
    let interval: DateInterval
    let placements: [CalendarTaskPlacement]
    let now: Date
    let showsNow: Bool
    let onPlan: (TaskItem) -> Void
    let onRename: (TaskItem) -> Void

    /// Elapsed hours preserve the actual length of days with daylight saving changes.
    private var hourCount: Int { Int(ceil(interval.duration / 3600)) }
    private var hourMarks: [Date] {
        (0...hourCount).map { min(interval.start.addingTimeInterval(Double($0) * 3600), interval.end) }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // These anchors have real layout positions, independent of the task overlays.
                VStack(spacing: 0) {
                    ForEach(0..<hourCount, id: \.self) { hour in
                        Color.clear
                            .frame(height: CGFloat(min(3600, interval.duration - Double(hour) * 3600) / 3600) * Self.hourHeight)
                            .id("calendar-hour-\(hour)")
                    }
                }
                .padding(.top, inset).allowsHitTesting(false).accessibilityHidden(true)

                ForEach(Array(hourMarks.enumerated()), id: \.offset) { _, date in
                    hourLine(date, width: geometry.size.width)
                        .offset(y: position(date) - 10)
                }
                ForEach(placements) { placement in
                    taskBlock(placement, width: geometry.size.width)
                }
                if showsNow && now >= interval.start && now < interval.end {
                    currentTimeLine(width: geometry.size.width)
                        .offset(y: position(now) - 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func hourLine(_ date: Date, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: Self.timeGutter - 10, alignment: .trailing)
                .padding(.trailing, 10)
            Rectangle().fill(TaskStyle.separator).frame(height: 1)
        }
        .frame(width: width, height: 20)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func taskBlock(_ placement: CalendarTaskPlacement, width: CGFloat) -> some View {
        let available = max(1, width - Self.timeGutter - 12)
        let columnWidth = available / CGFloat(placement.columnCount)
        let blockHeight = max(2, CGFloat(placement.interval.duration / 3600) * Self.hourHeight)
        return CalendarTaskButton(task: placement.schedule.task, onPlan: onPlan, onRename: onRename) {
            CalendarTimelineTask(schedule: placement.schedule, clipped: placement.interval,
                                 height: blockHeight, now: now)
                .frame(width: max(1, columnWidth - 4), height: blockHeight)
        }
        .offset(x: Self.timeGutter + CGFloat(placement.column) * columnWidth + 2,
                y: position(placement.interval.start))
    }

    private func currentTimeLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                .background(.red, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: Self.timeGutter, alignment: .trailing)
            Rectangle().fill(.red).frame(height: 2)
        }
        .frame(width: width, height: 20)
        .allowsHitTesting(false)
        .accessibilityLabel("Current time: \(now.formatted(date: .omitted, time: .shortened))")
    }

    private func position(_ date: Date) -> CGFloat {
        inset + CGFloat(date.timeIntervalSince(interval.start) / 3600) * Self.hourHeight
    }
}

private struct CalendarTimelineTask: View {
    let schedule: CalendarTaskSchedule
    let clipped: DateInterval
    let height: CGFloat
    let now: Date
    private var color: Color { CalendarTaskAppearance.color(schedule.task, now: now) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14))
                if now > clipped.start {
                    Rectangle().fill(color.opacity(0.08))
                        .frame(height: height * CGFloat(min(1, now.timeIntervalSince(clipped.start) / clipped.duration)))
                }
                Rectangle().fill(color).frame(width: 3)
                if height >= 18 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.task.title).font(.system(size: 12, weight: .semibold))
                            .lineLimit(height >= 70 ? 2 : 1)
                        if height >= 52 {
                            Text(Self.timeRange(schedule)).font(.system(size: 10)).lineLimit(2)
                        }
                        if height >= 96 {
                            Text("\(TaskFormatting.duration(schedule.end.timeIntervalSince(schedule.start))) planned window")
                                .font(.system(size: 10)).lineLimit(1)
                            if schedule.task.status == .completed {
                                Label("Completed", systemImage: "checkmark.circle").font(.system(size: 10))
                            } else if schedule.task.snapshot.isSnoozed(at: now) {
                                Label("Snoozed", systemImage: "bell.slash").font(.system(size: 10))
                            } else if schedule.task.hasConfirmedWorking {
                                Label("Working", systemImage: "play.circle").font(.system(size: 10))
                            }
                        }
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, height < 30 ? 1 : 6)
                    .frame(width: geometry.size.width, alignment: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.45), lineWidth: 1) }
            .contentShape(Rectangle())
        }
    }

    static func timeRange(_ schedule: CalendarTaskSchedule) -> String {
        if Calendar.current.isDate(schedule.start, inSameDayAs: schedule.end) {
            return "\(schedule.start.formatted(date: .omitted, time: .shortened)) – \(schedule.end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(TaskFormatting.date(schedule.start)) → \(TaskFormatting.date(schedule.end))"
    }
}
