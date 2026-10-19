#!/bin/bash
# Google Chrome 稳定版安装脚本（自包含：自动下载 + 安装 + 清理）
# 用法: sudo bash install-chrome.sh
# 2026-10-19 首次使用，装的是 155.0.8059.84；以后重装会自动拉当前最新稳定版
set -euo pipefail

DEB=/tmp/google-chrome-stable_current_amd64.deb
URL=https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

if [ ! -f "$DEB" ]; then
    echo "==> 下载 Chrome（dl.google.com 国内 CDN 直连，实测 ~140MB/3s）"
    curl -fL --connect-timeout 10 -o "$DEB" "$URL"
fi

echo "==> 安装（apt 自动补齐依赖，postinst 会添加 google-chrome.sources 软件源）"
apt-get install -y "$DEB"

echo "==> 验证安装"
google-chrome --version

rm -f "$DEB"
echo "完成！应用菜单搜 Chrome，或终端运行: google-chrome"
