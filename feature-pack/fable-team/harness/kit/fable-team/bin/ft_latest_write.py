"""원자 JSON 한 판 기록기 — 집계기는 계산한 결과만 넘긴다."""
import json
import os
import sys
from pathlib import Path


def write_latest(root, kind, tool, line, items, now, stamp=None):
    """최신 봉투를 원자 교체한다. 실패는 집계 rc에 영향을 주지 않는다."""
    dest = Path(root) / ".fable-team" / "state" / kind / "latest.json"
    tmp = Path(f"{dest}.tmp-{os.getpid()}")
    created = False
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        data = {"tool": tool, "kind": kind, "written_at": int(now), "stamp": stamp, "line": line, "items": items}
        with tmp.open("x", encoding="utf-8", newline="\n") as stream:
            created = True
            json.dump(data, stream, ensure_ascii=False, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, dest)
        return dest
    except OSError as exc:
        if created:
            try:
                tmp.unlink()
            except OSError:
                pass
        print(f"latest 쓰기 실패: {exc}", file=sys.stderr)
        return None
