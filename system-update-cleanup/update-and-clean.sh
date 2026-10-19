#!/usr/bin/env bash
# 系统更新 + 垃圾清理 一键脚本（2026-10-19 生成）
# 用法：sudo bash ~/备份/system-update-cleanup/update-and-clean.sh
# 幂等：可随时重复运行
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "==> [1/6] 刷新 apt 软件源"
apt-get update

echo "==> [2/6] 升级已安装的软件包"
apt-get full-upgrade -y -o Dpkg::Options::=--force-confold

echo "==> [3/6] 删除不再需要的软件包并清空 apt 下载缓存"
apt-get autoremove --purge -y
apt-get clean

echo "==> [4/6] 更新 snap 软件包（含 Firefox/Thunderbird/固件更新器）"
snap refresh || echo "⚠ 个别 snap 更新失败，可稍后重新运行本脚本"

echo "==> [5/6] 限制 snap 旧版本最多保留 2 个，并删除已禁用的旧版本"
snap set system refresh.retain=2
snap list --all | awk '/disabled/{print $1, $3}' | while read -r name rev; do
  snap remove "$name" --revision="$rev" || true
done

echo "==> [6/6] 收缩系统日志到 50M"
journalctl --vacuum-size=50M

echo
if [ -e /var/run/reboot-required ]; then
  echo "⚠ 系统提示需要重启以完成部分更新（例如新内核），方便时重启一次即可。"
else
  echo "✅ 全部完成，无需重启。"
fi
