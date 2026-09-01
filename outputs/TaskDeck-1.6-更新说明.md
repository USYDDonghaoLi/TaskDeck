# TaskDeck 1.6

## 公开发布准备

- 主应用和 Widget 已启用 Hardened Runtime。
- Xcode Release 使用 arm64 + x86_64 Universal 架构。
- 新增 Developer ID Application 导出、Apple `notarytool` 公证、`stapler` 附票、Gatekeeper 验证和 DMG 打包流程。
- 应用和 DMG 分别公证并附票，便于离线安装验证。
- 每次发布生成 SHA-256 校验文件。

## 隐私与数据安全

- 新增发布包隐私审计，阻止 SQLite、JSON、证书、凭据、邮箱和 `/Users/...` 本机路径进入应用。
- 本地 SwiftPM Release 在签名前剔除调试符号，防止编译机用户名残留在可执行文件中。
- 私人 denylist 仅存在本机且被 Git 忽略，扫描结果不打印私密值。
- 新增中英文隐私政策。

## 正式 App Group 迁移

- Bundle ID 和 App Group 可在发布时通过本机配置注入，不在仓库保存 Apple 凭据。
- 首次使用正式 App Group 时，TaskDeck 会从旧开发 App Group 只读复制任务、专注历史和运行中计时。
- 旧 SQLite 的字节不会被修改，新容器还会保留一份额外副本。

## 发布前置条件

生成正式 DMG 还需要安装完整 Xcode、注册正式 Bundle ID/App Group、安装 Developer ID Application 证书，并在 macOS Keychain 中建立 `notarytool` 凭据。
