# chrome-install

在 Ubuntu 上安装 Google Chrome 稳定版。2026-10-19 已在 Ubuntu 26.04.1 上执行成功，
装的版本是 155.0.8059.84。

## 说明

- 直接从官方 `dl.google.com` 下载 `.deb`，该域名国内 CDN 直连，实测很快，
  无需走 gh-proxy 等加速镜像
- 脚本自包含：包不存在时自动下载 → apt 安装 → 验证 → 删除安装包
- 当天实际执行的版本只含"安装已下载的 deb"一步，本脚本是之后整合的
  自包含版，效果一致

## 使用

```bash
sudo bash install-chrome.sh
```

## 备注

- 安装后 `/etc/apt/sources.list.d/google-chrome.sources` 是正常的，
  后续 `apt upgrade` 可自动更新 Chrome，**不要删**
- 卸载：`sudo apt purge google-chrome-stable`
