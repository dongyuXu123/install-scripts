#!/bin/bash
# 一键安装：搜狗输入法(fcitx4) + 微信 + QQ —— Ubuntu 26.04 (Wayland/GNOME)
# 用法: sudo bash install-sogou-wechat-qq.sh
# 幂等可重复执行；完成后【注销并重新登录】生效。
#
# 注意：26.04 的 im-config 0.62 已删除 fcitx4 支持（data/ 只有 23_fcitx5），
# `im-config -n fcitx` 会报 bogus configuration 退出，因此本脚本不使用
# im-config，改用 /etc/environment 环境变量 + XDG 自启动实现同等效果。
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "请用 sudo 运行: sudo bash $0"
    exit 1
fi

DL="$(cd "$(dirname "$0")" && pwd)"
cd "$DL"

USER_NAME="${SUDO_USER:-root}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

echo "== 1/4 安装三个 deb 及依赖（已装则跳过） =="
if ls ./*.deb >/dev/null 2>&1; then
    apt-get install -y ./*.deb || true
fi
# 搜狗 deb 漏声明的两个运行时依赖（老版本 Ubuntu 会被连带装上，26.04 不会）
apt-get install -y libqt5quickwidgets5 libgsettings-qt1
apt-get install -y -f

echo "== 2/4 写入输入法环境变量 (/etc/environment) =="
touch /etc/environment
grep -q '^GTK_IM_MODULE=' /etc/environment || cat >> /etc/environment <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
EOF

echo "== 3/4 配置自启动：启动 fcitx，屏蔽 fcitx5 =="
AUTOSTART="$USER_HOME/.config/autostart"
install -d -o "$USER_NAME" -g "$USER_NAME" "$AUTOSTART"

cat > "$AUTOSTART/fcitx-sogou.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx (搜狗输入法)
Exec=fcitx -d
Terminal=false
EOF

cat > "$AUTOSTART/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5
Hidden=true
Terminal=false
EOF

chown "$USER_NAME:$USER_NAME" \
    "$AUTOSTART/fcitx-sogou.desktop" "$AUTOSTART/org.fcitx.Fcitx5.desktop"

echo "== 4/4 验证 =="
dpkg -s sogoupinyin wechat linuxqq >/dev/null && echo "三个软件包: 已安装 ✓"
ldconfig -p | grep -q libQt5QuickWidgets.so.5 && echo "Qt5 运行库: 已安装 ✓"

echo
echo "全部完成！请【注销并重新登录】使输入法环境变量生效。"
echo "登录后按 Ctrl+Space 切换搜狗拼音；应用菜单启动「微信」和「QQ」。"
