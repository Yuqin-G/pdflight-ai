"""Copy recoverable native session logs and reconstruct missing text archives.

This never changes Harness data. Unsupported records stay in their copied
compressed source rather than being silently dropped.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import zstandard


def exclusive_write(path: Path, data: bytes):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        if path.read_bytes() != data:
            raise RuntimeError("A different recovery copy already exists")
        return
    with os.fdopen(fd, "wb") as f:
        f.write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("data", type=Path)
    parser.add_argument("sessions", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    papers = {p["id"] for p in json.loads((args.data / "index.json").read_text())["papers"]}
    groups = json.loads((args.data / "conversations.json").read_text())["groups"]
    recovered = retained = skipped = 0
    for group in groups:
        for item in group["conversations"]:
            sid = item["sessionId"]
            missing_archive = not (args.data / "chats" / (sid + ".json")).exists()
            if not missing_archive and group["paperId"] in papers:
                continue
            if not re.fullmatch(r"[A-Za-z0-9_-]+", sid):
                skipped += 1
                continue
            sources = list(args.sessions.glob("*/" + sid + "/session.v4.jsonl.zstd"))
            if len(sources) != 1:
                skipped += 1
                continue
            compressed = sources[0].read_bytes()
            exclusive_write(args.output / "native-sessions" / (sid + ".jsonl.zstd"), compressed)
            retained += 1
            if group["paperId"] not in papers or not missing_archive:
                continue
            with zstandard.ZstdDecompressor().stream_reader(sources[0].open("rb")) as stream:
                records = [json.loads(line) for line in stream.read().splitlines()]
            entries = []
            provider = model = None
            supported = True
            for record in records:
                if record.get("type") not in ("user/message", "assistant/message"):
                    continue
                if record.get("surfaceOp") != "append":
                    supported = False
                    break
                payload = record["data"]
                message = payload if record["type"] == "user/message" else payload.get("message", {})
                blocks = message.get("content", [])
                if not isinstance(blocks, list) or any(not isinstance(b, dict) or b.get("type") != "text" or not isinstance(b.get("text"), str) for b in blocks):
                    supported = False
                    break
                source = message.get("source") or {}
                provider = source.get("provider", provider)
                model = source.get("model", model)
                entries.append({"seq": record["seq"], "time": record["time"], "id": message["id"],
                                "role": message["role"], "text": "".join(b["text"] for b in blocks), "content": blocks})
            if not supported:
                skipped += 1
                continue
            archive = {"version": 1, "sessionId": sid, "nativeSessionId": sid, "paperId": group["paperId"],
                       "title": item.get("title", "对话"), "createdAt": item.get("createdAt"),
                       "status": "active", "entries": entries, "provider": provider, "model": model}
            exclusive_write(args.output / "chats" / (sid + ".json"), json.dumps(archive, ensure_ascii=False, indent=2).encode())
            recovered += 1
    print(f"Native session copies retained: {retained}; missing text archives reconstructed: {recovered}; skipped: {skipped}")


if __name__ == "__main__":
    main()
