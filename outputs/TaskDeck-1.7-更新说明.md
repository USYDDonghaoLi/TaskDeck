# TaskDeck 1.7

## 中文

- 新增任务回收站：删除后可立即撤销，也可在“设置”中恢复。
- 新增永久删除与清空回收站，操作前仍会自动备份数据库。
- 新增备份浏览器：显示时间、文件大小、任务数、专注记录数和完整性状态。
- 恢复备份前会校验 SQLite 完整性，并再次保存当前数据库；损坏文件和备份目录外文件会被拒绝。
- 数据库从 v1 无损升级到 v2，仅新增删除时间字段，原有任务不会被删除。
- 回收站任务不会进入报告、连续完成天数、热力图、Widget 或深链接。

## English

- Added Trash for tasks with immediate undo and later restoration in Settings.
- Added permanent deletion and Empty Trash, with an automatic pre-change database backup.
- Added a backup browser showing date, size, task count, focus-session count, and integrity status.
- Backups are integrity-checked before restoration, and the current database is saved again first. Corrupt or unmanaged files are rejected.
- Migrated SQLite from v1 to v2 by adding only an optional deletion timestamp; existing tasks are preserved.
- Trashed tasks are excluded from reports, streaks, heatmaps, Widgets, and deep links.
