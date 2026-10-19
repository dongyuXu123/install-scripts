#!/usr/bin/env bash
# =====================================================================
# Ubuntu 系统镜像快照 —— 一键创建（v2：设备名全自动探测）
# 用法：  sudo bash 创建系统镜像快照.sh
# 说明：  本机两块 NVMe 盘的编号(nvme0/nvme1)重启后可能互换，
#         因此所有分区都在运行时自动探测，绝不写死设备名：
#           · 根分区/EFI 分区 ← 从当前挂载表取
#           · 镜像存放分区   ← 按卷标"linux与windows共用"找 NTFS
#           · 还原目标       ← 快照内《恢复系统.sh》按 UUID 自动定位
# 作用：  把根分区(/)和 EFI 分区打成压缩镜像，并在镜像目录里自动生成
#         《恢复系统.sh》一键还原脚本和《恢复说明.md》
# 预计：  全程约 5–15 分钟；运行期间尽量别用电脑（不装软件、不拷大文件）
# =====================================================================
set -euo pipefail

MIN_FREE_GB=35
STAMP="$(date +%Y%m%d_%H%M)"

log(){ printf '\n\033[1;32m===== %s =====\033[0m\n' "$*"; }
die(){ echo "错误：$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 sudo 运行：sudo bash $0"

log "0/7 自动探测分区"
SRC_ROOT="$(findmnt -nro SOURCE /)"
SRC_ESP="$(findmnt -nro SOURCE /boot/efi)"
[ -b "$SRC_ROOT" ] || die "根分区 $SRC_ROOT 不是块设备"
[ -b "$SRC_ESP" ]  || die "EFI 分区 $SRC_ESP 不是块设备"
SYS_DISK="/dev/$(lsblk -no PKNAME "$SRC_ROOT" | head -n1)"
[ -b "$SYS_DISK" ] || die "找不到根分区所在的硬盘"
echo "  系统分区 : $SRC_ROOT  （所在盘 $SYS_DISK）"
echo "  EFI 分区 : $SRC_ESP"

# 镜像存放分区：优先按卷标找 NTFS（注意 lsblk -r 会把中文转义成 \x..，不能用 raw 模式比对中文）
DATA_PART=""
if [ -e "/dev/disk/by-label/linux与windows共用" ]; then
  DATA_PART="$(readlink -f "/dev/disk/by-label/linux与windows共用")"
fi
if [ -z "$DATA_PART" ]; then
  DATA_PART="$(lsblk -no PATH,LABEL,FSTYPE | awk '$3=="ntfs" && $2=="linux与windows共用"{print $1; exit}')"
fi
if [ -z "$DATA_PART" ]; then
  DATA_PART="$(lsblk -rno PATH,FSTYPE,SIZE "$SYS_DISK" | awk '$2=="ntfs"{print $3, $1}' | sort -rn | head -n1 | awk '{print $2}')"
  [ -n "$DATA_PART" ] || die "在 $SYS_DISK 上没找到 NTFS 数据分区"
  echo "  （未按卷标找到，改用本盘最大 NTFS 分区）"
fi
[ "$DATA_PART" != "$SRC_ROOT" ] && [ "$DATA_PART" != "$SRC_ESP" ] || die "数据分区探测异常：$DATA_PART 与系统分区重合"
[ "$(lsblk -no FSTYPE "$DATA_PART")" = ntfs ] || die "$DATA_PART 不是 NTFS 分区"
echo "  镜像存到 : $DATA_PART"

# UUID 是还原时的定位依据（设备编号会互换，UUID 不会变）
ROOT_UUID="$(lsblk -no UUID "$SRC_ROOT")"
ESP_UUID="$(lsblk -no UUID "$SRC_ESP")"
[ -n "$ROOT_UUID" ] && [ -n "$ESP_UUID" ] || die "读取分区 UUID 失败"

log "1/7 挂载数据分区 $DATA_PART"
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

log "2/7 记录分区表与系统信息"
for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}'); do
  sfdisk -d "/dev/$d" > "$SNAP/分区表_${d}.sfdisk"
done
blkid > "$SNAP/blkid.txt"
cp /etc/fstab "$SNAP/fstab.txt"
tar czf "$SNAP/apt源配置.tar.gz" -C /etc/apt sources.list sources.list.d 2>/dev/null || true
dpkg --get-selections > "$SNAP/已安装软件包.txt"
apt-mark showmanual > "$SNAP/手动安装软件包.txt" || true
snap list > "$SNAP/snap列表.txt" 2>/dev/null || true
flatpak list > "$SNAP/flatpak列表.txt" 2>/dev/null || true

log "3/7 备份根分区镜像 root.img.$EXT（最耗时，约 5–10 分钟）"
sync
if [ "$EXT" = zst ]; then
  dd if="$SRC_ROOT" bs=8M status=progress | zstd -3 -T0 -q -f -o "$SNAP/root.img.zst"
else
  dd if="$SRC_ROOT" bs=8M status=progress | gzip -1 > "$SNAP/root.img.gz"
fi

