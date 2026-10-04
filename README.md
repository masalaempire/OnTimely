# OnTimely

A simple macOS app that reminds you to start your tasks and finish before their deadlines. Requires macOS 14 or later.

## How to use

On first launch, a quick setup lets you choose reminder defaults and automatic updates. Choose **Use current settings** to skip it.

1. **Add a task.** In Inbox, click **+ Add task** or press **⌘N**, type a task, and press Return. Inbox tasks stay quiet until you plan them.
2. **Plan it.** Click **Plan** and choose the deadline, how long the task will take, and when you want to start.
3. **Turn on reminders.** Review your plan, click **Activate reminders**, and allow macOS notifications. Your task moves to Active.
4. **Start working.** Click **I’m Working** when you begin, or **Snooze** if you need more time. OnTimely may ask you to confirm again at your latest safe start.
5. **Finish.** Click **Submitted / Done** to stop reminders and move the task to Done.

Click an Active task's title to edit its plan. Use a task's menu to rename, delete, or return it to Inbox. To reuse a completed task, choose **Reopen in Inbox** in Done.

Keep OnTimely running for reminders. You can close its window and leave the app open.

## Importing ManageBac tasks

Open **Calendar → Import calendar** at the top right and paste your ManageBac `webcal://` subscription link. Choose your school's time zone, preview upcoming assignments, and import them. Past-due assignments are skipped. ManageBac task deadlines use the event's start time; the later end of its calendar display block is ignored. Other calendar feeds use their timed event's end, and to-do feeds use their explicit due time. All-day events and recurring series are excluded.

Imported assignments activate reminders automatically. Deadlines at or before **4:20 p.m.** get a suggested start at **7 p.m. the previous day** and latest start at **10 p.m.** Later deadlines get **6:50 p.m.** and **9 p.m.** on their due day. If those times would reach or pass the deadline, reminders use **2 hours before** and **1 hour before** instead. Submission reminders use your existing preferences.

Click an imported task to edit its deadline and reminder times without entering an estimated duration. Calendar refreshes preserve your edits, completed tasks, and dismissed entries. Previously imported assignments remain visible when overdue. Subscriptions refresh on launch and every 15 minutes while the app runs; reopen **Import calendar** to refresh manually or disconnect. Disconnecting preserves your tasks. Private subscription links are stored in this Mac's Keychain.

## Settings and shortcuts

Open **Settings** with **⌘,** to change reminder defaults and update preferences. To check for updates manually, choose **OnTimely → Check for Updates…**.

- **⌘N** — Add a task
- **⌘1** — Inbox
- **⌘2** — Active
- **⌘3** — Done
