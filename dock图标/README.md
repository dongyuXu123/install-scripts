# 左侧 Dock 分区图标美化（v5 拟人角色卡版 · 已生效）

日期：2026-10-22 安装并验证生效（历经 v1 Tela扁平 / v2 logo贴纸 / v3-v4 过渡，均已清理）

## 背景

Ubuntu 左侧 Dash to Dock 开着「显示挂载卷」，两块 NVMe 的 6 个分区全是 Yaru 同一个灰色
硬盘图标。最终方案按用户要求：**全部用人物拟人形象**（抖音"AI 拟人角色卡"系列，同一画风
共 14 张，用户两次提供了抖音帖链接），**豆包不要、logo 类不要**；EFI 分区隐藏；
外接 USB 设备默认 GLM、可逐个绑成不同角色。

## 图标方案

| 分区 | 图标 | 角色（角色卡称号） |
|---|---|---|
| nvme0n1p3 系统 (C盘) | `card-claude` | Claude 暖阳学者 |
| nvme0n1p4 软件 (D盘) | `card-gpt` | ChatGPT 白龙司书 |
| nvme0n1p5 游戏及数据 (E盘) | `card-gemini` | Gemini 幻星灵狐 |
| nvme1n1p3 linux与windows共用 | `card-deepseek` | DeepSeek 深海女仆 |
| nvme1n1p1 / nvme0n1p1 两个 EFI | — | `UDISKS_IGNORE=1` 隐藏（不影响 /boot/efi 挂载） |
| 外接 USB 分区 | 插入时**自动随机分配一个不重复的角色**（systemd 服务 `dock-icon-assign@`，带文件锁+自动去重，按 UUID 持久记忆；GLM 仅为兜底） |

备用形象（给外接设备逐个分配）：
`card-kimi`(Kimi 月栖安者) `card-qwen`(Qwen 青岚雅士) `card-grok`(Grok 黑曜公主)
`card-ernie`(ERNIE 静蓝读者) `card-hunyuan`(混元 霜华行者) `card-seed`(Seed 灵感使者)
`card-minimax`(MiniMax 拾光导演) `card-mistral`(Mistral 赤金游侠) `card-llama`(Llama 绒云梦游)
`pet-fish`(大肥鱼本鱼)

统一视觉：白色贴纸描边 + 角色主题色渐变卡 + 角色卡头像框（每卡左上角现成的头像）。
预览：`预览-v5-角色卡.png`

## 安装（2026-10-22 已完成并验证）

1. 图标本体在用户目录（无需 root）：
   `~/.local/share/icons/hicolor/256x256/devices/card-*.png`（14 枚 + pet-fish.png）
2. udev 规则已写入 `/etc/udev/rules.d/99-dock-drive-icons.rules`
   （外接默认 + 4 个 UUID 绑定 + EFI 隐藏），六项验证全部 OK。
3. 若日后重装系统或规则丢失，重跑一次即可（幂等）：
   ```
   sudo bash ~/备份/dock图标/install-udev-rules.sh
   ```

## 日常操作（外接设备逐个换形象）

```
sudo bash ~/备份/dock图标/assign-drive-icon.sh                          # 列出所有分区当前形象
sudo bash ~/备份/dock图标/assign-drive-icon.sh /dev/sdb1 card-kimi      # 例：这只U盘=Kimi
```
规则按 UUID 记忆，同一设备长期保留专属形象；没绑过的外接设备一律 GLM。

## 卸载 / 回滚

```
sudo bash ~/备份/dock图标/uninstall-udev-rules.sh
rm -f ~/.local/share/icons/hicolor/256x256/devices/{card-*,pet-fish}.png
```

## 素材与再生成

- 来源：抖音「AI 拟人角色卡」系列 14 张（帖子 modal_id=7695252193263275273），
  原图在 `角色卡原图/card-*.png`。
- 抓取方法：`https://www.iesdouyin.com/share/video/<作品ID>/` 免登录，img 标签里
  `aweme-images` 的原图带签名直链（有时效，抓到就下）。
- 生成脚本 `compose5.py`：BOX 是头像框裁剪区（统一框 (18,288,345,628)），
  CARDS 字典改渐变色即可换配色。**图标换图必须换新文件名**（GNOME 按名缓存，原地覆盖不刷新），
  同步改 udev 规则里的 `UDISKS_ICON_NAME` 再重跑 install。

## 文件清单

- `install-udev-rules.sh` / `assign-drive-icon.sh` / `uninstall-udev-rules.sh` — 三个脚本（需 sudo）
- `final5/card-*.png` + `final5/pet-fish.png` — 15 枚成品图标
- `compose5.py` — 生成脚本
- `预览-v5-角色卡.png` — 效果预览
- `角色卡原图/` — 14 张角色卡原图（icon 源）
