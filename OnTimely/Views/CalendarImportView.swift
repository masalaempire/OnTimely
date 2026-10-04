import SwiftData
import SwiftUI

struct CalendarImportView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CalendarSubscription.createdAt) private var subscriptions: [CalendarSubscription]
    @State private var link = ""
    @State private var timeZoneIdentifier = "Asia/Shanghai"
    @State private var preview: CalendarFeedPreview?
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadingTask: Task<Void, Never>?
    @State private var disconnectingCalendar: CalendarSubscription?

    private var busy: Bool { isLoading || runtime.calendarImports?.isRefreshing == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(title: "Import calendar", subtitle: "Connect ManageBac and let your tasks arrive with reminders.")
                .padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !subscriptions.isEmpty { connectedCalendars }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Calendar subscription link").font(.system(size: 13, weight: .medium))
                        SecureField("webcal://…", text: $link).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("ManageBac calendar subscription link")
                            .disabled(isLoading)
                        Picker("School time zone", selection: $timeZoneIdentifier) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { zone in
                                Text(zone.replacingOccurrences(of: "_", with: " ")).tag(zone)
                            }
                        }
                        .disabled(isLoading)
                        Text("Reminder times follow your school’s time zone. Your subscription link is saved privately on this Mac.")
                            .font(TaskStyle.metadata).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let preview { previewContent(preview) }
                    else { reminderExplanation }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(TaskStyle.metadata).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            TaskSeparator()
            HStack(spacing: 12) {
                Button("Close") { loadingTask?.cancel(); dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                    .disabled(isLoading && preview != nil)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                if let preview {
                    Button("Back") { self.preview = nil; errorMessage = nil }
                        .buttonStyle(QuietButtonStyle()).disabled(busy)
                    Button(importLabel(preview)) { loadingTask = Task { await connect(preview) } }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(busy)
                } else {
                    Button("Preview tasks") { loadingTask = Task { await loadPreview() } }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                        .disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 620)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .onChange(of: link) { _, _ in preview = nil; errorMessage = nil }
        .onChange(of: timeZoneIdentifier) { _, _ in preview = nil; errorMessage = nil }
        .onDisappear { loadingTask?.cancel() }
        .alert("Are you sure?", isPresented: Binding(
            get: { disconnectingCalendar != nil },
            set: { if !$0 { disconnectingCalendar = nil } }
        ), presenting: disconnectingCalendar) { subscription in
            Button("Cancel", role: .cancel) { disconnectingCalendar = nil }
            Button("Disconnect", role: .destructive) {
                do { try runtime.calendarImports?.disconnect(subscription) }
                catch { errorMessage = "This calendar couldn’t be disconnected. Try again." }
            }
            .disabled(busy)
        } message: { subscription in
            Text("Disconnect “\(subscription.name)”? This calendar will stop syncing. Your imported tasks will be kept.")
        }
    }

    private var connectedCalendars: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected calendars").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Refresh") { Task { await runtime.calendarImports?.refreshSubscriptions(force: true) } }
                    .buttonStyle(.link).disabled(busy)
            }
            ForEach(subscriptions) { subscription in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subscription.name).font(.system(size: 13, weight: .medium))
                            Text(subscription.host).font(TaskStyle.metadata).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") {
                            disconnectingCalendar = subscription
                        }
                        .buttonStyle(.link).disabled(busy)
                    }
                    if let error = subscription.lastSyncError {
                        Text(error).font(TaskStyle.metadata).foregroundStyle(.red)
                    } else if let synced = subscription.lastSyncedAt {
                        Text("Updated \(synced.formatted(date: .abbreviated, time: .shortened))")
                            .font(TaskStyle.metadata).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Calendars refresh every 15 minutes while OnTimely is running. Disconnecting keeps your imported tasks.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TaskSeparator()
        }
    }

    private var reminderExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automatic reminders").font(.system(size: 13, weight: .semibold))
            Text("Due by 4:20 p.m.: start at 7 p.m. the previous day; latest start at 10 p.m.")
            Text("Due later: start at 6:50 p.m. that day; latest start at 9 p.m.")
            Text("Earlier evening deadlines use reminders 2 hours and 1 hour before due. You can edit any task afterward.")
            Text("Past-due assignments are skipped. The actual ManageBac deadline is kept.")
        }
        .font(TaskStyle.metadata).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func previewContent(_ preview: CalendarFeedPreview) -> some View {
        let upcoming = preview.upcoming(at: .now)
        let pastDue = preview.pastDueCount(at: .now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(upcoming.count) upcoming \(upcoming.count == 1 ? "task" : "tasks")")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Select all") { selectedIDs = Set(upcoming.map(\.id)) }.buttonStyle(.link)
                Button("Clear") { selectedIDs.removeAll() }.buttonStyle(.link)
            }
            if upcoming.isEmpty {
                Text("No upcoming tasks yet. Connect this calendar to import new assignments automatically.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            ForEach(upcoming) { event in
                Toggle(isOn: Binding(get: { selectedIDs.contains(event.id) }, set: { selected in
                    if selected { selectedIDs.insert(event.id) } else { selectedIDs.remove(event.id) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.system(size: 13, weight: .medium))
                        if let due = event.dueDate {
                            Text("Due \(schoolDate(due, zone: preview.timeZoneIdentifier))")
                                .font(TaskStyle.metadata).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox).disabled(isLoading)
            }
            if pastDue > 0 {
                Text("\(pastDue) past-due \(pastDue == 1 ? "assignment" : "assignments") skipped.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            if preview.feed.excludedEntryCount > 0 {
                Text("\(preview.feed.excludedEntryCount) all-day, repeating, or incomplete calendar entries skipped.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
            Text("New upcoming assignments will import automatically. Unchecked entries stay excluded.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
            reminderExplanation
        }
    }

    private func importLabel(_ preview: CalendarFeedPreview) -> String {
        let count = preview.upcoming(at: .now).filter { selectedIDs.contains($0.id) }.count
        return count == 0 ? "Connect calendar" : "Import \(count) \(count == 1 ? "task" : "tasks")"
    }

    private func schoolDate(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: zone)
        return formatter.string(from: date)
    }

    private func loadPreview() async {
        guard let service = runtime.calendarImports else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await service.preview(link: link, timeZoneIdentifier: timeZoneIdentifier)
            guard !Task.isCancelled else { return }
            selectedIDs = Set(result.upcoming(at: .now).map(\.id))
            preview = result
        } catch is CancellationError { }
        catch { errorMessage = (error as? CalendarFeedError)?.errorDescription ?? "The calendar couldn’t be opened. Try again." }
    }

    private func connect(_ preview: CalendarFeedPreview) async {
        guard let service = runtime.calendarImports else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await service.subscribe(preview, selectedEventIDs: selectedIDs)
            if await runtime.notifications.permission() == .notRequested {
                await runtime.enableNotifications()
            }
            dismiss()
        } catch { errorMessage = (error as? CalendarFeedError)?.errorDescription ?? "Your calendar couldn’t be saved. Try again." }
    }
}
