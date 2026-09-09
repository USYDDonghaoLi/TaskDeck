# TaskDeck Privacy Policy / 隐私政策

Last updated / 最后更新：2026-09-09

## 简体中文

TaskDeck 是一款本地优先的 macOS 任务与专注管理应用。

### 数据收集

TaskDeck 不收集、上传、出售或与第三方共享用户的任务、专注记录、提醒、使用统计或个人信息。应用不包含分析 SDK、广告 SDK 或用户跟踪器。

### 本地存储

任务、子任务、专注记录和运行中计时保存在当前 Mac 用户的 App Group SQLite 数据库中。每次修改前会在同一本地容器中创建数据库备份，最多保留最近 30 份。

### Widget 与系统提醒

TaskDeck 的主应用和 Widget 通过 Apple App Group 在本机共享同一数据库。提醒使用 macOS 本地通知服务，用户可以在系统设置中撤销通知权限。

### 导入与导出

只有在用户主动选择“导出 JSON”时，TaskDeck 才会在用户指定的位置创建归档。导入文件只在本地解析，不会上传。

### 网络访问

当前版本的 TaskDeck 本身不向任何 TaskDeck 服务器发送数据。macOS 可能为 Developer ID、公证票据和 Gatekeeper 安全检查访问 Apple 服务；该过程由 Apple 和 macOS 控制。

### 公开源码仓库

公开 GitHub 仓库只包含源码、测试、文档和不含个人信息的演示材料，不包含任何用户数据库、专注记录、备份或 JSON 导出。GitHub Issue 和 Pull Request 是公开内容；提交问题时请勿上传任务导出、数据库、包含私人任务的截图、证书或凭据。敏感问题请按照仓库中的 `SECURITY.md` 私下报告。

## English

TaskDeck is a local-first macOS task and focus manager.

### Data collection

TaskDeck does not collect, upload, sell, or share tasks, focus records, reminders, usage analytics, or personal information. It contains no analytics SDK, advertising SDK, or user tracker.

### Local storage

Tasks, subtasks, focus history, and active timers are stored in an App Group SQLite database belonging to the current macOS user. Before each modification, TaskDeck creates a local database backup and retains the latest 30 backups.

### Widget and notifications

The app and Widget share the same database locally through Apple App Groups. Reminders use the local macOS notification service, and notification permission can be revoked in System Settings.

### Import and export

TaskDeck creates a JSON archive only when the user explicitly chooses Export JSON and selects a location. Imported files are parsed locally and are never uploaded.

### Network access

The current TaskDeck app does not send data to a TaskDeck server. macOS may contact Apple for Developer ID, notarization-ticket, and Gatekeeper security checks; that process is controlled by Apple and macOS.

### Public source repository

The public GitHub repository contains source code, tests, documentation, and privacy-safe demo material only. It does not contain user databases, focus history, backups, or JSON exports. GitHub issues and pull requests are public: never attach a task export, database, screenshot containing private tasks, certificate, or credential. Follow the repository's `SECURITY.md` for sensitive reports.
