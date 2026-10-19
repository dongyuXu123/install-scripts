#!/usr/bin/env bash
# =====================================================================
# Ubuntu 系统镜像快照 —— 一键创建
# 用法：  sudo bash 创建系统镜像快照.sh
# 作用：  把根分区(/)和 EFI 分区打成压缩镜像，存到共用数据分区
#         /dev/nvme0n1p3（linux与windows共用），并在镜像目录里自动生成
#         《恢复系统.sh》一键还原脚本和《恢复说明.md》
# 预计：  读盘 93G，zstd 多核压缩，全程约 5–15 分钟
# 注意：  运行期间尽量不要使用电脑（不装软件、不拷大文件、别关机）
# =====================================================================
set -euo pipefail

SRC_ROOT="/dev/nvme0n1p4"    # 根分区 /
SRC_ESP="/dev/nvme0n1p1"     # EFI 分区 /boot/efi（ESP_UBUNTU）
DATA_PART="/dev/nvme0n1p3"   # 镜像存放地：共用 NTFS 数据分区
SYS_DISK="/dev/nvme0n1"
DATA_DISK="/dev/nvme1n1"
MIN_FREE_GB=35
STAMP="$(date +%Y%m%d_%H%M)"

log(){ printf '\n\033[1;32m===== %s =====\033[0m\n' "$*"; }
die(){ echo "错误：$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 sudo 运行：sudo bash $0"
[ "$(findmnt -n -o SOURCE /)" = "$SRC_ROOT" ] || die "当前根分区不是 $SRC_ROOT，请检查脚本配置"
[ "$(findmnt -n -o SOURCE /boot/efi)" = "$SRC_ESP" ] || die "当前 EFI 分区不是 $SRC_ESP，请检查脚本配置"

log "0/6 挂载数据分区 $DATA_PART"
MNT=""
if findmnt -rn -S "$DATA_PART" >/dev/null; then
  MNT="$(findmnt -rn -S "$DATA_PART" -o TARGET | head -n1)"
  echo "$DATA_PART 已挂载在 $MNT，直接使用"
else
  MNT="/mnt/ntfs-snapshot"
  mkdir -p "$MNT"
  if ! mount -t ntfs3 -o rw "$DATA_PART" "$MNT" 2>/dev/null; then
    if ! mount -t ntfs3 -o rw,force "$DATA_PART" "$MNT" 2>/dev/null; then
      mount -t ntfs-3g -o rw "$DATA_PART" "$MNT" \
        || die "无法挂载 $DATA_PART。若提示卷被占用/脏卷，请先到 Windows 端正常关机一次再试"
    fi
  fi
fi
trap 'umount "$MNT" 2>/dev/null || true' EXIT

touch "$MNT/.rwtest" 2>/dev/null || die "$MNT 挂载为只读，无法写入镜像"
rm -f "$MNT/.rwtest"

FREE_GB="$(df -BG --output=avail "$MNT" | tail -n1 | tr -dc '0-9')"
[ "$FREE_GB" -ge "$MIN_FREE_GB" ] || die "$DATA_PART 只剩 ${FREE_GB}GB 可用，至少需要 ${MIN_FREE_GB}GB"
echo "目标分区可用空间 ${FREE_GB}GB，足够。"

SNAP="$MNT/系统镜像快照_$STAMP"
mkdir -p "$SNAP"

# 选择压缩器：优先 zstd（多核，快）
if command -v zstd >/dev/null 2>&1; then EXT="zst"; else EXT="gz"; fi

log "1/6 记录分区表与系统信息"
sfdisk -d "$SYS_DISK"  > "$SNAP/分区表_nvme0n1.sfdisk"
sfdisk -d "$DATA_DISK" > "$SNAP/分区表_nvme1n1.sfdisk"
blkid > "$SNAP/blkid.txt"
cp /etc/fstab "$SNAP/fstab.txt"
tar czf "$SNAP/apt源配置.tar.gz" -C /etc/apt sources.list sources.list.d 2>/dev/null || true
dpkg --get-selections > "$SNAP/已安装软件包.txt"
apt-mark showmanual > "$SNAP/手动安装软件包.txt" || true
snap list > "$SNAP/snap列表.txt" 2>/dev/null || true
flatpak list > "$SNAP/flatpak列表.txt" 2>/dev/null || true

log "2/6 备份根分区镜像 root.img.$EXT（最耗时，约 5–10 分钟）"
sync
if [ "$EXT" = zst ]; then
  dd if="$SRC_ROOT" bs=8M status=progress | zstd -3 -T0 -q -f -o "$SNAP/root.img.zst"
else
  dd if="$SRC_ROOT" bs=8M status=progress | gzip -1 > "$SNAP/root.img.gz"
fi

log "3/6 备份 EFI 分区镜像 EFI.img.$EXT"
if [ "$EXT" = zst ]; then
  dd if="$SRC_ESP" bs=8M status=progress | zstd -3 -T0 -q -f -o "$SNAP/EFI.img.zst"
else
  dd if="$SRC_ESP" bs=8M status=progress | gzip -1 > "$SNAP/EFI.img.gz"
fi

log "4/6 校验镜像完整性（zstd -t 全量解压验证）"
if [ "$EXT" = zst ]; then
  zstd -t "$SNAP/root.img.$EXT" && zstd -t "$SNAP/EFI.img.$EXT"
else
  gzip -t "$SNAP/root.img.$EXT" && gzip -t "$SNAP/EFI.img.$EXT"
fi
echo "镜像完整，可正常解压。"

log "5/6 生成校验和与还原文件"
( cd "$SNAP" && sha256sum "root.img.$EXT" "EFI.img.$EXT" > SHA256SUMS.txt )

cat > "$SNAP/恢复系统.sh" <<'ZEOF'
#!/usr/bin/env bash
# =====================================================================
# 一键还原 —— 必须在 Ubuntu Live USB（"试用 Ubuntu"模式）中运行：
#   sudo bash 恢复系统.sh
# 会把镜像覆盖写回系统分区和 EFI 分区，还原后系统回到快照时点。
# =====================================================================
set -euo pipefail

ROOT_DEV="/dev/nvme0n1p4"    # 还原目标：系统分区
ESP_DEV="/dev/nvme0n1p1"     # 还原目标：EFI 分区
IMG_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_IMG="$IMG_DIR/root.img.@EXT@"
ESP_IMG="$IMG_DIR/EFI.img.@EXT@"

[ "$(id -u)" = 0 ] || { echo "错误：请用 sudo 运行"; exit 1; }

case "@EXT@" in
  zst) command -v zstd  >/dev/null 2>&1 || { echo "错误：缺少 zstd。先执行：sudo apt update && sudo apt install -y zstd"; exit 1; }; DEC=(zstd -dc);;
  gz)  command -v gzip  >/dev/null 2>&1 || { echo "错误：缺少 gzip"; exit 1; }; DEC=(gzip -dc);;
  *) echo "错误：未知扩展名 @EXT@"; exit 1;;
