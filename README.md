# OnTimely 0.1.0

A small native macOS deadline reminder app. Capture first; plan when you’re ready.

## Run

Requires macOS 14 or later. Open `OnTimely.xcodeproj` in Xcode 26.3 or later, choose the **OnTimely** scheme and **My Mac**, then run. Xcode downloads the pinned Sparkle 2.10.0 package on the first build. The project uses ad-hoc signing and does not require a paid Apple Developer membership.

1. Choose **+ Add task** in Inbox, or press **⌘N**. Type a task and press Return; the inline composer stays ready for another task. Escape closes it. Inbox tasks never notify you.
2. Choose **Plan** and answer three questions: when it is due, how long it will take, and when you would like to start. Review your answers before saving. **Adjust reminders** contains the safety buffer, repeat interval, submission lead, and optional latest-start override. Latest safe start is calculated as `due − work − buffer`.
3. Choose **Activate reminders** and allow macOS notifications. The task moves to **Active**, grouped into Needs attention, Working, or Later. Click its title to review or edit the plan.
4. Use **I’m Working** to stop suggested-start reminders. Latest safe start asks for a separate confirmation even if you confirmed early.
5. Near due, reminders ask you to finish and submit. **Submitted / Done** stops every reminder and moves the task to **Done**.

Use the overflow menu or right-click a row to rename, delete, or move it back to Inbox. An Inbox task’s circle marks it done without planning. In Done, **Reopen in Inbox** lets you plan a task again. Timing details expand within Active and Done rows.

Keyboard shortcuts: **⌘N** opens the Inbox composer; **⌘1**, **⌘2**, and **⌘3** switch sections; **⌘,** opens settings. The quick-add shortcut works inside the app. The global shortcut and menu bar interface are deferred to v0.2.

## Reminder behavior

- Defaults: repeat every 10 minutes, 30-minute safety buffer, submission reminders beginning 30 minutes before due. Settings change new task defaults; each plan can override them.
- Suggested and latest-start reminders repeat only within their phase, until the corresponding working confirmation.
- Submission reminders repeat at the task’s interval, with extra checkpoints at 15 minutes, 5 minutes, and the deadline when those fall inside the submission window. They keep repeating after due while the app runs, until Done.
- Snooze defaults to 10 minutes in notifications; the window offers 5, 10, 15, 30, and 60 minutes. Snoozing an early phase never suppresses the next phase. The deadline breaks through a pre-deadline submission snooze.
- For short tasks, submission and latest-start can overlap. The independent latest-start checkpoint still occurs; confirming working never silences submission reminders.
- Timing edits reset working confirmations. Renaming preserves them. Old notifications from an earlier plan revision cannot modify the revised task.

**Close the window to leave reminders running.** OnTimely maintains up to 64 upcoming local requests across all tasks, refilling every 30 seconds and on wake or activation. These are scheduled with macOS in advance, so window focus is unnecessary. Fully quitting stops refilling: only the finite queue already scheduled can be delivered. Reopen the app to resume it. There is no background helper or launch-at-login in v0.1.

macOS controls delivery, sounds, Focus, and notification presentation. A sleeping Mac can deliver late; this app does not wake it. To see notification buttons, expand a banner or open Notification Center. If permission is denied, OnTimely shows an **Open Settings** notice; task capture and planning still work.

## Architecture

```text
OnTimely/
  Core/Models/           SwiftData TaskItem, snapshots, reminder actions
  Core/Utilities/        Deadline calculation and plan validation
  Core/Services/         Explicitly saved task operations, deterministic reminder queue
  Services/             macOS notifications, delegate, app lifecycle
  Views/                Inbox, Active, Done, planning, capture, settings
Tests/OnTimelyCoreTests/ Lifecycle, scheduling, snooze, and disk persistence
```

All mutations save SwiftData before rescheduling. Save failures roll back and surface an error. Notification callbacks and views use the same main context. Scheduling operations are serialized and repeated if task state changes during an asynchronous update; notification responses and Quit wait for the queue update to finish. Notifications are reconciled by stable identifiers; obsolete pending and delivered requests are removed after edits, confirmations, snooze, completion, deletion, or returning a task to Inbox. Dates are stored as absolute instants and displayed in the Mac’s local time zone.

No accounts, sync, analytics, or calendar integrations. Network access is used for GitHub-hosted update checks and downloads.

## Updates

Choose **OnTimely → Check for Updates…**, or open **Settings → Updates**. Automatic checks are enabled by default. Automatic downloads and installation are optional; turn them on in Settings to install downloaded updates when you quit. Sparkle stores these preferences and handles download progress, verification, installation, and relaunch.

The feed is `appcast.xml` in this repository's `main` branch, served through GitHub's raw HTTPS URL. It starts empty until a downloadable release is published. Signed downloads will be attached to versioned GitHub Releases. No separate website is needed. DMG packaging and release publication are deferred.

Update archives must be signed with the original OnTimely Ed25519 key. Its private part is stored in the development Mac's login Keychain under account `one.simonlm.OnTimely`; only its public part is in `Configuration/Info.plist`. Do not generate a replacement key for each release or commit a private key. See [the release notes for maintainers](Documentation/Updates.md).

## Checks

```sh
/usr/bin/swift test --scratch-path .build/core-tests
/usr/bin/xcodebuild -project OnTimely.xcodeproj -scheme OnTimely \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
```

For a local runnable build without a development certificate, replace `CODE_SIGNING_ALLOWED=NO` with `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=''`. This signs only for local use; distribution signing and notarization are separate release steps.

For a quick live notification check: choose a deadline roughly six minutes ahead, estimated work of two minutes, one-minute buffer, suggested start now, a one-minute repeat interval, and one-minute submission lead. Confirm the suggested notification, wait for the independent latest-start check, then verify submission and Done. Reopen the app to check that the task and its confirmations persisted.

The Sparkle integration builds in Release for Apple silicon and Intel. The embedded framework, installer service, public update key, sandbox entitlements, icon resource, and bundle signatures were checked. No app launches, UI checks, automated tests, or actual update installations were performed for this integration; the user handles live testing and acceptance. The following record predates the UI redesign: 20 automated tests passed on the development Mac, the Release build and local signature checks passed, and native capture, planning, completion, persistence after relaunch, window reopening, and settings were inspected. Real notification delivery and system notification buttons still require the manual check above.
