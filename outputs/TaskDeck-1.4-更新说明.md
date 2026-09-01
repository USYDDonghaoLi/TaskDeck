# TaskDeck 1.4

## 新功能

- 增加真正的 macOS WidgetKit 扩展，同时保留原来的“桌面悬浮”窗口。
- 小号 Widget 显示今日完成率。
- 中号 Widget 显示前三个待办任务。
- 大号 Widget 显示方向、精准任务和预计时间。
- 使用 App Intents 直接在 Widget 中勾选任务。
- 点击 Widget 中的任务可打开 TaskDeck，并滚动、高亮到对应任务。

## 数据安全

- 第一次启动 1.4 时，旧任务只会复制到 App Group 共享容器。
- 原始 `~/Library/Application Support/TaskDeck/tasks.json` 不会被移动、覆盖或删除。
- 专注记录、连续完成天数、热力图和 PDF 报告数据保持不变。
- 迁移与 Widget 勾选流程已通过自动逻辑测试；测试验证了旧文件内容不变。

## Widget 签名说明

WidgetKit 是受 macOS 保护的系统扩展。仓库已包含完整 Widget Target、App Sandbox、App Group、App Intents、深链接和 Xcode 工程；要让 Widget 出现在系统小组件库，必须用完整版 Xcode 为主应用和扩展选择同一个 Apple Development Team 进行签名。将来提交 Mac App Store 时也使用这一工程进行 Archive。
