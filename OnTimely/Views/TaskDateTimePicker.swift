import SwiftUI

struct TaskDateTimePicker: View {
    let label: String
    @Binding var selection: Date
    @State private var calendarPresented = false
    @State private var timePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(TaskStyle.metadata).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { calendarPresented = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        Text(dateLabel)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("\(label) date")
                .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
                .popover(isPresented: $calendarPresented, arrowEdge: .bottom) {
                    TaskCalendarPopover(selection: $selection) { calendarPresented = false }
                }
                Button { timePresented = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text(TaskTimeText.format(selection)).monospacedDigit()
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("\(label) time")
                .accessibilityValue(TaskTimeText.format(selection))
                .popover(isPresented: $timePresented, arrowEdge: .bottom) {
                    TaskTimePopover(selection: $selection) { timePresented = false }
                }
            }
        }
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selection) { return "Today" }
        if calendar.isDateInTomorrow(selection) { return "Tomorrow" }
        if calendar.component(.year, from: selection) != calendar.component(.year, from: .now) {
            return selection.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return selection.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

private struct TaskCalendarPopover: View {
    @Binding var selection: Date
    let close: () -> Void
    @State private var month: Date
    private var calendar: Calendar { Calendar.current }

    init(selection: Binding<Date>, close: @escaping () -> Void) {
        _selection = selection
        self.close = close
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 20, height: 20) }
                    .buttonStyle(.plain).accessibilityLabel("Previous month")
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 20, height: 20) }
                    .buttonStyle(.plain).accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7) { index in
                    Text(weekdaySymbols[index]).font(TaskStyle.metadata).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.bottom, 4).accessibilityHidden(true)
                }
                ForEach(0..<42) { index in
                    if let day = day(at: index) {
                        CalendarDayButton(day: day, selected: calendar.isDate(day, inSameDayAs: selection),
                                          inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month)) {
                            selectDay(day)
                        }
                    }
                }
            }
            TaskSeparator()
            HStack(spacing: 8) {
                Button("Today") { selectDay(.now) }.buttonStyle(QuietButtonStyle())
                Button("Tomorrow") {
                    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) { selectDay(tomorrow) }
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
            }
            Text("Your selected time stays the same.").font(TaskStyle.metadata).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16).frame(width: 316)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onExitCommand(perform: close)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    private func day(at index: Int) -> Date? {
        let leadingDays = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: index - leadingDays, to: month)
    }

    private func changeMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next }
    }

    private func selectDay(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        guard let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                       second: time.second ?? 0, of: day) else { return }
        selection = date
        close()
    }
}

private struct CalendarDayButton: View {
    let day: Date
    let selected: Bool
    let inMonth: Bool
    let action: () -> Void
    @State private var hovering = false
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 13, weight: selected || isToday ? .semibold : .regular))
                .frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(selected ? TaskStyle.onCoral : inMonth ? TaskStyle.text : Color.secondary)
                .background(selected ? TaskStyle.coral : hovering ? TaskStyle.hover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isToday && !selected { RoundedRectangle(cornerRadius: 6).strokeBorder(TaskStyle.coral, lineWidth: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private enum TaskTimeText {
    static func format(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return format(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    static func format(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

private struct TaskTimePopover: View {
    @Binding var selection: Date
    let close: () -> Void
    @State private var timeText: String
    @FocusState private var textFocused: Bool

    init(selection: Binding<Date>, close: @escaping () -> Void) {
        _selection = selection
        self.close = close
        _timeText = State(initialValue: TaskTimeText.format(selection.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a time").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                TextField("HH:MM", text: $timeText)
                    .textFieldStyle(.roundedBorder).font(.system(size: 20, weight: .medium).monospacedDigit())
                    .multilineTextAlignment(.center).frame(width: 100)
                    .focused($textFocused).onSubmit(apply)
                    .accessibilityLabel("Time in 24-hour format")
                    .accessibilityHint("For example, 09:30 or 18:45.")
                Text("24-hour time").font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                TimeColumn(label: "Hour", range: 0...23, selected: TaskTimeText.parse(timeText)?.hour) { hour in
                    let minute = TaskTimeText.parse(timeText)?.minute ?? Calendar.current.component(.minute, from: selection)
                    timeText = TaskTimeText.format(hour: hour, minute: minute)
                }
                TimeColumn(label: "Minute", range: 0...59, selected: TaskTimeText.parse(timeText)?.minute) { minute in
                    let hour = TaskTimeText.parse(timeText)?.hour ?? Calendar.current.component(.hour, from: selection)
                    timeText = TaskTimeText.format(hour: hour, minute: minute)
                }
            }
            HStack(spacing: 8) {
                ForEach([0, 15, 30, 45], id: \.self) { minute in
                    Button(String(format: ":%02d", minute)) {
                        let hour = TaskTimeText.parse(timeText)?.hour ?? Calendar.current.component(.hour, from: selection)
                        timeText = TaskTimeText.format(hour: hour, minute: minute)
                    }
                    .buttonStyle(QuietButtonStyle()).accessibilityLabel("Set minutes to \(minute)")
                }
            }
            if let error = timeError {
                Text(error).font(TaskStyle.metadata).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: close).buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done", action: apply).buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(resolvedDate == nil)
            }
        }
        .padding(16).frame(width: 280)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onAppear { textFocused = true }
        .onExitCommand(perform: close)
    }

    private var resolvedDate: Date? {
        guard let time = TaskTimeText.parse(timeText),
              let date = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: selection),
              Calendar.current.isDate(date, inSameDayAs: selection),
              Calendar.current.component(.hour, from: date) == time.hour,
              Calendar.current.component(.minute, from: date) == time.minute else { return nil }
        return date
    }

    private var timeError: String? {
        if TaskTimeText.parse(timeText) == nil { return "Enter a time from 00:00 to 23:59, such as 09:30." }
        if resolvedDate == nil { return "That time isn’t available on this date. Choose another time." }
        return nil
    }

    private func apply() {
        guard let date = resolvedDate else { return }
        selection = date
        close()
    }
}

private struct TimeColumn: View {
    let label: String
    let range: ClosedRange<Int>
    let selected: Int?
    let choose: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(label).font(TaskStyle.metadata).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(range, id: \.self) { value in
                            Button { choose(value) } label: {
                                Text(String(format: "%02d", value)).font(.system(size: 14).monospacedDigit())
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(selected == value ? TaskStyle.coral : TaskStyle.text)
                                    .background(selected == value ? TaskStyle.selection : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(value)
                            .accessibilityLabel("\(label) \(value)")
                            .accessibilityAddTraits(selected == value ? [.isSelected] : [])
                        }
                    }
                    .padding(4)
                }
                .frame(height: 160)
                .background(TaskStyle.hover, in: RoundedRectangle(cornerRadius: 6))
                .task(id: selected) {
                    await Task.yield()
                    if !Task.isCancelled, let selected { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
