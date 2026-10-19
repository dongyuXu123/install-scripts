#!/usr/bin/env bash
# 扫描下载目录（默认）或指定目录，只报告染毒文件。无需 sudo。
# 用法: bash scan-下载.sh [目录]
TARGET="${1:-$HOME/下载}"
[ -d "$TARGET" ] || { echo "目录不存在：$TARGET"; exit 1; }
clamscan -r -i --bell "$TARGET"
