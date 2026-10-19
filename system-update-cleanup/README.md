# 系统更新与垃圾清理（2026-10-19）

## 背景

对 Ubuntu 26.04 做一次例行维护：更新全部软件、清理缓存类垃圾文件。

摸底结论（清理前的占用）：

| 项目 | 大小 | 说明 |
|---|---|---|
| `/var/cache/apt` | 505M | apt 下载缓存，可再生 |
| `~/.npm` | 98M | node/npm 已卸载后的孤儿缓存，**已删除**（无需 root，当天已处理） |
| `/var/log/journal` | 89M | 系统日志，脚本收缩到 50M |
| `/var/crash/*.crash` | 162K | ZCode 当天的崩溃转储，**已删除** |
| 旧内核 | 无 | 只有一个内核 7.0.0-38，无旧内核可清 |

其他检查过、无需处理：无 flatpak、无 docker、无 pip（系统 python 未装；Hermes 在 `~/.hermes` 自带独立环境）、回收站已清空、`/tmp` 仅 460K。apt 源已是国内镜像 `cn.archive.ubuntu.com`，无需改动。

## 用法

需要 root 权限的部分已打包成一键脚本，请自己在终端运行：

```bash
sudo bash ~/备份/system-update-cleanup/update-and-clean.sh
```

脚本做 6 件事：apt 更新源 → 全量升级软件包 → autoremove 清理无用包并清空 apt 缓存 → snap 全量更新 → 限制 snap 旧版本保留 2 个并删除已禁用旧版 → 系统日志收缩到 50M。

脚本**幂等**，可随时重复运行；遇到个别 snap 更新失败，稍后重跑即可。结束时若提示需重启（通常是新内核生效），方便时重启一次。

## 回滚 / 风险说明

- 软件升级本身没有回滚，但均为 Ubuntu 官方源和 snap 商店的正式版本，风险低。
- 清理掉的全部是可再生缓存和日志，不影响任何已安装软件和数据。
- 若想恢复 snap 旧版本保留数，`sudo snap set system refresh.retain=3`（默认即 3）。
- 升级配置文件时脚本采用"保留现有配置"策略（`--force-confold`），不会改动你手工调过的系统配置。
