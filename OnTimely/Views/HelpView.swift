import SwiftUI

struct HelpCommands: Commands {
    let runtime: AppRuntime

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("OnTimely Help") { runtime.showHelp() }
                .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}

struct HelpView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        PageHeading(title: "Help", subtitle: "A guide to every part of OnTimely.")
                        Text("Capture a task in Inbox, plan it into Active, and mark it Done after finishing and submitting. Calendar brings your plans together, and Notes gives your ideas a place to stay.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        contents(proxy: proxy)
                        TaskSeparator()
                        ForEach(HelpGuide.chapters) { chapter in
                            HelpChapterView(chapter: chapter).id(chapter.id)
                            TaskSeparator()
                        }
                        HelpPermissionsSection().id("permissions")
                        TaskSeparator()
                        HelpSettingsSection().id("settings")
                    }
                    .frame(maxWidth: 780, alignment: .leading)
                    .padding(.horizontal, geometry.size.width < 620 ? 24 : 32)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .foregroundStyle(TaskStyle.text)
        .background(TaskStyle.content)
        .tint(TaskStyle.coral)
    }

    private func contents(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jump to a chapter").font(TaskStyle.metadata).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                ForEach(HelpGuide.chapters) { chapter in
                    contentsButton(chapter.section.rawValue, symbol: chapter.section.symbol,
                                   id: chapter.id, proxy: proxy)
                }
                contentsButton("Permissions", symbol: "lock.shield", id: "permissions", proxy: proxy)
                contentsButton("Settings & shortcuts", symbol: "gearshape", id: "settings", proxy: proxy)
            }
        }
    }

    private func contentsButton(_ title: String, symbol: String, id: String,
                                proxy: ScrollViewProxy) -> some View {
        Button {
            if reduceMotion { proxy.scrollTo(id, anchor: .top) }
            else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(TaskStyle.coral)
                Text(title).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("Jump to \(title)")
    }
}