esac

for f in "$ROOT_IMG" "$ESP_IMG"; do [ -f "$f" ] || { echo "错误：找不到镜像 $f"; exit 1; }; done
if findmnt -rn -S "$ROOT_DEV" >/dev/null; then echo "错误：$ROOT_DEV 正被挂载，请先卸载再还原"; exit 1; fi

echo "即将把镜像覆盖写回以下分区（目标分区上现有数据全部丢失！）："
echo "  root.img.@EXT@  -->  $ROOT_DEV  (系统 /)"
echo "  EFI.img.@EXT@   -->  $ESP_DEV   (EFI 引导)"
echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/nvme0n1
echo
read -r -p "确认还原？输入大写 YES 继续：" ANS
[ "$ANS" = "YES" ] || { echo "已取消，未做任何更改"; exit 1; }

echo "== [1/2] 还原根分区（约 5–15 分钟）=="
"${DEC[@]}" "$ROOT_IMG" | dd of="$ROOT_DEV" bs=8M status=progress
echo "== [2/2] 还原 EFI 分区 =="
"${DEC[@]}" "$ESP_IMG" | dd of="$ESP_DEV" bs=8M status=progress
sync
echo
echo "✅ 还原完成！输入 reboot 重启并拔掉 U 盘即可进入快照时点的系统。"
ZEOF

cat > "$SNAP/恢复说明.md" <<'ZEOF'
# Ubuntu 系统镜像快照 —— 恢复说明

快照时间：@STAMP@

