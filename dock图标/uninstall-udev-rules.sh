#!/usr/bin/env bash
# 移除 dock 分区图标 udev 规则，恢复 Yaru 默认图标 — 用法: sudo bash uninstall-udev-rules.sh
set -euo pipefail
rm -f /etc/udev/rules.d/99-dock-drive-icons.rules
udevadm control --reload
udevadm trigger --subsystem-match=block
echo "udev 规则已移除，分区恢复默认图标。"
echo "图标本体仍保留在 ~/.local/share/icons/hicolor/256x256/devices/（card-*.png、pet-fish.png），彻底删除见 README。"
