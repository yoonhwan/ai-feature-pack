"""ft-board ⑤ 절 «오빠가 정할 것» — HIL-LEDGER open · 큐의 [HIL]/[긴급] 미처리 · MERGE-QUEUE 대기 · 제안 Issue 미결정 · 관찰 중 (PLAN D8 · 판정 1070).

읽기만 · gh 호출 0(collect 가 이미 읽은 d["issues"] + 캐시 파일 시각만). 모름·실패·오래된 캐시는 0 이 아니다 — `확인 불가(사유)` / `(캐시 HH:MM · 미확인)`.
전부 알고 있고 전부 신선하고 전부 0 일 때만 `오빠가 정할 것: 없음 — 오늘 질문 0` 한 줄.
env: FT_BOARD_HIL_LEDGER(기본 <harness 팀 폴더>/HIL-LEDGER.md) · FT_BOARD_MERGE_QUEUE(기본 <harness 팀 폴더>/MERGE-QUEUE.md) — 팀 폴더는 TEAMS.md 폴더 칸(ft_team_lib)
"""
import json
import os
import re
from datetime import datetime
from pathlib import Path

import ft_board_env as env
from ft_board_mail import PREFIX
from ft_team_lib import TeamPathError, team_in

CACHE_TTL = 600
ATTN = re.compile(r"^\[(HIL|긴급)")


def _rows(path: Path):
    if not path.is_file():
        return None
    return [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in path.read_text(encoding="utf-8").splitlines() if ln.lstrip().startswith("|")]


def _ledger(root: Path, var: str, name: str):
    try:
        path = Path(os.environ[var]) if os.environ.get(var) else team_in(root, "harness") / name
    except TeamPathError:
        return None  # 팀 폴더를 못 풀면 «확인 불가» 로 보고된다 — 보드 전체를 죽이지 않는다(0 으로 둔갑 0)
    return _rows(path)


def _queue(root: Path):
    """planner 앞 큐의 [HIL]/[긴급] seq 목록 — 읽을 수 없으면 None"""
    try:
        planner = re.sub(r"#\d+$", "", json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"])
        seqs = []
        for ln in (root / ".fable-team" / "comm" / "mailbox.jsonl").read_text(encoding="utf-8").splitlines():
            rec = json.loads(ln) if ln.strip() else None
            if rec and re.sub(r"#\d+$", "", str(rec["to"])) == planner and ATTN.match(PREFIX.sub("", str(rec["body"]), count=1)):
                seqs.append(rec["seq"])
        return seqs
    except (OSError, ValueError, KeyError):
        return None


def _cache_note(root: Path, now: datetime) -> str:
    p = root / ".fable-team" / "state" / "board" / "gh-cache.json"
    if not p.is_file():
        return " (캐시 없음 · 미확인)"
    at = datetime.fromtimestamp(p.stat().st_mtime)
    return f" (캐시 {at.strftime('%H:%M')} · 미확인)" if (now - at).total_seconds() > CACHE_TTL else ""


def decide_lines(d: dict, now: datetime) -> list[str]:
    root = env.ft_root()
    hil = _ledger(root, "FT_BOARD_HIL_LEDGER", "HIL-LEDGER.md")
    mq = _ledger(root, "FT_BOARD_MERGE_QUEUE", "MERGE-QUEUE.md")
    seqs = _queue(root)
    note = _cache_note(root, now)
    opened = [i for i in d["issues"] if i["state"] == "open"]
    undecided = sum(1 for i in opened if "proposal" in i["labels"] and not {"approved", "rejected"} & set(i["labels"]))
    observing = sum(1 for i in opened if "status:observing" in i["labels"])
    n_hil = None if hil is None else sum(1 for r in hil if r and r[-1].lower() == "open")
    n_mq = None if mq is None else sum(1 for r in mq if "대기" in r)
    seq_txt = "" if not seqs else " " + " ".join(f"#{x}" for x in seqs[:6])
    items = [("HIL-LEDGER open", "HIL-LEDGER", n_hil, "파일 없음", ""),
             ("큐 [HIL]·[긴급] 미처리", "큐 [HIL]·[긴급]", None if seqs is None else len(seqs), "큐·planner 명부 읽기 실패", seq_txt),
             ("MERGE-QUEUE 대기", "MERGE-QUEUE", n_mq, "파일 없음", ""),
             ("제안 미결정", "제안", undecided, "", note), ("관찰 중", "관찰 중", observing, "", note)]
    if all(n == 0 for _, _, n, _, _ in items) and not note:
        return ["오빠가 정할 것: 없음 — 오늘 질문 0"]
    return [f"- {label} {n}{extra}" if n is not None else f"- {short} 확인 불가({why})" for label, short, n, why, extra in items]
