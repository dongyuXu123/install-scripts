#!/usr/bin/env bash
# ClamAV 一键安装（Ubuntu 26.04）— 运行: sudo bash 01-install.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行：sudo bash $0"; exit 1; }

echo "==> [1/4] 安装 clamav + clamav-freshclam（Ubuntu 官方源）"
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y clamav clamav-freshclam

echo "==> [2/4] 首次更新病毒库（约 250MB，Cloudflare CDN 国内可直连）"
systemctl stop clamav-freshclam 2>/dev/null || true
if freshclam; then
    echo "病毒库更新完成"
else
    echo "!! freshclam 下载失败（网络波动），不影响安装，稍后补跑：sudo freshclam" >&2
fi

echo "==> [3/4] 开启病毒库自动更新服务（每日多次自动检查）"
systemctl enable --now clamav-freshclam

echo "==> [4/4] EICAR 自检（用行业标准的无害测试文件验证查毒能力）"
if ls /var/lib/clamav/daily.c* >/dev/null 2>&1; then
    T=$(mktemp -d)
    printf '%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$T/eicar.com"
    if clamscan --no-summary -i "$T/eicar.com" | grep -q FOUND; then
        echo "✓ 自检通过：ClamAV 正确检出测试文件（该文件无害，是杀毒行业通用测试样本）"
    else
        echo "!! 自检未检出，等病毒库下载完后可重跑本脚本或 sudo freshclam"
    fi
    rm -rf "$T"
else
    echo "!! 病毒库尚未下载完成，跳过自检。稍后运行：sudo freshclam"
fi

clamscan --version
echo
echo "安装完成。日常扫描用同目录下的 scan-下载.sh / scan-共享分区.sh（无需 sudo）"