## 本目录内容
| 文件 | 说明 |
|---|---|
| root.img.@EXT@ | 根分区 / 的完整镜像（/dev/nvme0n1p4，ext4，93.1G 分区，含 /home） |
| EFI.img.@EXT@ | EFI 引导分区镜像（/dev/nvme0n1p1，vfat 300M，含 GRUB） |
| 分区表_nvme0n1.sfdisk / 分区表_nvme1n1.sfdisk | 两块硬盘的分区表文本备份 |
| SHA256SUMS.txt | 镜像校验和，复制到别处后可用 `sha256sum -c SHA256SUMS.txt` 验证 |
| 已安装软件包.txt / 手动安装软件包.txt / snap列表.txt / apt源配置.tar.gz | 重装时的参考信息 |
| 恢复系统.sh | 一键还原脚本（在 Live USB 里运行） |

## 什么时候需要还原
系统无法启动、大版本更新后崩溃、配置改坏无法挽回等。还原会把系统恢复到快照时点。
注意：/home 也在根分区里，**快照之后新产生的文件会被覆盖丢失**，需要的话先在 Live
环境里把新文件从坏系统分区拷出来再还原。

## 前提：准备一个 Ubuntu Live U 盘（平时放抽屉，用时救命）
- Windows 下：下载 Ubuntu 26.04 桌面版 ISO，用 Rufus 写入一个 ≥4G 的 U 盘
- Ubuntu 下：用"启动盘创建器"(Startup Disk Creator) 制作

## 标准还原步骤（硬盘没坏，只是系统坏了）
1. 插 Live U 盘 → 开机进 U 盘（Clover 或 UEFI 启动菜单里选）→ 选"试用 Ubuntu (Try Ubuntu)"
2. 打开终端（Ctrl+Alt+T），执行：
   ```
   sudo mount -o ro /dev/nvme0n1p3 /mnt     # 挂载镜像所在的数据分区（只读即可）
   cd /mnt/系统镜像快照_@STAMP@/
   sudo bash 恢复系统.sh                     # 按提示输入 YES，约 10–20 分钟
   ```
3. 完成后 `reboot`、拔 U 盘。UUID 不变，fstab/GRUB 均有效，无需其他操作。
   - 若提示没有 zstd：`sudo apt update && sudo apt install -y zstd` 后重跑
   - 手动方式（脚本不可用时）：
     ```
     zstd -dc root.img.@EXT@ | sudo dd of=/dev/nvme0n1p4 bs=8M status=progress
     zstd -dc EFI.img.@EXT@  | sudo dd of=/dev/nvme0n1p1 bs=8M status=progress
     sync
     ```

## 只是引导坏了（系统本身没坏，GRUB/启动项丢了）
不必整盘还原，进 Live 环境后：
```
sudo mount /dev/nvme0n1p4 /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done
sudo chroot /mnt grub-install /dev/nvme0n1
sudo chroot /mnt update-grub
```
图形化替代：Live 环境里安装 Boot-Repair 工具一键修复。

## 整块硬盘报废的极端情况
本镜像只覆盖系统分区和 EFI 分区，**不含数据分区（linux与windows共用）和 Windows**。
换新硬盘时先恢复分区表再写镜像：
```
sudo sfdisk /dev/nvme0n1 < 分区表_nvme0n1.sfdisk
# 然后按上面"标准还原步骤"把 root/EFI 镜像写回 p4/p1
```
新盘比旧盘小时需先改 sfdisk 文件中最后一个分区的大小（还原要求目标分区 ≥ 93.1G）。

## 平时建议
- 镜像与系统在同一块盘上：**能防系统崩溃，防不了硬盘物理损坏**。建议把整个
  "系统镜像快照_*" 目录再复制一份到移动硬盘或网盘。
- 大版本升级（26.04 → 下个版本）之前，重新跑一次创建脚本做新快照。
- 想要日常自动增量备份，可另装 Timeshift（注意其快照只能放 Linux 文件系统分区，
  本机只有根分区自己可用，会占约 28G 空间，可选）。
ZEOF

sed -i "s/@EXT@/$EXT/g; s/@STAMP@/$STAMP/g" "$SNAP/恢复系统.sh" "$SNAP/恢复说明.md"

log "6/6 完成"
ls -lh "$SNAP"
echo
echo "✅ 镜像快照已创建：$SNAP"
echo "   还原方法见同目录《恢复说明.md》。"
echo "   建议：抽空制作一个 Ubuntu Live U 盘放手边，并把该目录复制一份到移动硬盘。"
