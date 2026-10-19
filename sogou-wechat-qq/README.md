# sogou-wechat-qq

在 Ubuntu 26.04.1 (Wayland/GNOME) 上安装搜狗输入法 + 微信 + QQ 三件套。
2026-10-19 全流程实测通过（sogoupinyin 4.2.1.145 / wechat 4.1.13.26 / linuxqq 3.2.34）。

## 内容

- `install-sogou-wechat-qq.sh` — 幂等一键安装：装 deb 包 + 补齐搜狗漏声明的两个
  依赖 + 写输入法环境变量 + 配置 fcitx 自启动（屏蔽 fcitx5）
- `download-debs.sh` — 三个官方 deb 的下载脚本，支持 `--check`（只验链接可达）
  与 `--force`（强制重下），已有文件自动跳过
- 三个 deb 共约 500MB，不入库；重装时先跑下载脚本再跑安装脚本即可

## 下载脚本的原理（各不相同，2026-10 实测）

| 软件 | 获取方式 |
|---|---|
| 搜狗 | 官网 `shurufa.sogou.com/linux` 页面 downloadConfig 给的 `ime-sec.gtimg.com` 链接直接下 403，域名换成 `ime.gtimg.com` 即可 |
| 微信 | `dldir1v6.qq.com` 稳定直链，偶发 403 带 `weixin.qq.com` Referer 即可 |
| QQ | `qqdl.gtimg.cn` 一律 403（非 IP 封锁，Referer/UA 都没用）：先 GET `im.qq.com/index/` 取 `tgw_l7_route` cookie，再 POST `im.qq.com` 的 `GetSign` 接口（头 `x-oidb: {"uint32_command":"0x9b8e","uint32_service_type":1}`）换带签名的临时链接。流程出处：AUR `linuxqq-nt` 的 `linuxqq-get-url.sh` |

## 26.04 的三个坑（脚本已绕过，留档备查）

1. **im-config 0.62 删除了 fcitx4 支持**（`/usr/share/im-config/data/` 只剩
   `23_fcitx5`），`im-config -n fcitx` 报 bogus configuration 退出。
   现改用 `/etc/environment` + XDG 自启动，不用 im-config。
2. **搜狗 deb 漏声明两个运行时依赖**：`libqt5quickwidgets5`、`libgsettings-qt1`。
   缺了它们 sogoupinyin-service 起不来，fcitx-sogoupinyin.so 在退出路径上
   double free 直接把 fcitx abort。脚本已显式安装。
3. **必须设置 `XMODIFIERS=@im=fcitx`**：否则 fcitx 检测到 ibus 占用 XIM 会
   自动退出（GNOME 的 ibus 在 XWayland 上注册了 XIM），触发同上的 abort。

## 使用

```bash
bash download-debs.sh                # 下载三个 deb（已存在的跳过）
sudo bash install-sogou-wechat-qq.sh # 安装 + 配置
# 然后注销并重新登录
```

登录后 Ctrl+Space 切换搜狗；应用菜单启动「微信」「QQ」。
若个别 GNOME/GTK4 应用打不了中文，登录界面右下角切 "Ubuntu on Xorg"。

## 备注

- fcitx 自启动在 `~/.config/autostart/fcitx-sogou.desktop`；fcitx5 已用
  `Hidden=true` 同名文件屏蔽。想改回 fcitx5 拼音：`sudo apt install
  fcitx5-chinese-addons`，删掉上述两个自启动文件、清掉 `/etc/environment`
  里四行 IM 变量。
- 升级：`bash download-debs.sh --force` 重下后 `sudo apt install ./*.deb`。
- 卸载：`sudo apt purge sogoupinyin wechat linuxqq`
