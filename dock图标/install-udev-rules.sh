#!/usr/bin/env bash
# 一键安装 dock 分区图标 udev 规则(v6 拟人角色卡 + 外接随机分配) — 用法: sudo bash install-udev-rules.sh
# 幂等：重复运行只会覆盖同一批文件。
set -euo pipefail

RULES=/etc/udev/rules.d/99-dock-drive-icons.rules
AUTO=/etc/udev/rules.d/99-z-dock-icons-auto.rules
HELPER=/usr/local/bin/dock-icon-assign
UNIT=/etc/systemd/system/dock-icon-assign@.service

cat > "$RULES" <<'EOF'
# 左侧 dock 分区图标 v6 (2026-10-22)：AI 拟人角色卡 + 隐藏 EFI 分区 + 外接随机分配角色
# 图标本体: ~/.local/share/icons/hicolor/256x256/devices/card-*.png (另有 pet-fish.png 备用)
# 手动指定外接设备形象: sudo bash assign-drive-icon.sh <分区> <图标名>
# 移除规则: sudo bash uninstall-udev-rules.sh

# 外接 USB 设备插入时由 systemd 服务自动随机分配不重复角色（card-glm 仅为兜底）
ENV{ID_USB_INTERFACES}=="?*", ENV{ID_FS_USAGE}=="filesystem", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="dock-icon-assign@%k.service"
ENV{ID_USB_INTERFACES}=="?*", ENV{ID_FS_USAGE}=="filesystem", ENV{UDISKS_ICON_NAME}="card-glm", ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-glm"

# 内部硬盘分区（C=Claude D=ChatGPT E=Gemini，共用数据=DeepSeek）
ENV{ID_FS_UUID}=="D8F4A21DF4A1FDBE", ENV{UDISKS_ICON_NAME}="card-claude",   ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-claude"
ENV{ID_FS_UUID}=="6FB18845F2566D36", ENV{UDISKS_ICON_NAME}="card-gpt",      ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-gpt"
ENV{ID_FS_UUID}=="EA4E2EB64E2E7C07", ENV{UDISKS_ICON_NAME}="card-gemini",   ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-gemini"
ENV{ID_FS_UUID}=="629F3DAF0BC72D2A", ENV{UDISKS_ICON_NAME}="card-deepseek", ENV{UDISKS_SYMBOLIC_ICON_NAME}="card-deepseek"

# 两个 EFI 系统分区：不在 dock / 文件管理器里显示（不影响 /boot/efi 开机挂载）
ENV{ID_FS_UUID}=="7719-2D20", ENV{UDISKS_IGNORE}="1"
ENV{ID_FS_UUID}=="C8E6-D5D5", ENV{UDISKS_IGNORE}="1"
EOF

# 随机分配器：给新插入的外接设备挑一个未被占用的角色，写进独立规则文件（按 UUID 持久）
cat > "$HELPER" <<'EOF'
#!/usr/bin/env bash
# dock-icon-assign <内核设备名如 sda3>：随机分配不重复角色（幂等、带锁、自去重）
set -euo pipefail
[ $# -ge 1 ] || exit 0
DEVNODE=/dev/$1
MAIN=/etc/udev/rules.d/99-dock-drive-icons.rules
AUTO=/etc/udev/rules.d/99-z-dock-icons-auto.rules
touch "$AUTO"
dedupe() { # 同一 UUID 只保留最后一行（udev 语义即最后匹配生效）
  local f=$1; [ -s "$f" ] || return 0
  awk -F'"' '{last[$2]=$0} END{for(u in last) print last[u]}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
exec 9>"$AUTO.lock"
flock 9
dedupe "$AUTO"
uuid=$(udevadm info -q property "$DEVNODE" 2>/dev/null | awk -F= '/^ID_FS_UUID=/{print $2}')
[ -n "${uuid:-}" ] || exit 0
grep -q "ID_FS_UUID==\"$uuid\"" "$MAIN" "$AUTO" 2>/dev/null && exit 0
ALL="card-claude card-gpt card-gemini card-deepseek card-glm card-kimi card-qwen card-grok card-ernie card-hunyuan card-seed card-minimax card-mistral card-llama"
used=$(grep -h 'ID_FS_UUID' "$MAIN" "$AUTO" 2>/dev/null | grep -oh 'card-[a-z]*' | sort -u || true)
pool=()
for c in $ALL; do grep -qx "$c" <<<"$used" || pool+=("$c"); done
[ ${#pool[@]} -gt 0 ] || pool=($ALL)
pick=$(shuf -n1 -e -- "${pool[@]}")
echo "ENV{ID_FS_UUID}==\"$uuid\", ENV{UDISKS_ICON_NAME}=\"$pick\", ENV{UDISKS_SYMBOLIC_ICON_NAME}=\"$pick\"" >> "$AUTO"
udevadm control --reload
udevadm trigger --name-match="$DEVNODE"
logger -t dock-icon-assign "$DEVNODE (UUID=$uuid) -> $pick"
EOF
chmod 755 "$HELPER"

cat > "$UNIT" <<'EOF'
[Unit]
Description=Dock icon auto random assign for %i

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dock-icon-assign %i
EOF

touch "$AUTO"
udevadm control --reload
udevadm trigger --subsystem-match=block
systemctl daemon-reload

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

echo "== 当前已插入的外接设备（本次自动随机分配） =="
found_usb=0
for d in /dev/sd?[0-9] /dev/sd[a-z]; do
  [ -e "$d" ] || continue
  info=$(udevadm info -q property "$d" 2>/dev/null) || continue
  grep -q '^ID_USB_INTERFACES=' <<<"$info" || continue
  grep -q '^ID_FS_USAGE=filesystem' <<<"$info" || continue
  found_usb=1
  "$HELPER" "$(basename "$d")" || true
  label=$(awk -F= '/^ID_FS_LABEL=/{print $2}' <<<"$info")
  icon=$(udevadm info -q property "$d" | awk -F= '/^UDISKS_ICON_NAME=/{print $2}')
  echo "外接 $d (${label:-无标签}) -> 图标: ${icon:-未知}"
done
[ "$found_usb" -eq 0 ] && echo "(当前没有外接设备；以后每次插入都会自动分配一个不重复的角色)"

if [ "$fail" -eq 0 ]; then
  echo "全部生效。正常情况下 dock 图标会自动刷新；若个别没刷，注销重新登录一次即可。"
else
  echo "有未生效项，请把上面完整输出发回给 agent。"
  exit 1
fi
