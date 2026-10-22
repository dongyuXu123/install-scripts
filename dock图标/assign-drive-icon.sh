#!/usr/bin/env bash
# 给指定分区绑定专属 dock 图标 — 用法: sudo bash assign-drive-icon.sh <分区> <图标名>
# 例:  sudo bash assign-drive-icon.sh /dev/sdb1 ai-huggingface
# 可用图标名: card-claude card-gpt card-gemini card-deepseek card-glm card-kimi
#             card-qwen card-grok card-ernie card-hunyuan card-seed card-minimax
#             card-mistral card-llama pet-fish
# 不带参数运行 = 列出所有分区和当前图标。
set -euo pipefail

RULES=/etc/udev/rules.d/99-dock-drive-icons.rules
[ -f "$RULES" ] || { echo "先运行 install-udev-rules.sh 装基础规则"; exit 1; }

if [ $# -eq 0 ]; then
  echo "== 分区 → 当前图标 =="
  for d in /dev/sd?[0-9] /dev/nvme*n[0-9]p[0-9]; do
    [ -e "$d" ] || continue
    info=$(udevadm info -q property "$d" 2>/dev/null || true)
    echo "$info" | grep -q '^ID_FS_USAGE=filesystem' || continue
    label=$(echo "$info" | awk -F= '/^ID_FS_LABEL=/{print $2}')
    uuid=$(echo "$info" | awk -F= '/^ID_FS_UUID=/{print $2}')
    icon=$(echo "$info" | awk -F= '/^UDISKS_ICON_NAME=/{print $2}')
    ign=$(echo "$info" | awk -F= '/^UDISKS_IGNORE=/{print $2}')
    printf '%-16s %-20s %-14s %s\n' "$d" "${label:-无标签}" "${icon:-默认}" \
      $([ "${ign:-0}" = "1" ] && echo "(隐藏)") ""
  done
  exit 0
fi

[ $# -eq 2 ] || { echo "用法: sudo bash $0 <分区如/dev/sdb1> <图标名>"; exit 1; }
DEV=$1; ICON=$2
[ -e "$DEV" ] || { echo "分区不存在: $DEV"; exit 1; }
U_PATH="/home/dongyu/.local/share/icons/hicolor/256x256/devices/$ICON.png"
[ -f "$U_PATH" ] || { echo "图标不存在: $U_PATH"; echo "可用: $(cd /home/dongyu/.local/share/icons/hicolor/256x256/devices/ && ls *.png | sed 's/\.png//' | tr '\n' ' ')"; exit 1; }

UUID=$(udevadm info -q property "$DEV" | awk -F= '/^ID_FS_UUID=/{print $2}')
[ -n "$UUID" ] || { echo "$DEV 没有 UUID（可能是空分区）"; exit 1; }

# 幂等：删掉该 UUID 的旧行，追加新绑定
sed -i "/ID_FS_UUID==\"$UUID\"/d" "$RULES"
echo "ENV{ID_FS_UUID}==\"$UUID\", ENV{UDISKS_ICON_NAME}=\"$ICON\", ENV{UDISKS_SYMBOLIC_ICON_NAME}=\"$ICON\"" >> "$RULES"
udevadm control --reload
udevadm trigger --subsystem-match=block
sleep 0.5
got=$(udevadm info -q property "$DEV" | awk -F= '/^UDISKS_ICON_NAME=/{print $2}')
if [ "$got" = "$ICON" ]; then
  echo "OK  $DEV (UUID=$UUID) -> $ICON，dock 会自动刷新"
else
  echo "FAIL 期望 $ICON 实得 ${got:-无}，请把输出发回给 agent"; exit 1
fi
