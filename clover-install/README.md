# Clover 引导维护工具箱（装机完成 2026-10-18）

机器现状：Clover r5175 已装在 Ubuntu ESP (/boot/efi/EFI/CLOVER)，开机显示
Catalina 主题菜单，只有 windows / ubuntu 两个入口（自定义、Path 匹配、
Image 图标、FullTitle 字符串）。选 ubuntu 直达系统（GRUB 菜单已隐藏，
急需时开机按住 Shift/Esc 可调出）。8 秒不动自动进上次系统。

## 目录内容（保留部分）
- staging/        ESP 上 EFI/CLOVER 的完整镜像（重装的唯一事实来源）
- install.sh      一键重装/更新（改完 staging 后跑它，幂等）
- uninstall.sh    一键卸载 Clover 恢复原引导

## 常用调整
- 换主题: 下载主题目录放 staging/EFI/CLOVER/themes/<名>, 改
  staging config.plist 的 GUI/Theme, 再跑 install.sh
- 改超时: staging config.plist → Boot/Timeout（秒）
- Clover r5175 配置要点（踩坑记录）: 自定义入口图标键叫 Image 不是 Icon；
  FullTitle 要写字符串；Volume 匹配不可靠，用 Path-only+VolumeType=Internal；
  Hide 对自动条目无效，要控制条目数量用 GUI/Scan 各键全 false；
  Boot/Log 不是合法键，日志只要 EFI/CLOVER/misc 目录存在就会写

## 应急
- Clover 菜单异常 → 开机 F12 选 "ubuntu" 直达
- 日志在 /boot/efi/EFI/CLOVER/misc/（每次启动生成，排查专用）
