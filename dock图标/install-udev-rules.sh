#!/usr/bin/env bash
# 一键安装 dock 分区图标 udev 规则(v5 拟人角色卡版) — 用法: sudo bash install-udev-rules.sh
# 幂等：重复运行只会覆盖同一份规则文件。
set -euo pipefail

RULES=/etc/udev/rules.d/99-dock-drive-icons.rules

cat > "$RULES" <<'EOF'
# 左侧 dock 分区图标 v5 (2026-10-22)：AI 拟人角色卡 + 隐藏 EFI 分区 + 外接默认 GLM
# 图标本体: ~/.local/share/icons/hicolor/256x256/devices/card-*.png (另有 pet-fish.png 备用)
# 外接设备逐个换形象: sudo bash assign-drive-icon.sh <分区> <图标名>
# 移除规则: sudo bash uninstall-udev-rules.sh

# 外接 USB 设备默认 = GLM；具体设备的 UUID 绑定写在后面，会覆盖这条
ENV{DEVTYPE}=="partition", ENV{ID_BUS}=="usb", ENV{UDISKS_ICON_NAME}="card-glm", ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-glm"

# 内部硬盘分区（C=Claude D=ChatGPT E=Gemini，共用数据=DeepSeek）
ENV{ID_FS_UUID}=="D8F4A21DF4A1FDBE", ENV{UDISKS_ICON_NAME}="card-claude",   ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-claude"
ENV{ID_FS_UUID}=="6FB18845F2566D36", ENV{UDISKS_ICON_NAME}="card-gpt",      ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-gpt"
ENV{ID_FS_UUID}=="EA4E2EB64E2E7C07", ENV{UDISKS_ICON_NAME}="card-gemini",   ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-gemini"
ENV{ID_FS_UUID}=="629F3DAF0BC72D2A", ENV{UDISKS_ICON_NAME}="card-deepseek", ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-deepseek"

# 两个 EFI 系统分区：不在 dock / 文件管理器里显示（不影响 /boot/efi 开机挂载）
ENV{ID_FS_UUID}=="7719-2D20", ENV{UDISKS_IGNORE}="1"
ENV{ID_FS_UUID}=="C8E6-D5D5", ENV{UDISKS_IGNORE}="1"
EOF

udevadm control --reload
udevadm trigger --subsystem-match=block

echo "== 验证：内部分区图标 =="
fail=0
check_icon() { # 分区 期望图标名
  got=$(udevadm info -q property "/dev/$1" 2>/dev/null | awk -F= '/^UDISKS_ICON_NAME=/{print $2}')
  if [ "$got" = "$2" ]; then echo "OK   /dev/$1 -> $got"
  else echo "FAIL /dev/$1 期望 $2 实得 ${got:-无}"; fail=1; fi
}
check_ignore() { # 分区
  got=$(udevadm info -q property "/dev/$1" 2>/dev/null | awk -F= '/^UDISKS_IGNORE=/{print $2}')
  if [ "$got" = "1" ]; then echo "OK   /dev/$1 -> 已隐藏"
  else echo "FAIL /dev/$1 期望 UDISKS_IGNORE=1 实得 ${got:-无}"; fail=1; fi
}
check_icon nvme0n1p3 card-claude
check_icon nvme0n1p4 card-gpt
check_icon nvme0n1p5 card-gemini
check_icon nvme1n1p3 card-deepseek
check_ignore nvme1n1p1
check_ignore nvme0n1p1

echo "== 当前已插入的外接设备 =="
found_usb=0
for d in /dev/sd?[0-9]; do
  [ -e "$d" ] || continue
  found_usb=1
  label=$(udevadm info -q property "$d" | awk -F= '/^ID_FS_LABEL=/{print $2}')
  icon=$(udevadm info -q property "$d" | awk -F= '/^UDISKS_ICON_NAME=/{print $2}')
  echo "外接 $d (${label:-无标签}) -> 图标: ${icon:-card-glm(默认)}"
done
[ "$found_usb" -eq 0 ] && echo "(当前没有外接 USB 分区；插入后默认 GLM，可用 assign-drive-icon.sh 逐个换)"

if [ "$fail" -eq 0 ]; then
  echo "全部生效。正常情况下 dock 图标会自动刷新；若个别没刷，注销重新登录一次即可。"
else
  echo "有未生效项，请把上面完整输出发回给 agent。"
  exit 1
fi
