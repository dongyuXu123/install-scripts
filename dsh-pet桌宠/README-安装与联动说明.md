# dsh-pet 桌宠安装与三 Agent 联动说明

安装日期：2026-10-19　版本：dsh-pet-indesktop v4.3.3（Linux x86_64 chat 版）
sha256：36998e943f1c35b8ac4af34456a560a8d9aa18a4ba84eea237a7d0ffa28577a0

## 安装位置

- 程序：`~/apps/dsh-pet/dsh-pet-standalone-webm-chat/`（onedir，1.4G）
- 配置：`~/.config/dsh-pet-standalone-webm-chat/`
  - 主配置 `config.json`：`agent_link` 块在这里（全局键！）
  - 每宠档案 `config-slot-N.json`：不要放 agent_link（共享管理器不读它）
  - 事件目录 `agent-events/{hermes,codex,zcode}.jsonl`
- 菜单入口：`~/.local/share/applications/dsh-pet.desktop`
- 开机自启：桌宠右键/托盘菜单里勾「开机自启」（本备份未代做）

## 三个 Agent 的接线

| Agent | 方式 | 位置 |
|---|---|---|
| hermes | 官方桥接插件 v1.2.1 | `~/.hermes/plugins/dsh-pet-bridge/`，已 `hermes plugins enable`；hermes 会话/网关下次启动生效。Linux 下默认写 `~/.config/dsh-pet-standalone-webm-chat/agent-events/hermes.jsonl`（无改包） |
| codex | 自定义通道 + notify | `~/.codex/config.toml` 顶层加了 `notify = ["/home/dongyu/apps/dsh-pet/pet-codex-notify.py"]`。目前 codex notify 只有 agent-turn-complete 一种事件 → 桌宠显示「回合结束待确认」，粒度粗属官方协议限制 |
| zcode | 自定义通道 + hooks | `~/.zcode/cli/config.json` 注册了 7 个 hooks（SessionStart/UserPromptSubmit/PreToolUse/PermissionRequest/PostToolUse/PostToolUseFailure/Stop）→ 脚本 `pet-zcode-hook.py`；新开的 zcode 会话生效 |

桥接脚本（本目录内有备份，原件在 `~/apps/dsh-pet/`）：
- `pet-zcode-hook.py` — stdin 读 hook JSON，只取事件名/工具名，去重后追加 JSONL
- `pet-codex-notify.py` — 读 notify 事件参数，agent-turn-complete → attention

关键配置（主 config.json 的 agent_link 块）：
```json
{"custom_agents": [
  {"key": "hermes", "name": "Hermes", "path": "~/.config/dsh-pet-standalone-webm-chat/agent-events/hermes.jsonl"},
  {"key": "codex",  "name": "Codex",  "path": "~/.config/dsh-pet-standalone-webm-chat/agent-events/codex.jsonl"},
  {"key": "zcode",  "name": "ZCode",  "path": "~/.config/dsh-pet-standalone-webm-chat/agent-events/zcode.jsonl"}
], "hermes": true, "codex": true, "zcode": true}
```

验证方法：桌宠日志 `~/.config/dsh-pet-standalone-webm-chat/pet-<PID>.log` 里应有
三行「Agent 监视器 [xxx] 已启动」；右键桌宠 → Agent 联动 → 自定义联动 Agent
三项应已勾选。测试：`printf '{"ts": %s, "state": "thinking"}\n' "$(date +%s)" >> ~/.config/dsh-pet-standalone-webm-chat/agent-events/zcode.jsonl`，1.5 秒内鱼应有反应。

## 源码版（2026-10-19 起，当前生效）

- 位置 `~/apps/dsh-pet-src`：git v4.3.3 标签 + 本地分支 `dongyu-patches`（Python 3.13 venv 由 uv 装）。
- 启动器 `~/apps/dsh-pet-src/run-pet.sh`；桌面入口「DSH 桌宠」已指向它；打包版 `~/apps/dsh-pet/` 保留作后备。**两个版本不要同时跑**（共用数据目录）。
- 数据目录软链：`~/.config/dsh-pet-standalone` → `...-webm-chat`（两版共用配置/会话/联动）。
- assets 符号链接到打包版 `_internal/assets`，未重复下载。
- **本地补丁**（`patches/0001-*.patch`，已提交进 dongyu-patches 分支）：
  1. Bing 免 Key 搜索引擎（cn.bing.com 抓取 + 跳转还原；`chat.web_search.engine` 已设 bing 并启用）
  2. 多供应商余额：balance.py 按厂商映射端点（智谱 → `/api/paas/v4/users/me/balance`，格式容错解析），app.py 余额查询枚举全部已配 key 的 provider 合并显示
  3. GLM 聊天 provider 已配好（glm-4.6 @ coding 端点），**API Key 需在 桌宠设置 → AI 与对话 → 模型与连接 里填**（DeepSeek/GLM 两个 key 都填上后，「DeepSeek 余额」菜单会同时显示两行余额）
- **升级方法**：`git fetch origin tag vX.Y.Z --depth=1 && git checkout -b dongyu-patches-vX.Y.Z vX.Y.Z && git cherry-pick 53ad44f`；cherry-pick 前先 `rm ~/apps/dsh-pet-src/assets`（symlink），操作完重建。智谱余额格式如解析失败，错误气泡里带响应前 200 字符，据此校准 `_parse_zhipu_balance`。

## 已知说明

- **点击穿透问题（2026-10-19 已修复）**：默认 overlay 拓扑是"铺满整个虚拟桌面的
  一张全屏透明合成窗"，靠逐像素 alpha 命中测试决定鼠标是否穿透。该 X11 路径
  作者自述从未实机验证（README：Linux/macOS 当「预览」对待），本机双屏下命中
  判定恒为"透明像素"，导致鱼完全点不中、点击全部击穿。**修复**：主 config.json
  设 `"stream_capture_mode": true`（官方"直播捕获兼容模式"，重启级切到 legacy
  单窗拓扑）。代价：失去 overlay 的灵动岛等特性；legacy 小窗的透明边角会吞点击
  （经典桌宠行为）。若后续版本放出带修复的 Linux 包，可把该键改回 false。
- 联动只传状态/事件名/工具名元数据，不写代码、命令、消息正文（协议隐私红线）。
- AI 对话（Chat）未配置 API：需要时在桌宠设置里填任意 OpenAI 兼容端点；
  走 hermes 的方式见 `~/.hermes/plugins/dsh-pet-bridge/README.md`（Hermes API
  Server, http://127.0.0.1:8642/v1）。
- Wayland 会话下如遇透明/置顶异常：`QT_QPA_PLATFORM=xcb` 启动。

## 卸载

1. 退出桌宠，删 `~/apps/dsh-pet/` 与菜单入口 `~/.local/share/applications/dsh-pet.desktop`
2. 删配置目录 `~/.config/dsh-pet-standalone-webm-chat/`
3. hermes：`hermes plugins remove dsh-pet-bridge`（或删 `~/.hermes/plugins/dsh-pet-bridge/`）
4. codex：删 `~/.codex/config.toml` 里的 `notify = [...]` 行
5. zcode：删 `~/.zcode/cli/config.json` 的整个 `hooks` 块
