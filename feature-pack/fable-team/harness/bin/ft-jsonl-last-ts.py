#!/usr/bin/env python3
"""ft-jsonl-last-ts.py <jsonl> — timestamp 키가 있는 «마지막» 기록 → `<epoch> <type>[/<subtype>]` 한 줄 (R53).

Claude Code 는 턴 뒤에도 timestamp 없는 기록(last-prompt · cost-state)을 덧붙여 mtime 을 민다 — 유휴 시각은 기록 안의 timestamp 에서 읽는다.
기록이 없거나 못 읽으면 stderr `ERROR: …` + rc=1(stdout 0) — mtime 으로 내려가지 않는다. ISO 의 Z 는 UTC.
"""
import json
import os
import sys
from collections.abc import Iterator
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # 형제 모듈 — r849 로그아웃 판정은 한 곳(ft_api_outage_util)
from ft_api_outage_util import is_logged_out, is_normal  # noqa: E402

CHUNK = 1 << 16


def lines_from_end(path: str) -> Iterator[bytes]:
    with open(path, "rb") as fh:
        pos = fh.seek(0, 2)
        tail = b""
        while pos > 0:
            end, pos = pos, max(0, pos - CHUNK)
            _ = fh.seek(pos)
            parts = (fh.read(end - pos) + tail).split(b"\n")
            tail = parts[0]
            yield from reversed(parts[1:])
        yield tail


def last_timestamped(path: str) -> tuple[int, str] | None:
    for raw in lines_from_end(path):
        try:
            rec: dict[str, object] = json.loads(raw)
            epoch = int(datetime.fromisoformat(str(rec["timestamp"]).replace("Z", "+00:00")).timestamp())
        except (ValueError, KeyError, TypeError, AttributeError):
            continue
        sub = rec.get("subtype")
        return epoch, f"{rec.get('type', '?')}/{sub}" if sub else str(rec.get("type", "?"))
    return None


def last_active(path: str) -> tuple[int, str] | None:
    """r849 --skip-logged-out — 인증 실패 0초 턴(인증 실패 기록이 있고 정상 assistant 가 없는 턴 · 끝 turn_duration 포함)을 뺀 마지막 기록."""
    seg: list[dict[str, object]] = []  # 뒤에서부터 모은 «한 턴»(turn_duration 다음 ~ 다음 turn_duration) — 첫 원소가 가장 늦은 기록

    def pick() -> tuple[int, str] | None:
        if any(is_logged_out(r) for r in seg) and not any(is_normal(r) for r in seg):
            return None
        for rec in seg:
            try:
                epoch = int(datetime.fromisoformat(str(rec["timestamp"]).replace("Z", "+00:00")).timestamp())
            except (ValueError, KeyError, TypeError, AttributeError):
                continue
            sub = rec.get("subtype")
            return epoch, f"{rec.get('type', '?')}/{sub}" if sub else str(rec.get("type", "?"))
        return None

    for raw in lines_from_end(path):
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(rec, dict):
            continue
        if rec.get("type") == "system" and rec.get("subtype") == "turn_duration":
            if found := pick():
                return found
            seg = []
        seg.append(rec)
    return pick()


def main(argv: list[str]) -> int:
    skip = "--skip-logged-out" in argv[2:]
    if len(argv) != 2 + skip:
        print("usage: ft-jsonl-last-ts.py <jsonl> [--skip-logged-out]", file=sys.stderr)
        return 2
    try:
        found = last_active(argv[1]) if skip else last_timestamped(argv[1])
    except OSError as exc:
        print(f"ERROR: {argv[1]} 를 읽지 못함: {exc.strerror}", file=sys.stderr)
        return 1
    if found is None:
        print(f"ERROR: {argv[1]} 에 timestamp 기록 없음", file=sys.stderr)
        return 1
    print(f"{found[0]} {found[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
