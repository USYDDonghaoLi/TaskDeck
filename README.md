# TaskDeck

[English](README.en.md) | 简体中文

TaskDeck 是一个本地优先、极客风格的原生 macOS TODO 与专注管理应用，使用 SwiftUI 构建。它把长期方向、精准行动、时间预估、专注计时和复盘报告放在同一个工作台中。

## 功能

- 使用“大方向 + 精准任务描述 + 预计时间”创建任务
- 通过任务卡片上的铅笔编辑名称、预计时长、优先级、备注和日程
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
- 任务、专注记录和 Widget 共用本地 SQLite 数据库
- 每次修改前自动备份，并保留最近 30 份可恢复数据库
- 任务先移入回收站，可立即撤销、稍后恢复或永久删除
- 在设置中浏览自动备份、检查完整性，并安全恢复任务与专注数据
- 通过设置窗口导入或导出完整 JSON 归档
- 在设置窗口切换简体中文与英文，语言偏好会自动保存
- 支持 Hardened Runtime、Universal Binary、Developer ID、Apple 公证和 DMG 公开发布流水线
- 发布前自动检查任务数据、JSON、证书、邮箱和本机路径是否被误打包

## 隐私与数据

TaskDeck 不会上传任务内容。1.5 起，任务、专注记录和运行中的计时统一保存在 App Group 内的 SQLite 数据库，主应用与 Widget 使用事务化读写：

```text
~/Library/Group Containers/group.local.taskdeck.shared/TaskDeck/
├── taskdeck.sqlite3
└── Backups/
    ├── Database/       # 每次修改前备份，最多 30 份
    └── Legacy/         # 迁移前 JSON 的额外副本

~/Library/Application Support/TaskDeck/
├── tasks.json            # 升级前原文件，迁移后仍保留
├── focus-sessions.json   # 升级前原文件，迁移后仍保留
└── focus-runtime.json    # 升级前原文件，迁移后仍保留
```

升级应用不会删除已有任务。1.5 首次启动会优先读取 1.4 的共享 `tasks.json`，再迁移专注 JSON；原文件不会被移动、覆盖或删除。导入 JSON 前也会先备份当前数据库。

1.6 又增加了旧开发 App Group 到正式发布 App Group 的只读 SQLite 迁移：正式版首次启动会复制任务、专注历史和运行中计时，旧数据库原样保留。1.7 的删除操作改为回收站，并提供经过完整性校验的数据库备份恢复；升级时只新增可空字段，不会删除已有任务。完整隐私声明见 [PRIVACY.md](PRIVACY.md)。

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

### 官网公开发布

```bash
cp scripts/release.env.example scripts/release.env
cp scripts/privacy_denylist.txt.example scripts/privacy_denylist.txt
zsh scripts/check_release_readiness.sh
zsh scripts/release_taskdeck.sh
```

公开发布流水线会构建 arm64 + x86_64 Universal 应用，执行 Developer ID 导出、两层 Apple 公证、票据附加、Gatekeeper 检查、隐私审计和 SHA-256 生成。详细步骤见 [官网直发指南](docs/PUBLIC_RELEASE.md)。

## 使用

1. 解压 `TaskDeck-macOS.zip`，将 `TaskDeck.app` 拖入“应用程序”。
2. 第一次打开时，如 macOS 显示安全确认，请右键应用并选择“打开”。
3. 添加精准任务，然后使用播放按钮开始专注。
4. 点击任务卡片上的铅笔，可修改名称、预计时长和优先级。
5. 点击右上角“设置”，可切换语言、管理回收站、浏览/恢复自动备份，以及导入/导出 JSON。
6. 从右侧报告面板查看日、周、月战绩或导出 PDF。
7. 点击“桌面悬浮”打开常驻桌面的迷你任务板。
8. 在桌面空白处右键“编辑小组件”，搜索 TaskDeck，并选择小号、中号或大号。

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

当前版本：TaskDeck 1.7.0（Build 8）。

这是一个个人 Vibe Coding 项目，代码库默认保持私有；如果将来希望作为开源作品展示，可以在清理签名、隐私与发布配置后再改为公开。
