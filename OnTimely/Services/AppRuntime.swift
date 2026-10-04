import AppKit
import Foundation
import Observation
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", active = "Active", calendar = "Calendar", notes = "Notes", done = "Done"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .active: "clock"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .done: "checkmark"
        }
    }
}

enum ReminderDefaults {
    static var intervalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: "reminderIntervalMinutes")
        return (1...60).contains(value) ? value : 10
    }
    static var bufferMinutes: Int {
        guard UserDefaults.standard.object(forKey: "safetyBufferMinutes") != nil else { return 30 }
        return max(0, min(10_080, UserDefaults.standard.integer(forKey: "safetyBufferMinutes")))
    }
    static var submissionLeadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: "submissionLeadMinutes")
        return (1...1_440).contains(value) ? value : 30
    }
}

@MainActor
@Observable
final class AppRuntime {
    let container: ModelContainer?
    let store: TaskStore?
    let noteStore: NoteStore?
    let calendarImports: CalendarImportService?
    let startupError: String?
    let notifications: NotificationManager
    var section: AppSection = .inbox
    var permission: NotificationPermission = .unknown
    var errorMessage: String?
    var highlightedTaskID: UUID?
    var isEnablingNotifications = false
    var newNoteRequest: UUID?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var calendarTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var started = false

    init() {
        do {
            let container = try AppPersistence.makeContainer()
            self.container = container
            let taskStore = TaskStore(context: container.mainContext)
            store = taskStore
            noteStore = NoteStore(context: container.mainContext)
            calendarImports = CalendarImportService(store: taskStore)
            startupError = nil
        } catch {
            container = nil
            store = nil
            noteStore = nil
            calendarImports = nil
            startupError = error.localizedDescription
        }
        notifications = NotificationManager()
        notifications.onAction = { [weak self] payload in await self?.handle(payload) }
        notifications.shouldPresent = { [weak self] payload in self?.isValid(payload, foreground: true) ?? false }
        calendarImports?.onTasksChanged = { [weak self] in await self?.refresh() }
    }

    func start() {
        guard !started else { return }
        started = true
        // The lightweight app keeps refilling its notification queue when its window is closed.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keep deadline reminders scheduled")
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.calendarImports?.refreshSubscriptions() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                await self?.calendarImports?.refreshSubscriptions()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                await self?.calendarImports?.refreshSubscriptions()
            }
        })
        Task { @MainActor [weak self] in
            await self?.refresh()
            await self?.calendarImports?.refreshSubscriptions()
        }
    }

    func refresh() async {
        // Serialize async center operations; a state change during an await triggers another pass.
        if refreshing {
            refreshAgain = true
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        refreshing = true
        defer {
            refreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        repeat {
            refreshAgain = false
            do {
                permission = await notifications.permission()
                guard let store else { return }
                let snapshots = try store.allTasks().map(\.snapshot)
                let queue = ReminderScheduler.queue(for: snapshots, now: .now)
                try await notifications.synchronize(events: permission == .allowed ? queue.events : []) { [weak self] payload in
                    self?.permission == .allowed && self?.isValid(payload, foreground: true) == true
                }
                await notifications.removeObsoleteDelivered { [weak self] in self?.isValid($0, foreground: false) ?? false }
            } catch { errorMessage = "Reminders could not be updated. \(error.localizedDescription)" }
        } while refreshAgain
    }

    func enableNotifications() async {
        guard !isEnablingNotifications else { return }
        isEnablingNotifications = true
        defer { isEnablingNotifications = false }
        do {
            permission = try await notifications.requestPermission()
            await refresh()
        } catch { errorMessage = "Notifications could not be enabled. \(error.localizedDescription)" }
    }

    @discardableResult
    func perform(_ operation: (TaskStore) throws -> Void) -> Bool {
        guard let store else { return false }
        do {
            try operation(store)
            Task { await refresh() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func activate(_ task: TaskItem, plan: TaskPlan) -> Bool {
        guard perform({ try $0.activate(task, plan: plan) }) else { return false }
        if section != .calendar { section = .active }
        Task {
            if await notifications.permission() == .notRequested { await enableNotifications() }
            else { await refresh() }
        }
        return true
    }

    func focusQuickAdd() {
        section = .inbox
        highlightedTaskID = nil
        NotificationCenter.default.post(name: .focusQuickAdd, object: nil)
    }

    func focusNewNote() {
        section = .notes
        newNoteRequest = UUID()
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func isValid(_ payload: NotificationPayload, foreground: Bool) -> Bool {
        guard let task = try? store?.task(id: payload.taskID), task.status == .active,
              task.reminderRevision == payload.revision else { return false }
        let snapshot = task.snapshot
        if snapshot.isConfirmed(payload.phase) { return false }
        if snapshot.snoozedPhase == payload.phase, let until = snapshot.snoozedUntil, until > .now { return false }
        // Preserve the independent latest checkpoint for short tasks with overlapping phases.
        if payload.phase == .latestStart, let latest = snapshot.latestSafeStartDate,
           abs(latest.timeIntervalSinceNow) < 60 { return true }
        if foreground {
            let phase = snapshot.phase(at: .now)
            return phase == payload.phase
        }
        return snapshot.phase(at: .now) == payload.phase
    }

    private func handle(_ payload: NotificationPayload) async {
        // Done remains usable from an older delivered phase, but never from an older plan revision.
        guard let store else { return }
        do {
            guard let task = try store.applyReminderAction(taskID: payload.taskID, revision: payload.revision,
                                                          action: payload.action) else { await refresh(); return }
            if payload.action == .open {
                section = .active
                highlightedTaskID = task.id
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .showMainWindow, object: nil)
            }
            await refresh()
        } catch { errorMessage = "The notification action could not be saved. \(error.localizedDescription)" }
    }
}

extension Notification.Name {
    static let focusQuickAdd = Notification.Name("OnTimely.focusQuickAdd")
    static let showMainWindow = Notification.Name("OnTimely.showMainWindow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var runtime: AppRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "OnTimely", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        Self.runtime?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime = Self.runtime else { return .terminateNow }
        Task {
            await runtime.refresh()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .showMainWindow, object: nil) }
        return true
    }
}
