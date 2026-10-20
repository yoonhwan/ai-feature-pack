"""ft-board snapshot / prune — 슬랙 본문은 최신만 보이므로 «이력»은 불변 스냅샷 파일이 가진다 (판정 421 · 설계 §2-3 · DA N3).

snapshot: collect() dict 를 정렬 JSON 으로 `<FT_ROOT>/.fable-team/state/board/<YYYY-MM-DD>/<HHMMSS>-<hash8>.json` 에 «먼저» 쓰고(fsync)
  같은 날 직전 스냅샷과의 변경 단위 목록을 낸다. 쓰기 실패 = raise(rc≠0 · stdout 빈 값) — 호출자는 rc=0 일 때만 발행한다.
  입력이 직전과 같아도 막지 않는다(누락 답글 복구) — changes 빈 배열 + 같은 hash8.
prune: 명시 명령만(자동 삭제 0).
"""
import hashlib
import json
import os
import shutil
from datetime import datetime, timedelta
from pathlib import Path


def board_dir(root: Path) -> Path:
    return root / ".fable-team" / "state" / "board"


def _latest(day_dir: Path) -> Path | None:
    files = [p for p in day_dir.glob("*.json")] if day_dir.is_dir() else []
    return max(files, key=lambda p: (p.name[:6], p.stat().st_mtime_ns), default=None)


def _hash_of(p: Path) -> str:
    return p.name.split("-", 1)[1].removesuffix(".json")


def _prev_day_last(root: Path, day: str) -> str | None:
    for d in sorted((p for p in board_dir(root).glob("????-??-??") if p.name < day), reverse=True):
        last = _latest(d)
        if last:
            return _hash_of(last)
    return None


def diff(prev: dict, cur: dict) -> list[str]:
    out = []
    ptm = {t["key"]: t for t in prev["teams"]}
    for t in cur["teams"]:
        if t["key"] not in ptm:
            out.append(f"팀 추가 {t['key']}")
            continue
        old = ptm[t["key"]].get("states") or {}
        new = t.get("states") or {}
        for name, st in sorted(new.items()):
            if old.get(name) != st:
                out.append(f"카드 {t['key']}/{name} {old.get(name, '신규')}→{st}")
        out += [f"카드 {t['key']}/{n} {old[n]}→삭제" for n in sorted(set(old) - set(new))]
    pis = {i["number"]: i["state"] for i in prev["issues"]}
    for i in cur["issues"]:
        if pis.get(i["number"], "신규") != i["state"]:
            out.append(f"Issue #{i['number']} {pis.get(i['number'], '신규')}→{i['state']}")
    pv = {v["n"]: v for v in prev["verdicts"]}
    for v in cur["verdicts"]:
        if v["n"] not in pv:
            out.append(f"판정 {v['n']} new")
        elif pv[v["n"]]["state"] != v["state"]:
            out.append(f"판정 {v['n']} {pv[v['n']]['state']}→{v['state']}")
    hand = lambda d: {v["n"] for v in d["verdicts"] if v["state"] == "open" and v["oppa_todo"]}  # noqa: E731
    out += [f"오빠 손 +{n}" for n in sorted(hand(cur) - hand(prev))] + [f"오빠 손 -{n}" for n in sorted(hand(prev) - hand(cur))]
    return out


def snapshot(d: dict, root: Path, now: datetime) -> dict:
    body = json.dumps(d, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    h8 = hashlib.sha256(body.encode("utf-8")).hexdigest()[:8]
    day = now.strftime("%F")
    day_dir = board_dir(root) / day
    prev_file = _latest(day_dir)  # 쓰기 «전»에 직전을 잡는다
    prev = json.loads(prev_file.read_text(encoding="utf-8")) if prev_file else None
    day_dir.mkdir(parents=True, exist_ok=True)
    path = day_dir / f"{now.strftime('%H%M%S')}-{h8}.json"
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        f.write(body)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    prev_h8 = _hash_of(prev_file) if prev_file else None
    return {"snap": f"{prev_h8 or '-'}→{h8}", "prev": prev_h8,
            "changes": diff(prev, d) if prev else [], "prev_day_last": None if prev_file else _prev_day_last(root, day)}


def prune(root: Path, now: datetime, days: int) -> list[str]:
    cutoff = (now - timedelta(days=days)).strftime("%F")
    gone = sorted(p for p in board_dir(root).glob("????-??-??") if p.name < cutoff)
    for p in gone:
        shutil.rmtree(p)
    return [p.name for p in gone]
