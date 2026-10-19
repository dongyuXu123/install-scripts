# codex-zh-linux

让 Linux 版 Codex 桌面应用（ChatGPT 桌面应用内的 Codex，2026-08 起预览）显示简体中文界面。

## 背景

应用启动时需要从 `ab.chatgpt.com` 拉取远程开关 `enable_i18n`，该域名在国内不可达；
而中文语言包本身 100% 内置在应用里。本脚本把 app.asar 中该开关的默认值
从 `!1`（false）翻转为 `!0`（true），仅改字节、不动 asar 结构。
原理与 Windows 方案相同（参考 WanZhuang-wei/codex-zh-localization）。

## 使用

```bash
sudo bash codex-zh-linux.sh                # 自动定位 app.asar
sudo bash codex-zh-linux.sh /路径/app.asar  # 手动指定（AppImage 解包后用）
```

- 打补丁前会自动备份为 `app.asar.bak`，并打印回滚命令
- 应用升级（apt upgrade）会覆盖 app.asar，**升级后需重跑本脚本**
- 若界面仍为英文：检查 Settings → General → Language 是否为"中文（中国）"，
  并确认 `~/.codex/config.toml` 里的 `localeOverride = "zh-CN"` 没有被
  cc-switch 切换供应商时抹掉

## 回滚

```bash
sudo cp -a /路径/app.asar.bak /路径/app.asar
```
