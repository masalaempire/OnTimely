import SwiftUI

struct SettingsView: View {
    @ObservedObject var updates: AppUpdater
    @Environment(AppRuntime.self) private var runtime
    @AppStorage("reminderIntervalMinutes") private var interval = 10
    @AppStorage("safetyBufferMinutes") private var buffer = 30
    @AppStorage("submissionLeadMinutes") private var lead = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Settings", subtitle: "A little room around your deadlines.")
                VStack(alignment: .leading, spacing: 16) {
                    Text("New task defaults").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    ReminderDefaultsFields(interval: $interval, buffer: $buffer, lead: $lead)
                    Text("Defaults apply to newly planned tasks. Adjust reminders on a task’s review to change its plan.")
                        .font(TaskStyle.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaskSeparator()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Notifications").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        Label(permissionLabel, systemImage: runtime.permission == .allowed ? "bell" : "bell.slash")
                        Spacer(minLength: 8)
                        if runtime.permission == .allowed || runtime.permission == .denied {
                            Button("Open Settings") { runtime.openNotificationSettings() }.buttonStyle(QuietButtonStyle())
                                .accessibilityLabel("Open macOS notification settings")
                        } else {
                            Button("Enable") { Task { await runtime.enableNotifications() } }.buttonStyle(QuietButtonStyle())
                                .disabled(runtime.isEnablingNotifications)
                        }
                    }
                    Text("Close the window to keep reminders running. Quitting the app stops refilling reminders; already scheduled notifications can still arrive.")
                        .font(TaskStyle.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaskSeparator()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Updates").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(updates.version).font(TaskStyle.metadata).foregroundStyle(.secondary)
                    }
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticChecks($0) }))
                    Toggle("Automatically download and install updates", isOn: Binding(
                        get: { updates.automaticallyInstallsUpdates },
                        set: { updates.setAutomaticInstallation($0) }))
                        .disabled(!updates.automaticallyChecksForUpdates)
                    HStack {
                        Text("Automatic updates are installed when you quit the app.")
                            .font(TaskStyle.metadata).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        CheckForUpdatesButton(updates: updates).buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .font(.system(size: 13))
            .padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 480)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .task { await runtime.refresh() }
    }

    private var permissionLabel: String {
        switch runtime.permission {
        case .allowed: "Notifications enabled"
        case .denied: "Notifications disabled"
        case .notRequested: "Notifications haven’t been enabled"
        case .unknown: "Checking notifications…"
        }
    }
}
