"""ft_goal_receipt — 뉴스 판 묶음의 «검증 영수증» 수명 (R362 DA⑥ r2 H3 · ft_goal_gate 가 부른다).

영수증 = <상태>/goal-bundle/<sha10>-<run>.json «묶음별 파일»(다른 묶음 시작이 이전 묶음을 덮지 않는다) · 원자 쓰기(tmp+rename).
상태 = pending(검증만) → partial(후속 판 일부 나감) → complete(후속 판 전부 나감 = 닫힘) · failed(발행 실패 — 후속 번호 소비 불가 · 같은 묶음 재시도가 이어 받는다) · drafted(초안 모드 종료 = 닫는 사건 · 이후 planner 가 다듬어 올리는 판은 번호당 1회만).
검증한 판의 본문 해시를 묶음에 결속한다 — 같은 번호 다른 본문 = 거절. mark_done 은 처리 기록 저장 «뒤» 에 부른다(그 사이 실패해도 재시도가 중복 게시 0 + 기록 복구).
닫는 사건이 없던 영수증이 쌓이지 않도록 KEEP_S 지난 파일은 새 묶음을 시작할 때 지운다.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from pathlib import Path

CONT = re.compile(r"\((\d+)/(\d+)\)")
TOKEN = re.compile(r"골표 ([0-9a-f]{10})·(\d{12})")
DIR = "goal-bundle"
OPEN = ("pending", "partial", "drafted")  # 후속 판 발행이 허용되는 상태
KEEP_S = 3 * 24 * 60 * 60


def first(body: str) -> str:
    return body.splitlines()[0] if body.strip() else ""


def digest(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]


def _file(state_dir: Path, sha: str, run: str) -> Path:
    return state_dir / DIR / f"{sha}-{run}.json"


def _load(state_dir: Path, sha: str, run: str) -> dict:
    try:
        return json.loads(_file(state_dir, sha, run).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save(state_dir: Path, rec: dict) -> None:
    f = _file(state_dir, rec["sha"], rec["run"])
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".tmp")
    tmp.write_text(json.dumps(rec, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, f)


def _prune(state_dir: Path) -> None:
    for f in (state_dir / DIR).glob("*.json"):
        if time.time() - f.stat().st_mtime > KEEP_S:
            f.unlink(missing_ok=True)


def _key(parts: list[str]):
    return TOKEN.search(first(parts[1])) if len(parts) > 1 else None


def begin(state_dir: Path, parts: list[str]) -> str:
    """검증을 통과한 묶음의 영수증을 열거나 이어 받는다 — 문제가 있으면 그 글(없으면 빈 글)."""
    if not (t := _key(parts)):
        return ""
    hashes = {str(i): digest(p) for i, p in enumerate(parts[1:], 2)}
    rec = _load(state_dir, t[1], t[2])
    if rec.get("status") == "complete":
        return "이미 완료된 묶음이다 — 같은 묶음 id 재발행 거절"
    if rec and rec.get("hashes") != hashes:
        return "같은 묶음 id(골표 sha10·run)인데 검증한 판 본문과 다르다"
    if rec:
        rec["status"], rec["reason"] = ("partial" if rec["done"] else "pending"), ""
    else:
        rec = {"sha": t[1], "run": t[2], "total": len(parts), "status": "pending", "done": [], "hashes": hashes, "reason": ""}
    _prune(state_dir)
    _save(state_dir, rec)
    return ""


def finish(state_dir: Path, parts: list[str], status: str, reason: str = "") -> None:
    """묶음 닫는 사건 — complete(전 판 발행) · failed(발행 실패 사유) · drafted(초안 모드 종료). 이미 complete 면 그대로."""
    if not (t := _key(parts)):
        return
    rec = _load(state_dir, t[1], t[2])
    if rec and rec.get("status") != "complete":
        rec["status"], rec["reason"] = status, reason
        _save(state_dir, rec)


def check_part(state_dir: Path, body: str, n: int, total: int, t: re.Match[str]) -> str:
    """후속 판 하나의 문제(없으면 빈 글) — 영수증 있음 · 열린 상태 · 범위 · 한 번만 · 검증한 본문."""
    rec = _load(state_dir, t[1], t[2])
    if not rec or rec.get("total") != total:
        return "이어진 판의 묶음 표지가 검증 영수증(같은 run 의 판 묶음 검증)과 맞지 않는다 — 영수증 없음·다른 run·총수 불일치"
    if rec["status"] not in OPEN:
        return f"묶음 영수증이 {rec['status']} 상태다({rec.get('reason') or '닫힘'}) — 후속 판 발행 불가"
    if not 2 <= n <= total or n in rec["done"]:
        return f"판번호 {n}/{total} 가 범위 밖이거나 이미 나간 판이다"
    if rec["status"] != "drafted" and rec["hashes"].get(str(n)) != digest(body):
        return f"판번호 {n}/{total} 본문이 검증한 판과 다르다(같은 번호 다른 글)"
    return ""


def is_done(state_dir: Path, body: str) -> bool:
    """이 판이 이미 나가고 기록까지 끝났는가 — 묶음 재시도가 같은 판을 다시 올리지 않는다."""
    m, t = CONT.search(first(body)), TOKEN.search(first(body))
    if not (m and t and int(m[1]) > 1):
        return False
    rec = _load(state_dir, t[1], t[2])
    return bool(rec) and int(m[1]) in rec["done"] and rec["hashes"].get(m[1]) == digest(body)


def mark_done(state_dir: Path, body: str) -> None:
    """후속 판이 나가고 처리 기록이 저장된 «뒤» 판번호를 찍는다 — 후속 판이 전부 찍히면 complete(닫힘)."""
    m, t = CONT.search(first(body)), TOKEN.search(first(body))
    if not (m and t and int(m[1]) > 1):
        return
    rec = _load(state_dir, t[1], t[2])
    if not rec or rec["status"] not in OPEN:
        return
    rec["done"] = sorted({*rec["done"], int(m[1])})
    if rec["done"] == list(range(2, rec["total"] + 1)):
        rec["status"] = "complete"
    elif rec["status"] == "pending":
        rec["status"] = "partial"
    _save(state_dir, rec)