log "4/7 备份 EFI 分区镜像 EFI.img.$EXT"
if [ "$EXT" = zst ]; then
  dd if="$SRC_ESP" bs=8M status=progress | zstd -3 -T0 -q -f -o "$SNAP/EFI.img.zst"
else
  dd if="$SRC_ESP" bs=8M status=progress | gzip -1 > "$SNAP/EFI.img.gz"
fi

log "5/7 校验镜像完整性（全量解压验证）"
if [ "$EXT" = zst ]; then
  zstd -t "$SNAP/root.img.$EXT" && zstd -t "$SNAP/EFI.img.$EXT"
else
  gzip -t "$SNAP/root.img.$EXT" && gzip -t "$SNAP/EFI.img.$EXT"
fi
echo "镜像完整，可正常解压。"

log "6/7 生成校验和与还原文件"
( cd "$SNAP" && sha256sum "root.img.$EXT" "EFI.img.$EXT" > SHA256SUMS.txt )

cat > "$SNAP/恢复系统.sh" <<'ZEOF'
#!/usr/bin/env bash
# =====================================================================
# 一键还原 —— 必须在 Ubuntu Live USB（"试用 Ubuntu"模式）中运行：
#   sudo bash 恢复系统.sh
# 会把镜像覆盖写回系统分区和 EFI 分区，还原后系统回到快照时点。
# 注意：本机两块 NVMe 编号(nvme0/nvme1)重启后可能互换！
#       本脚本按 UUID 自动定位目标分区，不靠 nvme 编号认盘。
# =====================================================================
set -euo pipefail

ROOT_UUID="@ROOT_UUID@"
ESP_UUID="@ESP_UUID@"
ROOT_FALLBACK="@ROOT@"     # UUID 定位失败时的备用设备名
ESP_FALLBACK="@ESP@"
IMG_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_IMG="$IMG_DIR/root.img.@EXT@"
ESP_IMG="$IMG_DIR/EFI.img.@EXT@"

[ "$(id -u)" = 0 ] || { echo "错误：请用 sudo 运行"; exit 1; }

case "@EXT@" in
  zst) command -v zstd >/dev/null 2>&1 || { echo "错误：缺少 zstd。先执行：sudo apt update && sudo apt install -y zstd"; exit 1; }; DEC=(zstd -dc);;
  gz)  command -v gzip >/dev/null 2>&1 || { echo "错误：缺少 gzip"; exit 1; }; DEC=(gzip -dc);;
  *) echo "错误：未知扩展名 @EXT@"; exit 1;;
esac

pick(){  # pick <UUID> <备用设备名> → 结果存入 TARGET
  TARGET=""
  local d=""
  [ -n "$1" ] && d="$(blkid -o device -t "UUID=$1" 2>/dev/null | head -n1)"
  [ -z "$d" ] && [ -b "$2" ] && d="$2"
  [ -n "$d" ] || return 1
  TARGET="$d"
}

pick "$ROOT_UUID" "$ROOT_FALLBACK" \
  || die "找不到系统分区还原目标：既没有 UUID=$ROOT_UUID 的分区，也没有 $ROOT_FALLBACK 设备。请用 lsblk 和 blkid 手工确认目标后，编辑本脚本顶部变量再运行"
ROOT_DEV="$TARGET"
pick "$ESP_UUID" "$ESP_FALLBACK" \
  || die "找不到 EFI 分区还原目标：既没有 UUID=$ESP_UUID 的分区，也没有 $ESP_FALLBACK 设备"
ESP_DEV="$TARGET"

for f in "$ROOT_IMG" "$ESP_IMG"; do [ -f "$f" ] || { echo "错误：找不到镜像 $f"; exit 1; }; done
if findmnt -rn -S "$ROOT_DEV" >/dev/null; then
  echo "错误：$ROOT_DEV 正被挂载（可能是你为拷文件挂载的），请先 sudo umount 后再还原"; exit 1
fi

echo "即将把镜像覆盖写回以下分区（目标分区上现有数据全部丢失！）："
echo "  root.img.@EXT@  -->  $ROOT_DEV"
echo "  EFI.img.@EXT@   -->  $ESP_DEV"
echo
echo "当前硬盘布局如下，请务必核对上面两个目标没有指错盘（尤其别写到 Windows 分区）："
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -v '^loop' || lsblk
echo
read -r -p "确认还原？输入大写 YES 继续：" ANS
[ "$ANS" = "YES" ] || { echo "已取消，未做任何更改"; exit 1; }

echo "== [1/2] 还原系统分区（约 5–15 分钟）=="
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

> ⚠️ 本机两块 NVMe 盘的编号（nvme0/nvme1）重启后可能互换！
> 认盘不要凭 nvme 编号记忆，以 **UUID** 或**卷标**为准。

