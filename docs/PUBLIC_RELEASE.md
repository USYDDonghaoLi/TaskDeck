# TaskDeck 官网直发指南

这条流程用于在 Mac App Store 之外公开分发 TaskDeck。最终产物是由 Developer ID Application 签名、经 Apple 公证并已附加公证票据的 Universal `.dmg`。

## 1. 安装完整 Xcode

1. 从 Mac App Store 安装最新正式版 Xcode。
2. 启动一次 Xcode，接受许可协议并安装附加组件。
3. 选择完整 Xcode：

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   xcodebuild -version
   ```

## 2. 准备 Apple Developer 身份

1. 加入 Apple Developer Program。
2. 在 Xcode 的 Settings → Accounts 登录同一 Apple Account。
3. 由 Account Holder 创建 `Developer ID Application` 证书，安装到登录钥匙串。
4. 用以下命令确认证书：

   ```bash
   security find-identity -v -p codesigning
   ```

## 3. 注册正式标识与 App Group

在 Certificates, Identifiers & Profiles 中创建三个唯一标识：

```text
主应用： com.your-brand.taskdeck
Widget：  com.your-brand.taskdeck.widget
App Group: group.com.your-brand.taskdeck
```

1. 主应用和 Widget 都使用 Explicit App ID。
2. 为两个 App ID 启用 App Groups capability。
3. 将同一个 App Group 关联到两个 App ID。
4. 如 Apple 后台要求，为 Developer ID 分发创建包含 App Group 的 provisioning profile。

Widget 扩展已单独启用 App Sandbox；主应用在官网直发版中保持非沙盒，以便兼容旧版数据迁移。两者都只通过已签名的 App Group 共享任务数据库。

TaskDeck 1.6 会从旧 `group.local.taskdeck.shared` 数据库只读迁移到新 App Group，原数据库不会被修改或删除。

## 4. 配置本机发布参数

```bash
cp scripts/release.env.example scripts/release.env
cp scripts/privacy_denylist.txt.example scripts/privacy_denylist.txt
```

编辑 `scripts/release.env`，填入已注册的 Team ID、Bundle ID、App Group 和证书全名。该文件已被 Git 忽略。不要在文件中填写 Apple Account 密码、App 专用密码或 API 私钥。

可选的 `scripts/privacy_denylist.txt` 每行填写一个私密邮箱、用户名或任务片段。审计脚本只报告匹配行号，不会打印私密内容。

## 5. 将公证凭据存入钥匙串

使用 Apple Account 和 App 专用密码：

```bash
xcrun notarytool store-credentials "TaskDeckNotary" \
  --apple-id "YOUR_APPLE_ACCOUNT" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

密码由 macOS Keychain 保管，不得写入仓库或发布脚本。也可使用 App Store Connect API Key 创建同名 Keychain profile。

## 6. 运行发布前检查

```bash
zsh scripts/check_logic.sh
zsh scripts/check_pdf_report.sh
zsh scripts/check_release_readiness.sh
zsh scripts/check_release_privacy.sh outputs/TaskDeck.app
```

`check_release_readiness.sh` 必须全部通过才可以继续。

## 7. 生成正式 DMG

```bash
zsh scripts/release_taskdeck.sh
```

脚本会自动执行：

1. Xcode Archive。
2. Developer ID Application 导出。
3. 验证 arm64 + x86_64 Universal Binary。
4. 隐私扫描和嵌套签名检查。
5. 应用 ZIP 公证并向 `.app` 附加票据。
6. 创建、签名和验证 DMG。
7. DMG 公证并向 DMG 附加票据。
8. Gatekeeper 评估、第二次隐私扫描和 SHA-256 生成。

成功后产物位于：

```text
outputs/releases/TaskDeck-<version>.dmg
outputs/releases/TaskDeck-<version>.dmg.sha256
```

## 8. 干净机验收

在不安装开发证书的 Mac 用户账户上测试：

- 下载 DMG 后 Gatekeeper 不报未知开发者。
- 将 TaskDeck 拖入 Applications 后可启动。
- 新安装不包含任何任务或专注记录。
- 从 1.5 升级后任务、专注记录和语言偏好完整。
- 提醒、Widget、JSON 导入/导出和 PDF 正常。
- 断网时仍可从已附票的 DMG 安装。

## 9. 对外发布

公开提供 DMG、SHA-256、更新日志和隐私政策。TaskDeck 的 GitHub 源码仓库已经公开，但发布前仍不得将本机的 SQLite、JSON 导出、自动备份、证书、API Key、`release.env` 或公证凭据加入提交、Release 附件或 DMG。

在 GitHub Releases 创建与版本号对应的标签（例如 `v2.0.0`），并仅上传经过上述流程验证的 DMG、SHA-256 和更新说明。发布后从一台没有开发证书的 Mac 再次下载并完成第 8 节验收。
