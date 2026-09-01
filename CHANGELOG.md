# Changelog / 更新日志

All notable TaskDeck changes are recorded here. Version numbers follow semantic versioning, while `CFBundleVersion` uses a monotonically increasing integer.

## 1.9.0 (Build 10) - Quality & Onboarding

- Added a first-run bilingual onboarding experience for empty installations; existing users with tasks are never interrupted.
- Added keyboard navigation for Today (`⌘1`), All Tasks (`⌘2`), and Completed (`⌘3`) alongside the existing creation, search, clear-filter, and desktop-board shortcuts.
- Added VoiceOver labels and state descriptions to task, subtask, focus, report, filter, composer, sidebar, and desktop-board controls.
- Added a native standalone XCTest target to the shared Xcode scheme with isolated temporary-database coverage for persistence, subtasks, compound filters, Trash, backup restoration, and legacy JSON.
- Confirmed that tests and onboarding require no database migration and never read or modify the user's TaskDeck database.

## 1.8.0 (Build 9) - Precision Workflow

- Added persistent, checkable subtasks backed by the existing relational SQLite subtask table.
- Added subtask creation and editing in the task composer, inline completion/deletion on task cards, and recurring-task subtask templates.
- Added global search across task names, directions, notes, and subtask titles.
- Added compound priority and date filters for overdue, today, upcoming, and unscheduled work.
- Added a Menu Bar Extra for creating a task without opening the main window.
- Added app commands for new task (`⌘N`), global search (`⌘F`), clear filters (`⌘⌥F`), and desktop board (`⌘⇧D`).
- Upgraded JSON archives to schema v4 while retaining backward-compatible imports.

## 1.7.0 (Build 8) - Safety & Recovery

- Added a task Trash with one-click undo, restore, permanent deletion, and empty-trash controls.
- Added a database-backup browser with integrity status, task/focus counts, and bilingual restore confirmation.
- Added guarded restore: only managed TaskDeck backups are accepted, corrupt files are rejected, and the current database is backed up again before replacement.
- Migrated SQLite schema v1 to v2 with a non-destructive `deleted_at` column; existing tasks remain active and unchanged.
- Excluded trashed tasks from lists, reports, streaks, heatmaps, deep links, and Widget interactions.
- Added regression coverage for soft deletion, undo, SQLite v1 migration, safe restore, corrupt backups, and path validation.

## 1.6.0 (Build 7) - Public Release Preparation

- Added configurable production bundle identifiers and App Group identifiers.
- Added read-only migration from the previous local App Group SQLite database.
- Enabled Hardened Runtime for the app and Widget targets.
- Enabled App Sandbox for the Widget extension while retaining the direct-distribution host app's migration access.
- Added Universal Release archive, Developer ID export, app and DMG notarization, stapling, Gatekeeper validation, and SHA-256 generation.
- Added release-readiness and privacy-audit scripts.
- Added a bilingual privacy policy and public-release guide.
- Confirmed that task databases, JSON exports, credentials, certificates, user home paths, and email strings are excluded from the app bundle.

## 1.5.0 (Build 6) - SQLite & Settings

- Added the Settings window, Chinese/English switching, visible task editing, SQLite storage, automatic backups, and JSON import/export.
- Migrated tasks and focus history without deleting legacy JSON files.

## 1.4.0 (Build 5) - WidgetKit

- Added small, medium, and large WidgetKit widgets with App Intents and deep links.

## 1.3.0 (Build 4) - Localization

- Added Simplified Chinese and English interface support.

## 1.2.0 (Build 3) - Focus & Reports

- Added focus sessions, completion streaks, heatmaps, and PDF reports.

## 1.1.0 (Build 2) - Task Workflow

- Added task editing, priorities, notes, recurrence, postponement, and safer backups.

## 1.0.0 (Build 1)

- Initial local-first TaskDeck release.