## 本目录内容
| 文件 | 说明 |
|---|---|
| root.img.@EXT@ | 系统分区 @ROOT@ 的完整镜像（ext4，93.1G 分区，含 /home），UUID @ROOT_UUID@ |
| EFI.img.@EXT@ | EFI 引导分区 @ESP@ 的镜像（vfat 300M，含 GRUB），UUID @ESP_UUID@ |
| 分区表_*.sfdisk | 每块硬盘的分区表文本备份 |
| SHA256SUMS.txt | 镜像校验和，复制到别处后可用 `sha256sum -c SHA256SUMS.txt` 验证 |
| 已安装软件包.txt / 手动安装软件包.txt / snap列表.txt / apt源配置.tar.gz | 重装时的参考信息 |
| 恢复系统.sh | 一键还原脚本（在 Live USB 里运行，按 UUID 自动定位目标分区） |

## 什么时候需要还原
系统无法启动、大版本更新后崩溃、配置改坏无法挽回等。还原会把系统恢复到快照时点。
注意：/home 也在系统分区里，**快照之后新产生的文件会被覆盖丢失**；需要的话先在
Live 环境里把新文件从坏系统分区拷出来再还原。

## 前提：准备一个 Ubuntu Live U 盘（平时放抽屉，用时救命）
- Windows 下：下载 Ubuntu 26.04 桌面版 ISO，用 Rufus 写入一个 ≥4G 的 U 盘
- Ubuntu 下：用"启动盘创建器"(Startup Disk Creator) 制作

## 标准还原步骤（硬盘没坏，只是系统坏了）
1. 插 Live U 盘 → 开机进 U 盘（Clover 或 UEFI 启动菜单里选）→ 选"试用 Ubuntu (Try Ubuntu)"
2. 打开终端（Ctrl+Alt+T），执行：
   ```
   sudo mount -o ro @DATA@ /mnt        # 挂载镜像所在的数据分区（卷标"linux与windows共用"，只读即可）
   cd /mnt/系统镜像快照_@STAMP@/
   sudo bash 恢复系统.sh                # 按 UUID 自动定位，按提示输入 YES，约 10–20 分钟
   ```
3. 完成后 `reboot`、拔 U 盘。UUID 不变，fstab/GRUB 均有效，无需其他操作。
   - 若提示没有 zstd：`sudo apt update && sudo apt install -y zstd` 后重跑
   - 若挂载数据分区报"卷被占用/脏卷"：先去 Windows 正常关机一次再来
   - 手动方式（脚本不可用时；**先 `lsblk`/`sudo blkid` 确认目标，别认错盘**）：
     ```
     sudo blkid                                  # 找 UUID=@ROOT_UUID@ 和 @ESP_UUID@ 对应的分区
     zstd -dc root.img.@EXT@ | sudo dd of=<系统分区> bs=8M status=progress
     zstd -dc EFI.img.@EXT@  | sudo dd of=<EFI分区> bs=8M status=progress
     sync
     ```

## 只是引导坏了（系统本身没坏，GRUB/启动项丢了）
不必整盘还原，进 Live 环境后（分区名以 `lsblk` 实际为准）：
```
sudo mount /dev/nvme?n1p4 /mnt          # 系统分区：ext4、93.1G 那个
sudo mount /dev/nvme?n1p1 /mnt/boot/efi # EFI 分区：vfat、卷标 ESP_UBUNTU 那个
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done
sudo chroot /mnt grub-install /dev/nvme?n1   # 系统所在盘
sudo chroot /mnt update-grub
```
图形化替代：Live 环境里安装 Boot-Repair 工具一键修复。

## 整块硬盘报废的极端情况
本镜像只覆盖系统分区和 EFI 分区，**不含数据分区（linux与windows共用）和 Windows**。
换新硬盘时先恢复分区表再写镜像：
```
sudo sfdisk /dev/nvme?n1 < 分区表_<对应盘名>.sfdisk
# 然后按上面"标准还原步骤"写回 root/EFI 镜像（新分区没有旧 UUID 时，
# 恢复系统.sh 会退回用设备名匹配，注意核对 lsblk 输出）
```
新盘比旧盘小时需先改 sfdisk 文件中最后一个分区的大小（还原要求目标分区 ≥ 93.1G）。

## 平时建议
- 镜像与系统在同一块盘上：**能防系统崩溃，防不了硬盘物理损坏**。建议把整个
  "系统镜像快照_*" 目录再复制一份到移动硬盘或网盘。
- 大版本升级（26.04 → 下个版本）之前，重新跑一次创建脚本做新快照。
- 想要日常自动增量备份，可另装 Timeshift（其快照只能放 Linux 文件系统分区，
  本机只有系统分区自己可用，会占约 28G 空间，可选）。
ZEOF

sed -i "s|@EXT@|$EXT|g; s|@STAMP@|$STAMP|g; s|@ROOT@|$SRC_ROOT|g; s|@ESP@|$SRC_ESP|g; s|@DATA@|$DATA_PART|g; s|@ROOT_UUID@|$ROOT_UUID|g; s|@ESP_UUID@|$ESP_UUID|g" \
  "$SNAP/恢复系统.sh" "$SNAP/恢复说明.md"

log "7/7 完成"
ls -lh "$SNAP"
echo
echo "✅ 镜像快照已创建：$SNAP"
echo "   还原方法见同目录《恢复说明.md》。"
echo "   建议：抽空制作一个 Ubuntu Live U 盘放手边，并把该目录复制一份到移动硬盘。"
