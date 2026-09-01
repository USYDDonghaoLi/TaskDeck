# TaskDeck

[English](README.en.md) | 简体中文

TaskDeck 是一个本地优先、极客风格的原生 macOS TODO 与专注管理应用，使用 SwiftUI 构建。它把长期方向、精准行动、时间预估、专注计时和复盘报告放在同一个工作台中。

## 功能

- 使用“大方向 + 精准任务描述 + 预计时间”创建任务
- 编辑任务、优先级、备注、执行时间和提醒时间
- 支持每天、工作日、每周和每月重复任务
- 一键延期到一小时后、明天或下周一
- 通过 macOS 系统通知发送提醒
- 针对具体任务开始、暂停、继续和结束专注计时
- 显示连续完成天数和最近 12 周活动热力图
- 自动生成日、周、月完成与实际专注报告
- 复制 Markdown 战绩，或导出一页式 PDF 行动报告
- 可置顶并跨桌面显示的紧凑任务板
- 原生 WidgetKit 桌面小组件：小号显示今日完成率，中号显示前三个待办，大号显示方向、任务和预计时间
- 通过 App Intents 直接在小组件中勾选完成，并通过深链接定位到应用内对应任务
- 本地持久化与自动备份，不依赖云端账户
- 在应用内即时切换简体中文与英文，语言偏好会自动保存

## 隐私与数据

TaskDeck 不会上传任务内容。1.4 起，任务共享副本保存在 App Group，供主应用和 Widget 共同使用；专注记录仍保存在原目录：

```text
~/Library/Group Containers/group.local.taskdeck.shared/TaskDeck/
├── tasks.json
└── Backups/

~/Library/Application Support/TaskDeck/
├── tasks.json            # 升级前原文件，迁移后仍保留
├── focus-sessions.json
├── focus-runtime.json
└── Backups/
```

升级应用不会删除已有任务。第一次启动 1.4 时只会把旧 `tasks.json` 复制到共享容器，不会移动、覆盖或删除原文件；任务保存前仍会保留上一份可恢复备份。

## 系统要求

- 主应用需要 macOS 13.0 或更高版本
- 原生桌面 Widget 需要 macOS 14.0 或更高版本
- Apple Silicon Mac（当前打包脚本目标为 arm64）
- Swift 6 工具链（仅源码构建需要）

## 构建

```bash
zsh scripts/check_logic.sh
zsh scripts/package_app.sh
```

构建结果位于 `outputs/TaskDeck.app`，压缩包位于 `outputs/TaskDeck-macOS.zip`。

`scripts/package_app.sh` 会生成供本机测试的 ad-hoc 签名包。macOS 要求 Widget 扩展使用 Apple Development 或发行证书签名，才能稳定出现在系统小组件库中。完整 Widget 构建流程：

1. 安装完整版 Xcode，打开 `TaskDeck.xcodeproj`。
2. 在 TaskDeck 与 TaskDeckWidget 两个 Target 的 Signing & Capabilities 中选择同一个 Development Team。
3. 保留并注册 App Group `group.local.taskdeck.shared`，然后运行 TaskDeck Scheme。

项目已包含独立 Widget Target、嵌入阶段、App Sandbox、App Group 和 App Intents 配置。以后提交 Mac App Store 时也应从该 Xcode 工程 Archive。

## 使用

1. 解压 `TaskDeck-macOS.zip`，将 `TaskDeck.app` 拖入“应用程序”。
2. 第一次打开时，如 macOS 显示安全确认，请右键应用并选择“打开”。
3. 添加精准任务，然后使用播放按钮开始专注。
4. 从右侧报告面板查看日、周、月战绩或导出 PDF。
5. 点击“桌面悬浮”打开常驻桌面的迷你任务板。
6. 在桌面空白处右键“编辑小组件”，搜索 TaskDeck，并选择小号、中号或大号。

## 项目结构

```text
Sources/TaskDeck/   SwiftUI 应用源码
WidgetExtension/    WidgetKit + App Intents 扩展源码
Assets/             应用配置
TaskDeck.xcodeproj/ 可签名、可归档的 Xcode 工程
scripts/            构建与逻辑检查脚本
outputs/            使用说明、更新说明和示例报告
```

## 版本

当前版本：TaskDeck 1.4.0。

这是一个个人 Vibe Coding 项目，代码库默认保持私有；如果将来希望作为开源作品展示，可以在清理签名、隐私与发布配置后再改为公开。
