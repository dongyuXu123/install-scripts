# clamav安装

Ubuntu 26.04 上的 ClamAV 杀毒方案：**只装按需扫描**（clamscan + 病毒库每日自动更新），
不装常驻实时监控——clamd/clamonacc 常驻要占 1GB+ 内存，家用按需扫就够了。
2026-10-19 安装并用 EICAR 标准测试样本验证通过（clamav 1.5.4）。

## 内容

- `01-install.sh` — sudo 一键安装：装 clamav + clamav-freshclam → 首次更新病毒库
  （约 250MB）→ 开启每日自动更新 → EICAR 自检。幂等，可重复跑
- `scan-下载.sh` — 免 sudo 扫描 `~/下载`（或指定目录），只报告染毒文件
- `scan-共享分区.sh` — 免 sudo 扫描"linux与windows共用"NTFS 分区（827G，
  可能跑几个小时），完整日志按时间戳存本目录

## 使用

```bash
sudo bash 01-install.sh   # 安装（仅需一次）
bash scan-下载.sh          # 日常：扫下载目录
bash scan-共享分区.sh      # 大扫除：扫共用分区
```

## 已知坑

- `01-install.sh` 的 EICAR 自检如果在 freshclam 服务刚拉起、正在替换库文件时运行，
  可能误报"未检出"——复测即过，属时序问题不是故障。

## 备注

- 病毒库走 `database.clamav.net` 的 Cloudflare CDN，国内直连，无需镜像
- 卸载：`sudo apt purge clamav clamav-freshclam && sudo rm -rf /var/lib/clamav`
- 未做（需要时再加）：clamd/clamonacc 实时监控；Windows 内部盘只读挂载扫描。
  另：Sophos/Comodo 免费 Linux 版已停产、ClamTk 已弃维护，勿浪费时间找替代
