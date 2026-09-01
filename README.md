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
- 本地持久化与自动备份，不依赖云端账户

## 隐私与数据

TaskDeck 不会上传任务内容。运行数据保存在：

```text
~/Library/Application Support/TaskDeck/
├── tasks.json
├── focus-sessions.json
├── focus-runtime.json
└── Backups/
```

升级应用不会删除已有任务。任务和专注数据使用独立文件，任务保存前还会保留上一份可恢复备份。

## 系统要求

- macOS 13.0 或更高版本
- Apple Silicon Mac（当前打包脚本目标为 arm64）
- Swift 6 工具链（仅源码构建需要）

## 构建

```bash
zsh scripts/check_logic.sh
zsh scripts/package_app.sh
```

构建结果位于 `outputs/TaskDeck.app`，压缩包位于 `outputs/TaskDeck-macOS.zip`。

## 使用

1. 解压 `TaskDeck-macOS.zip`，将 `TaskDeck.app` 拖入“应用程序”。
2. 第一次打开时，如 macOS 显示安全确认，请右键应用并选择“打开”。
3. 添加精准任务，然后使用播放按钮开始专注。
4. 从右侧报告面板查看日、周、月战绩或导出 PDF。
5. 点击“桌面悬浮”打开常驻桌面的迷你任务板。

## 项目结构

```text
Sources/TaskDeck/   SwiftUI 应用源码
Assets/             应用配置
scripts/            构建与逻辑检查脚本
outputs/            使用说明、更新说明和示例报告
```

## 版本

当前稳定版本：TaskDeck 1.2.0。

这是一个个人 Vibe Coding 项目，代码库默认保持私有；如果将来希望作为开源作品展示，可以在清理签名、隐私与发布配置后再改为公开。
