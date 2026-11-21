"""ft_monitor_snap — 모니터 스냅샷 수집기(그림자) (r2409 · 기획서 §2.1·§3 S1 · 화면 0).

  ft_monitor_snap.py collect [--root R] [--now ISO|epoch]   # 틱마다 1회 · snap.json 새로 + hist.jsonl 1줄(열쇠 다를 때)
  ft_monitor_snap.py show [--snap F]                        # 저장된 스냅샷 1줄 요약(24시간 대조·시험)
쓰기 = `state/board/monitor-snap.json` · `state/board/monitor-hist.jsonl` 둘뿐(다른 파일 손 0 · Slack·쪽지·LLM 0).
  snap = {"schema":1,"at":잰 시각,"cells":11칸,"goals":{골:{fact_key,fact_changed_at}}} · 칸 꼴 = ft_monitor_snap_src 머리말.
  fact_changed_at 승계(DA#56 H2): 새 fact_key 가 직전 스냅샷과 같으면 시각을 그대로 이어 간다(48시간 절단·재시작 무관 ·
  72시간도 그대로) · 직전 스냅샷 파일이 없으면 null = «서 있음 ?(시작점 없음)».
  hist = 발행 대신 1줄(기획서 §3 S1 그림자) · 열쇠(§2.4 G5 투영)가 직전 줄과 다를 때만 · 경과 시간·표시 시각은 열쇠 밖 · 48시간 보관.
  같은 입력·같은 --now = 같은 바이트(§2.4 G4 · 정렬 고정 · 표시 시각도 같다). rc 0 · 쓰기 실패 = rc 1 «판정 불가» 1줄.
env: FT_ROOT · FT_MONITOR_NOW(시각 주입) · FT_MONITOR_SNAP · FT_MONITOR_HIST · 원천 대역 = ft_monitor_snap_cells 머리말.
"""
from __future__ import annotations  # mini python 3.9.6

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import ft_monitor_snap_cells as cells_lib
from ft_monitor_snap_src import iso

SCHEMA = 1
HIST_KEEP_S = 48 * 3600
NO_TIME = {"planner_check"}  # 경과 시간(«N분 전»)은 열쇠 밖 — q 만 본다(§2.4 G5)


def _now(value: str | None) -> float:
    value = value if value is not None else os.environ.get("FT_MONITOR_NOW")
    if not value:
        return datetime.now().timestamp()
    try:
        return float(value)
    except ValueError:
        return datetime.fromisoformat(value).timestamp()


