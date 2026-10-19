#!/bin/bash
# 下载搜狗输入法 / 微信 / QQ 三个官方 deb 到本脚本所在目录（供 install 脚本使用）
# 用法: bash download-debs.sh [--check|--force]
#   (默认)    下载缺失的 deb；目录里已有的文件跳过
#   --check   只验证三个下载链接是否可达（各拉 1KB），不下载
#   --force   忽略已有文件，强制重新下载
#
# 三个包获取方式各不相同（2026-10-19 实测）：
# - 搜狗: 官网 shurufa.sogou.com/linux 页面 downloadConfig 给的是
#   ime-sec.gtimg.com 链接，直接下 403；把域名换成 ime.gtimg.com 即可
# - 微信: dldir1v6.qq.com 稳定直链；偶发 403，带 weixin.qq.com Referer 即可
# - QQ:   qqdl.gtimg.cn 一律 403（非 IP 封锁，加 Referer/UA 无效），必须：
#   1) GET https://im.qq.com/index/ 取 tgw_l7_route cookie
#   2) POST im.qq.com 的 GetSign 接口换带签名的临时链接
#   流程出处: AUR linuxqq-nt 的 linuxqq-get-url.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

MODE=download; FORCE=0
case "${1:-}" in
    --check) MODE=check ;;
    --force) FORCE=1 ;;
    "") ;;
    *) echo "用法: bash $0 [--check|--force]"; exit 1 ;;
esac

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/155.0.0.0 Safari/537.36"

sogou_url() {
    local link
    link=$(curl -fsSL --connect-timeout 15 -A "$UA" https://shurufa.sogou.com/linux \
        | grep -oE 'https://ime-sec\.gtimg\.com/[^\\"]*_amd64\.deb' | head -1 \
        | sed 's/ime-sec\.gtimg\.com/ime.gtimg.com/')
    [[ -n $link ]] || { echo "错误: 无法从搜狗官网解析下载链接" >&2; return 1; }
    echo "$link"
}

qq_raw_url() {
    curl -fsSL --connect-timeout 15 -A "$UA" \
        https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js \
        | grep -oE '"deb":"https://qqdl[^"]*amd64[^"]*\.deb"' | head -1 | cut -d'"' -f4
}

qq_signed_url() {
    local raw cookie
    raw="$(qq_raw_url)"
    [[ -n $raw ]] || { echo "错误: 无法从 linuxConfig.js 解析 QQ 链接" >&2; return 1; }
    cookie=$(curl -fsSL --connect-timeout 15 -A "$UA" -c - https://im.qq.com/index/ -o /dev/null \
        | awk '/tgw_l7_route/{print $NF}')
    [[ -n $cookie ]] || { echo "错误: 未取到 tgw_l7_route cookie" >&2; return 1; }
    python3 - "$raw" "$cookie" <<'PYEOF'
import json, sys, urllib.request
req = urllib.request.Request(
    "https://im.qq.com/http2rpc/gotrpc/noauth/trpc.qqntv2.urlsign.UrlSign/GetSign",
    data=json.dumps({"url": sys.argv[1]}).encode(),
    headers={"Content-Type": "application/json", "Origin": "https://im.qq.com",
             "Referer": "https://im.qq.com", "User-Agent": "Mozilla/5.0",
             "Cookie": "tgw_l7_route=" + sys.argv[2],
             "x-oidb": '{"uint32_command":"0x9b8e","uint32_service_type":1}'})
with urllib.request.urlopen(req, timeout=30) as r:
    print(json.load(r)["data"]["url"])
PYEOF
}

WX_URL="https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb"
WX_FILE="WeChatLinux_x86_64.deb"
SO_URL="$(sogou_url)"; SO_FILE="$(basename "$SO_URL")"
QQ_URL="$(qq_signed_url)"; QQ_FILE="$(basename "$(qq_raw_url)")"

if [[ $MODE == check ]]; then
    for u in "$SO_URL" "$WX_URL" "$QQ_URL"; do
        code=$(curl -sS -m 20 -A "$UA" -e https://weixin.qq.com/ -r 0-1023 \
            -o /dev/null -w '%{http_code}' "$u")
        [[ $code == 206 || $code == 200 ]] \
            && echo "可达 ($code): ${u:0:80}..." \
            || { echo "不可达 ($code): $u" >&2; exit 1; }
    done
    echo "三个下载链接全部验证通过 ✓"
    exit 0
fi

echo "==> 搜狗输入法: $SO_FILE"
if [[ $FORCE -eq 0 && -f $SO_FILE ]]; then echo "    已存在，跳过"; else curl -fL --retry 3 --connect-timeout 15 -A "$UA" -o "$SO_FILE" "$SO_URL"; fi

echo "==> 微信: $WX_FILE"
if [[ $FORCE -eq 0 && -f $WX_FILE ]]; then echo "    已存在，跳过"; else curl -fL --retry 3 --connect-timeout 15 -A "$UA" -e https://weixin.qq.com/ -o "$WX_FILE" "$WX_URL"; fi

echo "==> QQ: $QQ_FILE"
if [[ $FORCE -eq 0 && -f $QQ_FILE ]]; then echo "    已存在，跳过"; else curl -fL --retry 3 --connect-timeout 15 -A "$UA" -o "$QQ_FILE" "$QQ_URL"; fi

echo
echo "全部就绪: $(ls -lh ./*.deb | awk '{print $NF, $5}' | tr '\n' ' ')"
echo "接着运行: sudo bash install-sogou-wechat-qq.sh"
