# TaskDeck

English | [简体中文](README.md)

TaskDeck is a local-first, hacker-inspired native macOS app for task execution and focus tracking. Built with SwiftUI, it brings long-term directions, precise next actions, time estimates, focus sessions, and review reports into one workspace.

## Features

- Create tasks with a direction, a precise action, and an estimated duration
- Edit task details, priority, notes, schedule, and reminder time
- Repeat tasks daily, on weekdays, weekly, or monthly
- Postpone a task by one hour, until tomorrow, or until next Monday
- Receive reminders through macOS notifications
- Start, pause, resume, and finish a focus session for a specific task
- Track the current completion streak and a 12-week activity heatmap
- Generate daily, weekly, and monthly completion and focus summaries
- Copy a Markdown report or export a polished one-page PDF report
- Use a compact always-on-top task board across macOS Spaces
- Keep all data locally with automatic backups and no cloud account
- Switch instantly between Simplified Chinese and English, with the preference remembered locally

## Privacy and Data

TaskDeck does not upload task content. Runtime data is stored in:

```text
~/Library/Application Support/TaskDeck/
├── tasks.json
├── focus-sessions.json
├── focus-runtime.json
└── Backups/
```

Upgrading the app does not delete existing tasks. Task and focus records are stored separately, and TaskDeck keeps a recoverable previous version of the task file before saving.

## Requirements

- macOS 13.0 or later
- Apple Silicon Mac (the current packaging script targets arm64)
- Swift 6 toolchain (source builds only)

## Build

```bash
zsh scripts/check_logic.sh
zsh scripts/package_app.sh
```

The app bundle is written to `outputs/TaskDeck.app`; the distributable archive is written to `outputs/TaskDeck-macOS.zip`.

## Getting Started

1. Unzip `TaskDeck-macOS.zip` and move `TaskDeck.app` into Applications.
2. On first launch, if macOS displays a security confirmation, right-click the app and choose Open.
3. Add a precise task and use its play button to start focusing.
4. Review daily, weekly, or monthly results and export a PDF from the report panel.
5. Open the desktop board for an always-on-top compact view.

## Project Layout

```text
Sources/TaskDeck/   SwiftUI application source
Assets/             Application metadata
scripts/            Build and logic-check scripts
outputs/            User guides, release notes, and sample reports
```

## Version

Current stable version: TaskDeck 1.3.0.

This is a personal vibe-coding project. The repository is private by default; it can be made public later after reviewing signing, privacy, and release configuration.