private struct HelpChapterView: View {
    let chapter: HelpChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpSectionHeading(title: "\(chapter.number). \(chapter.section.rawValue)",
                               symbol: chapter.section.symbol, summary: chapter.summary)
            ForEach(chapter.features) { feature in HelpFeatureView(feature: feature) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HelpSectionHeading: View {
    let title: String
    let symbol: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(TaskStyle.coral).frame(width: 24).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 19, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(summary).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HelpFeatureView: View {
    let feature: HelpFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(feature.title).font(.system(size: 14, weight: .medium)).accessibilityAddTraits(.isHeader)
            Text(feature.details).font(.system(size: 13)).foregroundStyle(.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HelpPermissionsSection: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpSectionHeading(title: "Permissions", symbol: "lock.shield",
                               summary: "Give reminders and calendar refreshes the access they need.")
            HelpFeatureView(feature: HelpFeature("Allow notifications",
                "OnTimely needs notification access to deliver suggested-start, latest-start and submission reminders. Choose Allow when macOS asks. If you previously declined, open System Settings → Notifications → OnTimely and turn on Allow notifications. You can also choose how banners and sounds appear there."))
            VStack(alignment: .leading, spacing: 10) {
                Label(notificationStatus, systemImage: runtime.permission == .allowed ? "bell" : "bell.slash")
                    .font(TaskStyle.metadata).foregroundStyle(.secondary)
                if runtime.permission == .notRequested || runtime.permission == .unknown {
                    Button("Enable notifications") { Task { await runtime.enableNotifications() } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(runtime.isEnablingNotifications || runtime.permission == .unknown)
                } else {
                    Button("Open notification settings") { runtime.openNotificationSettings() }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            HelpFeatureView(feature: HelpFeature("Keep reminders running",
                "Closing the OnTimely window keeps the app running and reminders scheduled. Quitting stops OnTimely from refilling reminders, although already scheduled notifications can still arrive. If reminders are quiet, check notification permission and your Mac’s Focus settings."))
            HelpFeatureView(feature: HelpFeature("Allow Keychain access for webcal",
                "Your calendar subscription link is private and is stored in macOS Keychain on this Mac. OnTimely needs to read it to refresh your calendar. macOS may ask for Keychain access when you connect or refresh a calendar, or after an app update. When the prompt names OnTimely, enter your Mac login password if asked and choose Allow or Allow Once. Choose Always Allow if you want future calendar refreshes without repeated access prompts."))
            HelpFeatureView(feature: HelpFeature("If you deny Keychain access",
                "OnTimely cannot refresh that calendar until access is allowed. Your existing imported tasks remain available. Open Calendar → Import calendar → Refresh to try again, then allow access when macOS asks. Keep your subscription link private: anyone with the link may be able to read your calendar."))
            VStack(alignment: .leading, spacing: 8) {
                Link("Apple’s notification settings guide",
                     destination: URL(string: "https://support.apple.com/guide/mac-help/mchl205da693/mac")!)
                Link("Apple’s Keychain access guide",
                     destination: URL(string: "https://support.apple.com/guide/keychain-access/kyca1243/mac")!)
            }
            .font(TaskStyle.metadata)
        }
    }

    private var notificationStatus: String {
        switch runtime.permission {
        case .allowed: "Notifications enabled"
        case .denied: "Notifications disabled"
        case .notRequested: "Notifications haven’t been enabled"
        case .unknown: "Checking notification permission…"
        }
    }
}

private struct HelpSettingsSection: View {
    private let shortcuts: [(action: String, keys: String)] = [
        ("Inbox", "⌘1"), ("Active", "⌘2"), ("Done", "⌘3"),
        ("Calendar", "⌘4"), ("Notes", "⌘5"),
        ("Add task · New note while in Notes", "⌘N"),
        ("Settings", "⌘,"), ("Help", "⌘⇧/"),
        ("Save the current note", "⌘S"),
        ("Bold · Italic · Underline in Notes", "⌘B · ⌘I · ⌘U"),
        ("Add a task from the quick entry field", "Return"),
        ("Close quick entry or cancel a dialog", "Escape")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HelpSectionHeading(title: "Settings & shortcuts", symbol: "gearshape",
                               summary: "Make OnTimely fit the way you work.")
            HelpFeatureView(feature: HelpFeature("First launch setup",
                "The setup helper appears the first time you open OnTimely. Choose your reminder defaults and update preferences, or use the current settings to continue. You can change these choices later in Settings."))
            HelpFeatureView(feature: HelpFeature("New task defaults",
                "Settings lets you set the repeat reminder interval, safety buffer and how long before the deadline submission reminders begin. Defaults apply to newly planned tasks. To change an existing task, open its plan and adjust its reminders."))
            HelpFeatureView(feature: HelpFeature("App updates",
                "Turn automatic update checks on or off in Settings. With checks enabled, you can also choose to download and install updates automatically; automatic updates install when you quit the app. Use Check for Updates in Settings or the OnTimely menu to check manually."))
            HelpFeatureView(feature: HelpFeature("About OnTimely",
                "Choose OnTimely → About OnTimely in the menu bar to see your installed version and build, credits, and links to the website and GitHub repository."))
            HelpFeatureView(feature: HelpFeature("Your saved work",
                "Tasks and notes are saved locally on this Mac and stay available after reopening the app. Calendar subscriptions fetch updates from their connected calendar while OnTimely is running."))
            SettingsLink { Label("Open Settings", systemImage: "gearshape") }
                .buttonStyle(QuietButtonStyle())
            VStack(alignment: .leading, spacing: 12) {
                Text("Keyboard shortcuts").font(.system(size: 14, weight: .medium)).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(shortcuts, id: \.action) { shortcut in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(shortcut.action).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(shortcut.keys).font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(TaskStyle.coral).fixedSize()
                        }
                        .font(.system(size: 13)).padding(.vertical, 10)
                        TaskSeparator()
                    }
                }
            }
        }
    }
}

private struct HelpChapter: Identifiable {
    let number: Int
    let section: AppSection
    let summary: String
    let features: [HelpFeature]
    var id: String { section.rawValue }
}

private struct HelpFeature: Identifiable {
    let title: String
    let details: String
    var id: String { title }

    init(_ title: String, _ details: String) {
        self.title = title
        self.details = details
    }
}

private enum HelpGuide {
    static let chapters: [HelpChapter] = [
        HelpChapter(number: 1, section: .inbox, summary: "Capture first. Make a plan when you’re ready.", features: [
            HelpFeature("Add tasks quickly",
                "Choose + Add task, type a task name and press Return or choose Add task. The entry field stays open so you can capture another task immediately. Press Escape or Cancel to close it. ⌘N opens task entry from any section except Notes, where it creates a note."),
            HelpFeature("Keep unplanned tasks quiet",
                "Inbox tasks do not send reminders. Use Inbox for anything you want to remember before deciding when to start. If a task is already finished, click its circle to move it straight to Done."),
            HelpFeature("Plan a task in three steps",
                "Choose Plan beside a task. Set its deadline, estimate how long the work will take, then choose a starting point: Now, Latest safe start, or a time you choose. Estimated work has 15-minute, 30-minute, 1-hour and 2-hour options, plus Custom for your own number of minutes."),
            HelpFeature("Choose dates and times",
                "Click the date button to open the month calendar. Use the arrows to change months, choose a day, or select Today or Tomorrow. Click the time button to choose or enter a time. Changing the date keeps your selected time."),
            HelpFeature("Understand latest safe start",
                "OnTimely calculates the latest safe start by subtracting your estimated work and safety buffer from the deadline. Suggested start is when you intend to begin; latest safe start is the later checkpoint that leaves room to finish. If the latest safe start has passed, activating the plan begins reminders immediately."),
            HelpFeature("Review and adjust reminders",
                "The review shows your deadline, estimated work, suggested start and latest safe start. Edit any answer, rename the task, or expand Adjust reminders to change the safety buffer, repeat interval, submission reminder lead time or latest safe start override. An override later than the calculated time leaves less room for your estimate and buffer."),
            HelpFeature("Activate, rename or delete",
                "Choose Activate reminders on the review to move the task to Active. Cancel closes the plan without applying your draft. Use the task’s three-dot menu or right-click to Rename or Delete; deletion asks for confirmation.")
        ]),
        HelpChapter(number: 2, section: .active, summary: "Know what needs attention, and keep each deadline moving.", features: [
            HelpFeature("Read your task status",
                "Planned tasks are grouped into Needs attention, Working and Later. Each task shows its deadline, start time and current status, including approaching deadlines and overdue work. The list updates as your plan reaches each reminder checkpoint."),
            HelpFeature("Suggested-start reminders",
                "When it is time to begin, choose I’m Working in the app or notification. This confirms that you have started and stops reminders for that start phase. The task remains Active until you mark it submitted or done."),
            HelpFeature("Latest-start reminders",
                "Latest start is a separate checkpoint. Even if you confirmed the earlier suggested start, OnTimely can ask again at latest start. Choose Yes, I’m Working to confirm that checkpoint. Confirming a start checkpoint does not stop submission reminders."),
            HelpFeature("Submission reminders and completion",
                "Near the deadline, OnTimely reminds you to finish and submit. Choose Submitted / Done only when the work is finished and any required submission is complete. This stops the task’s reminders and moves it to Done. Overdue tasks remain visible until you finish, move them to Inbox or delete them."),
            HelpFeature("Snooze a reminder",
                "Use Snooze to pause the current reminder phase for 5, 10, 15 or 30 minutes, or 1 hour. Notifications offer Snooze 10m. The task shows its snoozed-until time. Snoozing the current phase does not remove later checkpoints or your deadline."),
            HelpFeature("Inspect and edit a plan",
                "Expand Timing details for your start checkpoints, deadline, planned window, submission reminder start and repeat interval. Personal tasks also show estimated work and safety buffer. Click the task title or choose Edit plan from its menu to change the plan, then choose Save plan."),
            HelpFeature("Use notifications and task menus",
                "Click a task notification to open and highlight the task, or use its available working, snooze and completion actions directly. The three-dot menu and right-click menu also let you rename a task, move it back to Inbox to stop reminders, or delete it after confirmation.")
        ]),
        HelpChapter(number: 3, section: .calendar, summary: "See your schedule and connect calendar assignments.", features: [
            HelpFeature("Browse Month and Day views",
                "Switch between Month and Day, use the arrows to move through dates, and choose Today to return to the current date. Click a day in Month to open its timeline. Days with more than three plans show a more button to reveal the day. In Day view, choose Now to scroll to the current time, or click the plan count to show the day’s task list."),
            HelpFeature("Read and open calendar plans",
                "Calendar shows tasks with a planned start and deadline, including completed plans. Blue marks later or snoozed work, green marks working, coral marks start or submission reminders, and red marks latest-start or overdue work. Completed plans are muted with a checkmark. Click a task block or task in the day list to see its details and use the same actions as Active."),
            HelpFeature("Create a task on a day",
                "Right-click a day in Month or empty space in Day and choose New task. Enter the task name, then plan its deadline, duration and start with the selected day as your starting point. If you cancel planning after creating the task, it remains in Inbox."),
            HelpFeature("Open a webcal link with OnTimely",
                "When opening a webcal subscription link, choose OnTimely as the application. OnTimely opens the calendar import dialog with the link already filled in. You can also choose Import calendar and paste your webcal or HTTPS subscription link manually."),
            HelpFeature("Preview and select assignments",
                "Set the School time zone to the calendar’s time zone, then choose Preview tasks. Select individual upcoming assignments, use Select all, or Clear the selection before importing. Unchecked entries stay excluded from later refreshes. You can connect a calendar with no selected tasks and let new assignments arrive automatically."),
            HelpFeature("Understand imported deadlines",
                "ManageBac assignments keep their actual deadline. New imports skip past-due assignments and unsupported all-day, repeating or incomplete entries. Reminder rules use the selected school time zone; preview deadlines are shown in that zone, while the main app displays dates using your Mac’s local time."),
            HelpFeature("Automatic plans for imported tasks",
                "Imported assignments become Active with reminders already planned. For deadlines at or before 4:20 p.m., suggested start is 7 p.m. the previous day and latest start is 10 p.m. For later deadlines, suggested start is 6:50 p.m. and latest start is 9 p.m. that day. If those evening checkpoints would reach or pass the deadline, reminders instead begin 2 hours and 1 hour before it."),
            HelpFeature("Edit an imported task",
                "Open the task and choose Edit plan to change its title, deadline, suggested start, latest start, repeat interval and submission reminder lead time. Imported tasks use these checkpoints directly, so you do not need to enter estimated work or a safety buffer. Calendar refreshes keep your edits. Review any deadline-changed notice; cancelled assignments are labelled so you can decide whether to keep them as personal tasks."),
            HelpFeature("Refresh and manage subscriptions",
                "Connected calendars refresh on launch and every 15 minutes while OnTimely runs. Open Import calendar to see connected calendars, their last update or any sync error, and choose Refresh to fetch changes manually. New upcoming assignments import automatically, while completed or deleted assignments stay completed or excluded."),
            HelpFeature("Disconnect a calendar",
                "In Import calendar, choose Disconnect next to a connected calendar and confirm. Disconnecting stops further calendar refreshes and keeps tasks you already imported. Calendar links are stored in Keychain; see Permissions below if macOS asks for access during a refresh.")
        ]),
        HelpChapter(number: 4, section: .notes, summary: "Write, format and save the details around your work.", features: [
            HelpFeature("Create and switch notes",
                "Choose New note, or press ⌘N while Notes is selected. Click a note in the list to open it; each row shows its title and a short preview. Edit the title at the top of the note and write in the editor below."),
            HelpFeature("Format text and headings",
                "Select text and use the toolbar for bold, italic, underline or strikethrough. Choose Body, Title, Heading or Subheading from the paragraph style menu, and choose a text size from 12 to 36 points. Bold, italic and underline also use ⌘B, ⌘I and ⌘U. Scroll the formatting toolbar horizontally if all controls do not fit."),
            HelpFeature("Lists and checklists",
                "The Lists menu creates bulleted lists, numbered lists and checklists. Toggle a checklist item by clicking its checkbox or using Check or uncheck item in the menu. Checklists organize your note; they do not create deadline tasks or reminders."),
            HelpFeature("Links, quotes and code",
                "Choose Link in the toolbar to insert a web or email link with optional display text. Use Inline code for code within a sentence. The three-dot formatting menu adds a Quote or Code block. Standard text selection, copy, paste and undo work in the editor."),
            HelpFeature("Automatic and manual saving",
                "Changes to a note’s title and content save automatically as you write. The status changes from Saving… to Saved. Choose Save or press ⌘S to save immediately. If saving fails, use Retry. Leaving Notes or switching notes also saves pending edits."),
            HelpFeature("Delete a note",
                "Use the note’s three-dot menu, or right-click it in the list, and choose Delete note. Confirm to permanently remove it. Notes stay separate from your tasks and do not send reminders.")
        ]),
        HelpChapter(number: 5, section: .done, summary: "Keep a record of finished work, or give it another start.", features: [
            HelpFeature("Find completed tasks",
                "Tasks completed from Inbox, Active or Calendar appear here, most recently completed first. Each task shows when you finished it. If it had a deadline, expand Details to see the original deadline. Completed tasks no longer send reminders."),
            HelpFeature("Reopen in Inbox",
                "Choose Reopen in Inbox from the task’s three-dot or right-click menu. The task returns to Inbox with reminders off. Plan and activate it again when you want a new schedule. Completing an imported assignment keeps it completed through later calendar refreshes."),
            HelpFeature("Rename or remove finished work",
                "The task menu also offers Rename and Delete. Renaming keeps the completion record. Deleting asks for confirmation and permanently removes the task.")
        ])
    ]
}
