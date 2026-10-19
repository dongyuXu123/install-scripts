#!/usr/bin/env python3
"""Codex notify → dsh-pet Agent 联动事件桥。

在 ~/.codex/config.toml 里配置：
    notify = ["/home/dongyu/apps/dsh-pet/pet-codex-notify.py"]
Codex 会把事件 JSON 作为最后一个命令行参数传入。目前 notify 只有
agent-turn-complete（回合结束待确认）一种事件，粒度较粗，属协议允许
的自定义通道用法。只写状态元数据，不落任何消息正文。写失败静默。
"""
import json
import pathlib
import sys
import time

BASE = pathlib.Path.home() / ".config/dsh-pet-standalone-webm-chat/agent-events"
EVENT_FILE = BASE / "codex.jsonl"

STATE_BY_EVENT = {
    "agent-turn-complete": "attention",
}


def main() -> None:
    if len(sys.argv) < 2:
        return
    try:
        data = json.loads(sys.argv[-1])
    except Exception:
        return
    state = STATE_BY_EVENT.get(str(data.get("type") or ""))
    if state is None:
        return
    try:
        BASE.mkdir(parents=True, exist_ok=True)
        line = {"ts": time.time(), "agent": "codex", "state": state}
        with EVENT_FILE.open("a", encoding="utf-8") as f:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")
    except Exception:
        pass


if __name__ == "__main__":
    main()
