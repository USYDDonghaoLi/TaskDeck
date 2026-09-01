# TaskDeck 1.1

## 新功能

- 编辑已有任务，同时保留任务 ID 和完成历史
- 普通、重要、紧急三级优先级
- 任务备注
- 每天、工作日、每周、每月周期任务
- 快速延期到一小时后、明天 09:00 或下周一 09:00
- 紧急和重要任务优先排序

## 数据安全

- 完全兼容 TaskDeck 1.0 的任务 JSON
- 第一次加载旧数据时创建 `Backups/tasks-before-v1.1.json`
- 每次保存前保留 `Backups/tasks-last-known-good.json`
- 如果旧文件无法解析，新版会停止写入，不会用空任务覆盖原文件

应用升级只替换 `TaskDeck.app`，不会删除 `Application Support/TaskDeck` 中的个人任务。
