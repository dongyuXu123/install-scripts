#!/usr/bin/env python3
"""ZCode hooks → dsh-pet Agent 联动事件桥。

注册在 ~/.zcode/cli/config.json 的 hooks.events.<事件> 里，
ZCode 以 JSON 从 stdin 传入 hook 载荷，本脚本只取事件名与工具名，
按 docs/AGENT_LINK_PROTOCOL.md 追加一行事件到桌宠的 zcode.jsonl。

隐私红线：绝不写入提示词、命令内容、文件路径等正文数据。
写失败一律静默——联动是锦上添花，不能影响 ZCode 本体。
"""
import json
import pathlib
import sys
import time

BASE = pathlib.Path.home() / ".config/dsh-pet-standalone-webm-chat/agent-events"
EVENT_FILE = BASE / "zcode.jsonl"
LAST_FILE = BASE / ".zcode-last-state"

# hook 事件 -> 协议形态（state 直给六态；event 走桌宠内置映射）
MAPPING = {
    "SessionStart": ("state", "idle", "idle"),
    "UserPromptSubmit": ("state", "thinking", "thinking"),
    "PreToolUse": ("event", "PreToolUse", "working"),
    "PostToolUse": ("event", "PostToolUse", "working"),
    "PostToolUseFailure": ("event", "PostToolUseFailure", "error"),
    "PermissionRequest": ("state", "attention", "attention"),
    "Stop": ("event", "Stop", "attention"),
}


def main() -> None:
    arg_event = sys.argv[1] if len(sys.argv) > 1 else ""
    payload = {}
    try:
        raw = sys.stdin.read()
        if raw.strip():
            payload = json.loads(raw)
    except Exception:
        pass

    event = payload.get("hook_event_name") or arg_event
    mapped = MAPPING.get(event)
    if mapped is None:
        return
    kind, value, normalized = mapped
    tool = str(payload.get("tool_name") or "").lower()

    try:
        BASE.mkdir(parents=True, exist_ok=True)
        # 协议 §2.5：连续相同状态不要重复落盘
        last = LAST_FILE.read_text(encoding="utf-8").strip() if LAST_FILE.exists() else ""
        if last == normalized:
            return
        LAST_FILE.write_text(normalized, encoding="utf-8")

        line = {"ts": time.time(), "agent": "zcode"}
        if kind == "state":
            line["state"] = value
        else:
            line["event"] = value
        if tool:
            line["tool"] = tool
        with EVENT_FILE.open("a", encoding="utf-8") as f:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")
    except Exception:
        pass


if __name__ == "__main__":
    main()
