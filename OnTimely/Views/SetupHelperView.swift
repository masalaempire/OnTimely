import SwiftUI

struct AppLaunchView: View {
    @ObservedObject var updates: AppUpdater
    @AppStorage("hasShownSetupHelper") private var hasShownSetup = false
    @State private var showingSetup = false
    @State private var prepared = false

    var body: some View {
        MainView()
            .sheet(isPresented: $showingSetup, onDismiss: { updates.start() }) {
                SetupHelperView(updates: updates)
            }
            .task {
                guard !prepared else { return }
                prepared = true
                if hasShownSetup {
                    updates.start()
                } else {
                    // Keep this independent of the version, even if the user quits during setup.
                    hasShownSetup = true
                    showingSetup = true
                }
            }
    }
}

struct SetupHelperView: View {
    @ObservedObject var updates: AppUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var customizeDefaults = false
    @State private var interval: Int
    @State private var buffer: Int
    @State private var lead: Int
    @State private var automaticChecks: Bool
    @State private var automaticInstallation: Bool

    init(updates: AppUpdater) {
        self.updates = updates
        _interval = State(initialValue: ReminderDefaults.intervalMinutes)
        _buffer = State(initialValue: ReminderDefaults.bufferMinutes)
        _lead = State(initialValue: ReminderDefaults.submissionLeadMinutes)
        _automaticChecks = State(initialValue: updates.automaticallyChecksForUpdates)
        _automaticInstallation = State(initialValue: updates.automaticallyInstallsUpdates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if step == 0 { reminderStep }
                    else { updatesStep }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
            }
            TaskSeparator()
            footer
        }
        .font(.system(size: 13))
        .frame(width: 520, height: 460)
        .foregroundStyle(TaskStyle.text).background(TaskStyle.content).tint(TaskStyle.coral)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OnTimely").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 12) {
                Text("Step \(step + 1) of 2").font(TaskStyle.metadata).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(0..<2) { index in
                        Capsule().fill(index <= step ? TaskStyle.coral : TaskStyle.separator)
                            .frame(width: 24, height: 3)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
                Text("A quick setup").font(TaskStyle.metadata).foregroundStyle(.secondary)
            }
        }
        .padding(24).padding(.bottom, -8)
    }

    private var reminderStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Welcome to OnTimely", subtitle: "A little room around your deadlines.")
            VStack(spacing: 12) {
                TimingDetail(label: "Repeat reminders every", value: "\(interval) minutes")
                TimingDetail(label: "Safety buffer", value: "\(buffer) minutes")
                TimingDetail(label: "Submission reminders", value: "\(lead) minutes before due")
            }
            .padding(16)
            .background(TaskStyle.sidebar, in: RoundedRectangle(cornerRadius: 6))
            Toggle("Customize reminder defaults", isOn: $customizeDefaults)
                .onChange(of: customizeDefaults) { _, enabled in
                    if !enabled {
                        interval = ReminderDefaults.intervalMinutes
                        buffer = ReminderDefaults.bufferMinutes
                        lead = ReminderDefaults.submissionLeadMinutes
                    }
                }
            if customizeDefaults {
                ReminderDefaultsFields(interval: $interval, buffer: $buffer, lead: $lead)
            }
            Text("These defaults apply to newly planned tasks. You can adjust each task when you plan it.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updatesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Stay up to date", subtitle: "Choose how OnTimely keeps itself updated.")
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Automatically check for updates", isOn: $automaticChecks)
                Text("OnTimely will check periodically for new versions.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Automatically download and install updates", isOn: $automaticInstallation)
                    .disabled(!automaticChecks)
                Text("Updates download in the background and install when you quit the app.")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TaskStyle.sidebar, in: RoundedRectangle(cornerRadius: 6))
            Text("You can always check manually from OnTimely → Check for Updates… and change these choices in Settings.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You can change all of this later in Settings.")
                .font(TaskStyle.metadata).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Use current settings") { dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                if step > 0 {
                    Button("Back") { step = 0 }.buttonStyle(QuietButtonStyle())
                }
                Button(step == 0 ? "Continue" : "Get started") {
                    if step == 0 { step = 1 }
                    else { finish() }
                }
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func finish() {
        if customizeDefaults {
            UserDefaults.standard.set(interval, forKey: "reminderIntervalMinutes")
            UserDefaults.standard.set(buffer, forKey: "safetyBufferMinutes")
            UserDefaults.standard.set(lead, forKey: "submissionLeadMinutes")
        }
        updates.setAutomaticChecks(automaticChecks)
        updates.setAutomaticInstallation(automaticInstallation)
        dismiss()
    }
}

struct ReminderDefaultsFields: View {
    @Binding var interval: Int
    @Binding var buffer: Int
    @Binding var lead: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Repeat reminders every", selection: $interval) {
                ForEach(Array(Set([5, 10, 15, 30, 60, interval])).sorted(), id: \.self) {
                    Text("\($0) minutes").tag($0)
                }
            }
            Stepper("Safety buffer: \(buffer) minutes", value: $buffer, in: 0...max(180, buffer), step: 5)
            Picker("Submission reminders before due", selection: $lead) {
                ForEach(Array(Set([5, 15, 30, 60, lead])).sorted(), id: \.self) {
                    Text("\($0) minutes").tag($0)
                }
            }
        }
    }
}
