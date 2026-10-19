#!/usr/bin/env bash
# codex-zh-linux.sh — 翻转 Codex/ChatGPT 桌面应用(Linux 版) app.asar 中的
# enable_i18n 默认值，让官方内置简体中文语言包生效。
#
# 用法:
#   sudo bash codex-zh-linux.sh            # 自动定位 app.asar
#   sudo bash codex-zh-linux.sh /path/to/app.asar   # 手动指定（AppImage 解包后可用）
#
# 回滚: 脚本会打印具体的 cp 命令。
# 注意: 应用每次升级会覆盖 app.asar，升级后需重跑本脚本。

set -euo pipefail

# ---------- 1. 定位 app.asar ----------
if [ $# -ge 1 ]; then
  ASAR="$1"
else
  ASAR=$(find /opt /usr/lib /usr/local/lib -maxdepth 5 -type f \
    \( -ipath '*chatgpt*' -o -ipath '*codex*' \) -name app.asar 2>/dev/null | head -1)
fi

if [ -z "${ASAR:-}" ] || [ ! -f "$ASAR" ]; then
  echo "错误: 未找到 app.asar。"
  echo "请确认已安装并至少启动过一次应用；也可手动指定:"
  echo "  sudo bash $0 /路径/app.asar"
  echo "AppImage 用户: ./xxx.AppImage --appimage-extract 后指定 squashfs-root 内的 app.asar"
  exit 1
fi
echo "目标文件: $ASAR"
echo "文件大小: $(stat -c%s "$ASAR") 字节"

# ---------- 2. 检查应用是否在运行（仅提示，不强制关闭） ----------
APP_DIR=$(dirname "$(dirname "$ASAR")")
if pgrep -f "$APP_DIR" >/dev/null 2>&1; then
  echo
  echo "警告: 检测到该应用正在运行 (目录 $APP_DIR)。"
  echo "      建议先完全退出应用再打补丁；现在继续也可以，重启应用后生效。"
  echo
fi

# ---------- 3. 备份 ----------
BAK="$ASAR.bak"
cp -a "$ASAR" "$BAK"
echo "已备份到: $BAK"

# ---------- 4. 打补丁 ----------
python3 - "$ASAR" <<'EOF'
import re, sys

p = sys.argv[1]
data = open(p, 'rb').read()

# 匹配形如 enable_i18n`,!1 / enable_i18n:!1 / enable_i18n=!1 的默认值
# 分隔符排除括号，避免误伤 enable_i18n(),!1 这类函数调用的第二参数
pat = re.compile(rb'(enable_i18n[^a-zA-Z0-9()]{0,3})!1')
matches = list(pat.finditer(data))
n = len(matches)

if n == 0:
    print("未匹配到默认值模式。以下是文件中所有 enable_i18n 出现位置的上下文:")
    for m in re.finditer(rb'enable_i18n', data):
        i = m.start()
        print(f"  偏移 {hex(i)}: {data[max(0, i-10):i+30]!r}")
    sys.exit("补丁中止，原文件未改动（备份已生成）。请把上面的上下文发出来调整正则。")

for m in matches:
    print(f"  偏移 {hex(m.start())}: {data[max(0, m.start()-10):m.end()+1]!r}  ->  ...!0")

new = pat.sub(rb'\g<1>!0', data)
open(p, 'wb').write(new)

# 回读校验
check = open(p, 'rb').read()
remaining = len(pat.findall(check))
flipped = len(re.findall(rb'enable_i18n[^a-zA-Z0-9()]{0,3}!0', check))
if remaining != 0 or flipped < n:
    sys.exit("校验失败！请回滚: 用备份恢复后再联系排查")
print(f"补丁完成并校验通过: 修改 {n} 处，回读确认 {flipped} 处已为 !0")
EOF

echo
echo "完成。请完全退出并重启应用查看效果（若界面仍英文，检查 Settings → General → Language 是否为中文（中国））。"
echo "回滚命令: sudo cp -a '$BAK' '$ASAR'"
