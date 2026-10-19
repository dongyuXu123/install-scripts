#!/bin/bash
# Clover 卸载/回退脚本：删除 NVRAM 条目和 ESP 上的 CLOVER 目录，恢复原引导顺序
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "错误：请用 sudo 运行本脚本" >&2; exit 1; fi
ESP=/boot/efi
mountpoint -q "$ESP" || mount "$ESP"

while [ -n "$(efibootmgr | grep 'Clover Boot Manager' | head -1)" ]; do
    OLD=$(efibootmgr | grep 'Clover Boot Manager' | head -1 | sed 's/Boot\([0-9A-Fa-f]*\)\*.*/\1/')
    efibootmgr -q -b "$OLD" -B >/dev/null 2>&1 || true
done
[ -d "$ESP/EFI/CLOVER" ] && rm -rf "$ESP/EFI/CLOVER"

REST=$(efibootmgr | grep '^BootOrder:' | awk '{print $2}')
echo ">> 已移除 Clover，恢复原启动顺序: $REST"
efibootmgr
