# install-scripts — Linux 软件安装/配置脚本合集

个人装机备份仓库：每次装软件/调系统沉淀下来的脚本、配置与踩坑记录集中存放，
重装系统或换新机时直接复用。全部在 Ubuntu 24.04/26.04 上实际执行验证过。

## 项目一览

| 目录 | 用途 | 入口 |
|---|---|---|
| [chrome-install/](chrome-install/) | Google Chrome 稳定版一键安装（自动下载官方 deb） | `sudo bash install-chrome.sh` |
| [clover-install/](clover-install/) | Clover r5175 引导 + Catalina 主题，UEFI 双系统开机菜单（含 ESP 完整镜像，可一键重装/卸载） | `sudo bash install.sh` / `uninstall.sh` |
| [codex-zh-linux/](codex-zh-linux/) | Codex 桌面应用（Linux）简体中文界面补丁，翻转 app.asar 内置 i18n 开关 | `sudo bash codex-zh-linux.sh` |
| [hermes-install/](hermes-install/) | Hermes Agent 更新用的本地 PyPI 加速代理（TLS 改写 → 清华镜像） | 见该目录 README |

每个目录内的 `README.md` 记录背景、用法、回滚方式和当时的踩坑要点。

## 网络环境说明（中国大陆网络，2026-10 实测）

- **github.com**：网页时好时坏，git clone/push TLS 握手经常中途卡死
  - clone 用前缀镜像：`https://gh-proxy.com/https://github.com/<org>/<repo>.git`
  - `api.github.com`、`raw.githubusercontent.com`、release 资产下载直连可用
  - SSH 方式 `ssh.github.com:443` 实测可通（本机已配置 `~/.ssh/config`）
- **PyPI 官方源**：Fastly 节点限速 5–140 KB/s → 用清华 tuna 镜像，或
  [hermes-install](hermes-install/) 的本地代理（lockfile 钉死官方域名时用后者）
- **dl.google.com**：国内 CDN 直连，速度很快，Chrome 无需镜像
- 本仓库首次上传是在 git push 不通的情况下走 `api.github.com` 完成的

## 环境

- 机器：UEFI 双 NVMe 双系统（Ubuntu 26.04 + Windows），中国大陆家宽网络
- 所有需要 root 的操作都写成幂等脚本，`sudo bash <脚本>` 一键执行