def _dump(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def _paths(root: Path) -> tuple:
    board = root / ".fable-team" / "state" / "board"
    return (Path(os.environ.get("FT_MONITOR_SNAP") or board / "monitor-snap.json"),
            Path(os.environ.get("FT_MONITOR_HIST") or board / "monitor-hist.jsonl"))


def _read_json(path: Path) -> dict | None:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    return doc if isinstance(doc, dict) else None


def _fact_key(goal: str, item: dict, cells: dict) -> str:
    """골 사실 열쇠 = 이름 · n/m · 카드 목록 · 착지 시각 · 기다림 줄 · 칸 q (경과 시간 제외 · 정렬 고정)."""
    raw = {"goal": goal, "n": item.get("n"), "m": item.get("m"),
           "waiting": cells["waiting"]["v"].get(goal) if isinstance(cells["waiting"].get("v"), dict) else None,
           "facts": cells["goal_facts"]["v"].get(goal) if isinstance(cells["goal_facts"].get("v"), dict) else None,
           "q": [cells["waiting"]["q"], cells["goal_facts"]["q"]]}
    return hashlib.sha256(_dump(raw).encode("utf-8")).hexdigest()


def _goals(cells: dict, prev: dict | None, now: float) -> dict:
    goals = cells["goals"]["v"] if isinstance(cells["goals"].get("v"), dict) else {}
    before = (prev or {}).get("goals") if isinstance((prev or {}).get("goals"), dict) else {}
    out = {}
    for goal, item in sorted(goals.items()):
        key = _fact_key(goal, item, cells)
        old = before.get(goal) if isinstance(before.get(goal), dict) else None
        if old and old.get("fact_key") == key:
            changed = old.get("fact_changed_at")  # 승계 — 시작점 없음(null)도 그대로 둔다(«서 있음 ?» · ⑬c)
        else:
            changed = None if prev is None else iso(now)
        out[goal] = {"fact_key": key, "fact_changed_at": changed}
    return out


def _project(snap: dict) -> dict:
    """§2.4 G5 발행 열쇠 투영 — 값·출처·q 는 넣고 경과 시간·표시 시각은 뺀다."""
    cells = {}
    for name, item in sorted(snap["cells"].items()):
        value = None if name in NO_TIME else item.get("v")
        if name == "blocked_sessions" and isinstance(value, dict):
            value = {"blocked": value.get("blocked")}
        cells[name] = {"v": value, "q": item.get("q")}
    goals = {g: {"n": snap["goals"][g]["fact_key"]} for g in sorted(snap["goals"])}
    return {"cells": cells, "goals": goals}


def _key(project: dict) -> str:
    return hashlib.sha256(_dump(project).encode("utf-8")).hexdigest()


def _hist_append(path: Path, line: dict, now: float) -> tuple:
    """(썼는지, 직전 줄) — 열쇠가 직전 줄과 같으면 새 줄 0 · 48시간 넘은 줄은 이때 버린다."""
    rows = []
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            try:
                row = json.loads(raw)
            except ValueError:
                continue
            if isinstance(row, dict) and isinstance(row.get("epoch"), (int, float)):
                rows.append(row)
    except (OSError, UnicodeDecodeError):
        rows = []
    kept = [r for r in rows if now - float(r["epoch"]) <= HIST_KEEP_S]
    same = rows[-1] if rows else None
    if kept == rows and same is not None and same.get("key") == line["key"]:
        return (False, same)  # 새 줄도 없고 버릴 줄도 없다 — 파일 그대로
    write = kept + ([] if same is not None and same.get("key") == line["key"] else [line])
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("".join(_dump(r) for r in write), encoding="utf-8")
    os.replace(tmp, path)
    return (len(write) > len(kept), same)


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def collect(root: Path, now: float) -> tuple:
    """(snap, 쓴 hist 줄 수 | None, 직전 열쇠) — 파일 쓰기 실패는 예외로 올린다(부르는 쪽이 rc 1)."""
    snap_path, hist_path = _paths(root)
    at = iso(now)
    prev = _read_json(snap_path)
    cells = cells_lib.collect_all(root, at, now)
    snap = {"schema": SCHEMA, "at": at, "cells": cells, "goals": _goals(cells, prev, now)}
    _write(snap_path, _dump(snap))
    project = _project(snap)
    key = _key(project)
    wrote, same = _hist_append(hist_path, {"at": at, "epoch": now, "key": key, **project}, now)
    return snap, (1 if wrote else 0), (None if wrote else same.get("at") if same else None)


def show(path: Path) -> str:
    doc = _read_json(path)
    if doc is None:
        return f"ft_monitor_snap: 판정 불가 — 스냅샷 못 읽음 {path}"
    bad = [k for k, v in sorted(doc.get("cells", {}).items()) if v.get("q") != "ok"]
    goals = doc.get("goals") or {}
    hold = [g for g in sorted(goals) if not goals[g].get("fact_changed_at")]
    return (f"ft_monitor_snap: at={doc.get('at')} · 칸 11 중 ok {11 - len(bad)} · 못 잼/낡음 {len(bad)}"
            f"{('(' + ','.join(bad) + ')') if bad else ''} · 골 {len(goals)} · 시작점 없음 {len(hold)}")


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(add_help=True, description="모니터 스냅샷 수집기(r2409 · 그림자)")
    ap.add_argument("cmd", nargs="?", default="collect", choices=("collect", "show"))
    ap.add_argument("--root", default=os.environ.get("FT_ROOT") or ".")
    ap.add_argument("--now", default=None)
    ap.add_argument("--snap", default=None)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    snap_path, _ = _paths(root)
    if a.cmd == "show":
        print(show(Path(a.snap) if a.snap else snap_path))
        return 0
    now = _now(a.now)
    try:
        snap, wrote, same_at = collect(root, now)
    except OSError as e:
        print(f"ft_monitor_snap: 판정 불가 — 스냅샷 쓰기 실패 {e}", file=sys.stderr)
        return 1
    if not a.quiet:
        bad = [k for k, v in sorted(snap["cells"].items()) if v.get("q") != "ok"]
        print(f"ft_monitor_snap: 칸 11 · ok {11 - len(bad)} · 못 잼/낡음 {len(bad)}"
              f"{('(' + ','.join(bad) + ')') if bad else ''} · 골 {len(snap['goals'])} · "
              + ("hist +1" if wrote else f"hist 0(열쇠 같음 {same_at or ''})".strip()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
