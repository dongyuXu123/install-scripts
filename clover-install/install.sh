#!/bin/bash
# Clover r5175 一键安装脚本（写入 ESP + 注册 NVRAM 引导项）v2
# v2 修复: ESP 是 FAT32 不支持属主, 改用 cp -r 避免 "无法保留所有权" 中止
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "错误：请用 sudo 运行本脚本" >&2; exit 1; fi
BASE="$(cd "$(dirname "$0")" && pwd)"
SRC="$BASE/staging/EFI/CLOVER"
ESP=/boot/efi

# --- 动态定位当前系统的 ESP 及其磁盘/分区号，不写死设备名 ---
mountpoint -q "$ESP" || mount "$ESP"
ESP_DEV="$(findmnt -n -o SOURCE "$ESP")"
if [[ "$ESP_DEV" =~ ^/dev/(nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    DISK="/dev/${BASH_REMATCH[1]}"; PART="${BASH_REMATCH[2]}"
elif [[ "$ESP_DEV" =~ ^/dev/([sh]d[a-z]+)([0-9]+)$ ]]; then
    DISK="/dev/${BASH_REMATCH[1]}"; PART="${BASH_REMATCH[2]}"
else
    echo "错误：无法解析 ESP 设备 $ESP_DEV" >&2; exit 1
fi
echo ">> ESP: $ESP_DEV (磁盘 $DISK 分区 $PART)"

[ -f "$SRC/CLOVERX64.efi" ] || { echo "错误：缺少 $SRC/CLOVERX64.efi" >&2; exit 1; }

# --- 给本机 ESP 设置卷标 ESP_UBUNTU (Clover 自定义入口按卷标匹配; 幂等, 已有卷标则跳过) ---
# 挂载中内核会置 FAT 脏位(主引导扇区与备份不一致), fatlabel 拒绝写入 → 需先干净卸载再打标
CUR_LABEL=$(lsblk -n -o LABEL "$ESP_DEV")
if [ "$CUR_LABEL" != "ESP_UBUNTU" ]; then
    echo ">> 设置 ESP 卷标: '$CUR_LABEL' -> ESP_UBUNTU (临时卸载 ESP)"
    sync
    umount "$ESP" || { echo "错误: ESP 卸载失败(有程序占用?)" >&2; exit 1; }
    fatlabel "$ESP_DEV" ESP_UBUNTU
    mount "$ESP" || { echo "错误: ESP 重新挂载失败, 请手动: mount $ESP" >&2; exit 1; }
    lsblk -n -o LABEL "$ESP_DEV" | grep -q ESP_UBUNTU || { echo "错误: 卷标设置失败" >&2; exit 1; }
    echo ">> 卷标已设置为 ESP_UBUNTU"
else
    echo ">> ESP 卷标已是 ESP_UBUNTU, 跳过"
fi

# --- 写入文件（staging 是唯一事实来源，ESP 上的 CLOVER 直接重建，并清理历史 .bak）---
echo ">> 复制 Clover 文件到 ESP"
rm -rf "$ESP/EFI/CLOVER" "$ESP"/EFI/CLOVER.bak.*
cp -r "$SRC" "$ESP/EFI/CLOVER"

# --- 清理旧的 Clover NVRAM 条目，避免重复 ---
while [ -n "$(efibootmgr | grep 'Clover Boot Manager' | head -1)" ]; do
    OLD=$(efibootmgr | grep 'Clover Boot Manager' | head -1 | sed 's/Boot\([0-9A-Fa-f]*\)\*.*/\1/')
    efibootmgr -q -b "$OLD" -B >/dev/null 2>&1 || true
done

# --- 注册新引导项 ---
echo ">> 注册 NVRAM 引导项"
efibootmgr -q -c -d "$DISK" -p "$PART" -L 'Clover Boot Manager' -l '\EFI\CLOVER\CLOVERX64.EFI'
NEW=$(efibootmgr | grep 'Clover Boot Manager' | head -1 | sed 's/Boot\([0-9A-Fa-f]*\)\*.*/\1/')

# --- 调整启动顺序：Clover 最前，原有顺序保持不变 ---
ORDER=$(efibootmgr | grep '^BootOrder:' | awk '{print $2}' | tr ',' ' ' | sed "s/\b$NEW\b//")
efibootmgr -q -o "$NEW,$(echo $ORDER | tr ' ' ',')"
# 不动 Ubuntu/Windows 条目本身 —— 出问题可在 BIOS 启动菜单(F12)里直接选回

# --- 隐藏 GRUB 菜单(Clover 已承担选择功能; 急需时开机按住 Esc/Shift 可调出 GRUB) ---
if [ -f /etc/default/grub ] && command -v update-grub >/dev/null; then
    echo ">> 设置 GRUB_TIMEOUT=0 (跳过 GRUB 菜单)"
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    if grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
    fi
    update-grub >/dev/null 2>&1 || echo "!! update-grub 异常, 请手动检查 /etc/default/grub"
fi

sync
echo
echo "==== 安装完成，当前引导状态 ===="
efibootmgr
echo
ls -la "$ESP/EFI/CLOVER"
echo
echo "文件数校验: $(find "$ESP/EFI/CLOVER" -type f | wc -l) / 89"
echo
echo "下一步：重启进 BIOS(通常按 F2/Del) → 关闭 Secure Boot → 保存重启即可进入 Clover 图形菜单"
