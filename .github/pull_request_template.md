## Summary / 改动摘要

Describe the user-visible result and why the change is needed.

## Verification / 验证

- [ ] `zsh scripts/check_logic.sh`
- [ ] `zsh scripts/check_pdf_report.sh` when report code changes
- [ ] Xcode tests pass when application or data code changes
- [ ] Documentation or changelog is updated when behavior changes

## Privacy and safety / 隐私与安全

- [ ] No real task data, SQLite database, JSON export, local path, email address, credential, certificate, provisioning profile, or release secret is included
- [ ] Database changes preserve existing tasks and include a migration or compatibility test
- [ ] Screenshots and fixtures use synthetic data only
