# Changelog / 更新日志

All notable TaskDeck changes are recorded here. Version numbers follow semantic versioning, while `CFBundleVersion` uses a monotonically increasing integer.

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
