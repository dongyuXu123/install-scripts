#!/usr/bin/env bash
# 扫描"linux与windows共用"NTFS 分区（827G，可能要跑几个小时）。无需 sudo。
# 结果只列染毒文件，完整日志按日期存到本目录。
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/共享分区扫描-$(date +%F-%H%M).log"
[ -d "/run/media/dongyu/linux与windows共用" ] || { echo "共享分区未挂载"; exit 1; }
clamscan -r -i --bell --log="$LOG" "/run/media/dongyu/linux与windows共用"
echo "完整日志：$LOG"
