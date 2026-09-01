# TaskDeck 1.5

## 新功能

- 新增独立的极客风设置窗口，统一管理中英文切换与本地数据。
- 任务卡片新增可见的铅笔按钮，可修改名称、预计时长和优先级，任务 ID 与历史保持不变。
- 设置窗口支持导出完整 JSON 归档，以及导入完整归档或旧版任务 JSON。

## 数据层升级

- 继续支持 macOS 13，因此采用系统 SQLite，没有引入第三方数据依赖。
- 任务、专注历史和运行中的计时使用同一 App Group 数据库，与 Widget 事务化共享。
- 主应用和 Widget 同时修改时会在 SQLite 事务内合并最新状态，避免旧内存数据覆盖 Widget 的勾选。
- 每次修改前使用 SQLite 在线备份 API 创建完整备份，自动保留最近 30 份。
- 数据表已预留子任务关系，便于后续扩展。

## 升级安全

- 1.5 首次启动会优先迁移 1.4 App Group 中的最新 `tasks.json`，再迁移专注记录与运行中计时。
- 原 JSON 只读取和复制，不会被移动、覆盖或删除。
- 自动测试覆盖了迁移前后字节不变、损坏数据库保护、编辑持久化、Widget 并发写入、备份上限及 JSON 往返。

数据库位于 `~/Library/Group Containers/group.local.taskdeck.shared/TaskDeck/taskdeck.sqlite3`，备份位于同目录的 `Backups/Database`。
