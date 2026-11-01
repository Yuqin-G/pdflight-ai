"""Add reasoning and tool timeline details from backed-up Harness sessions.

Only the staged native history is modified. Original compressed logs and
Harness archives remain unchanged beside it.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import tempfile
import zstandard


def iso(ms):
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def atomic_write(path, value):
    fd, name = tempfile.mkstemp(prefix=".enrich-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf8") as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", type=Path)
    parser.add_argument("archive_dir", type=Path)
    parser.add_argument("recovered_dir", type=Path)
    args = parser.parse_args()
    counters = {"sessions": 0, "reasoning blocks": 0, "tool calls": 0, "unmatched": 0}
    for history_path in (args.stage / "ai-chats").glob("*.json"):
        history = json.loads(history_path.read_text())
        changed = False
        for conversation in history.get("conversations", []):
            conversation_changed = False
            sid = conversation["id"]
            source = args.stage / "harness-native-originals" / (sid + ".jsonl.zstd")
            archive = args.archive_dir / "chats" / (sid + ".json")
            if not archive.exists(): archive = args.recovered_dir / "chats" / (sid + ".json")
            if not source.exists() or not archive.exists(): continue
            archive_data = json.loads(archive.read_text())
            archive_ids = {item["id"]: item["seq"] for item in archive_data["entries"] if "id" in item}
            messages = conversation["messages"]
            by_id = {m["id"]: m for m in messages}
            if any(m["id"] not in archive_ids for m in messages):
                counters["unmatched"] += 1
                continue
            with zstandard.ZstdDecompressor().stream_reader(source.open("rb")) as stream:
                records = [json.loads(line) for line in stream.read().splitlines()]
            ordered = [(archive_ids[m["id"]], m) for m in messages]
            tools = {}
            for record in records:
                kind = record.get("type"); data = record.get("data") or {}; seq = record.get("seq")
                if kind == "assistant/message":
                    message = data.get("message") or {}; mid = message.get("id")
                    blocks = message.get("content") or []
                    reasoning = "\n\n".join(b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "reasoning" and b.get("text"))
                    if not reasoning or not mid: continue
                    target = by_id.get(mid)
                    if target is None:
                        target = {"id": mid, "role": "assistant", "content": "", "createdAt": iso(record["time"])}
                        by_id[mid] = target; ordered.append((seq, target))
                    target["reasoning"] = reasoning; counters["reasoning blocks"] += 1; changed = True; conversation_changed = True
                elif kind == "tool/call":
                    cid = data.get("callId")
                    if not isinstance(cid, str) or not isinstance(data.get("name"), str): continue
                    card = {"id": "harness-tool-" + cid, "role": "tool", "content": "", "createdAt": iso(record["time"]),
                            "toolEvent": {"name": data["name"], "arguments": str(data.get("arguments", "")), "isError": False}}
                    tools[cid] = card; ordered.append((seq, card)); counters["tool calls"] += 1; changed = True; conversation_changed = True
                elif kind == "tool/result":
                    result = data.get("message") or {}; card = tools.get(result.get("toolCallId"))
                    if not card: continue
                    blocks = result.get("content") or []
                    text = "\n\n".join(b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text" and b.get("text"))
                    if any(not isinstance(b, dict) or b.get("type") != "text" for b in blocks): text += "\n[非文本结果保留在原始会话日志中]"
                    card["toolEvent"]["result"] = text; card["toolEvent"]["isError"] = bool(result.get("isError"))
            if conversation_changed:
                conversation["messages"] = [item for _, item in sorted(ordered, key=lambda pair: pair[0])]
            counters["sessions"] += 1
        if changed: atomic_write(history_path, history)
    print("; ".join(f"{key}: {value}" for key, value in counters.items()))


if __name__ == "__main__": main()
