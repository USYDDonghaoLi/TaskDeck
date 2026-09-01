# TaskDeck

English | [简体中文](README.md)

TaskDeck is a local-first, hacker-inspired native macOS app for task execution and focus tracking. Built with SwiftUI, it brings long-term directions, precise next actions, time estimates, focus sessions, and review reports into one workspace.

## Features

- Create tasks with a direction, a precise action, and an estimated duration
- Use the visible pencil on a task card to edit its name, estimate, priority, notes, and schedule
- Repeat tasks daily, on weekdays, weekly, or monthly
- Postpone a task by one hour, until tomorrow, or until next Monday
- Receive reminders through macOS notifications
- Start, pause, resume, and finish a focus session for a specific task
- Track the current completion streak and a 12-week activity heatmap
- Generate daily, weekly, and monthly completion and focus summaries
- Copy a Markdown report or export a polished one-page PDF report
- Use a compact always-on-top task board across macOS Spaces
- Add native WidgetKit desktop widgets: small for today's progress, medium for the top three tasks, and large for direction, task, and estimate
- Complete tasks directly in a widget with App Intents and deep-link to the matching task in the app
- Share tasks, focus history, and the Widget through one local SQLite database
- Create a backup before every change and retain the latest 30 recoverable databases
- Import or export a complete JSON archive from the Settings window
- Switch between Simplified Chinese and English in Settings, with the preference remembered locally

## Privacy and Data

TaskDeck does not upload task content. Starting in 1.5, tasks, focus history, and the active timer live in a single SQLite database inside the App Group. The app and Widget use transactional access to that database:

```text
~/Library/Group Containers/group.local.taskdeck.shared/TaskDeck/
├── taskdeck.sqlite3
└── Backups/
    ├── Database/       # pre-change backups; latest 30 retained
    └── Legacy/         # an extra copy of pre-migration JSON

~/Library/Application Support/TaskDeck/
├── tasks.json            # preserved legacy file after migration
├── focus-sessions.json   # preserved legacy file after migration
└── focus-runtime.json    # preserved legacy file after migration
```

Upgrading does not delete existing tasks. On the first 1.5 launch, TaskDeck imports the 1.4 shared `tasks.json` first, then the focus JSON files. It never moves, overwrites, or deletes those originals. JSON import also backs up the current database before replacing data.

## Requirements

- macOS 13.0 or later for the main app
- macOS 14.0 or later for the native desktop widget
- Apple Silicon Mac (the current packaging script targets arm64)
- Swift 6 toolchain (source builds only)

## Build

```bash
zsh scripts/check_logic.sh
zsh scripts/package_app.sh
```

The app bundle is written to `outputs/TaskDeck.app`; the distributable archive is written to `outputs/TaskDeck-macOS.zip`.

`scripts/package_app.sh` creates an ad-hoc signed bundle for local testing. macOS requires an Apple Development or distribution signature before a Widget extension is reliably exposed in the system widget gallery. For a fully signed Widget build:

1. Install the full Xcode app and open `TaskDeck.xcodeproj`.
2. Select the same Development Team for the TaskDeck and TaskDeckWidget targets under Signing & Capabilities.
3. Keep and register the `group.local.taskdeck.shared` App Group, then run the TaskDeck scheme.

The project already contains the Widget target, embed phase, App Sandbox, App Group, and App Intents configuration. Use this Xcode project to Archive a future Mac App Store build.

## Getting Started

1. Unzip `TaskDeck-macOS.zip` and move `TaskDeck.app` into Applications.
2. On first launch, if macOS displays a security confirmation, right-click the app and choose Open.
3. Add a precise task and use its play button to start focusing.
4. Use the pencil on a task card to change its name, estimated duration, or priority.
5. Open Settings to change language, import/export JSON, or reveal the data folder.
6. Review daily, weekly, or monthly results and export a PDF from the report panel.
7. Open the desktop board for an always-on-top compact view.
8. Right-click the desktop, choose Edit Widgets, search for TaskDeck, and pick a small, medium, or large widget.

## Project Layout

```text
Sources/TaskDeck/   SwiftUI application source
WidgetExtension/    WidgetKit and App Intents extension source
Assets/             Application metadata
TaskDeck.xcodeproj/ Signable and archivable Xcode project
scripts/            Build and logic-check scripts
outputs/            User guides, release notes, and sample reports
```

## Version

Current version: TaskDeck 1.5.0.

This is a personal vibe-coding project. The repository is private by default; it can be made public later after reviewing signing, privacy, and release configuration.
