"""ft-sheet-events `reconcile --confirm` 의 authoritative 확인 — prepared 잔존(도구가 죽음) 사건을 «성공» 으로 승격해도 되는지 사실로 가린다 (PLAN §3-1 재실행 행).

spawn=좌석 실재 · nano-close=명부에서 사라짐+세션 없음 · land-candidate=후보 sha 객체 실재 · issue-close/label=gh 상태(7초+1) · stop-ready/done=쪽지 로그에 같은 본문 sha16.
확인 못 하면 False — 승격 0(prepared 그대로). 추측으로 승격하지 않는다.
"""
import json
import re
import os
import subprocess
import sys
from pathlib import Path

import ft_board_env as env
from ft_board_mail import PREFIX
from ft_sheet_key import sha16


def _seat_in_roster(root: Path, seat: str) -> bool:
    return any(seat in json.loads(p.read_text(encoding="utf-8")) for p in (root / ".fable-team").glob("seats*.json"))


def _gh_issue(num: str, field: str) -> str:
    cmd = ["gh", "issue", "view", num, "-R", "SecondWindStudio/byz-agents", "--json", field]
    for _ in range(env.GH_RETRIES + 1):
        try:
            return env.run(cmd, "gh issue view", timeout=env.GH_TIMEOUT_S)
        except (RuntimeError, subprocess.TimeoutExpired):
            continue
    return ""


def gh_state(num: str) -> int:
    cmd = ["gh", "issue", "view", num, "-R", os.environ.get("FT_ISSUE_REPO", "SecondWindStudio/byz-agents"), "--json", "state", "--jq", ".state"]
    for _ in range(env.GH_RETRIES + 1):  # 7초 룰 — 1회 7초 + 재시도 1
        try:
            print(env.run(cmd, "gh issue view", timeout=env.GH_TIMEOUT_S).strip())
            return 0
        except (RuntimeError, subprocess.TimeoutExpired):
            continue
    print("확인 불가", file=sys.stderr)
    return 1


def _mail_has(root: Path, seat: str, digest: str) -> bool:
    for fn in ("mailbox.jsonl", "mailbox.log.jsonl"):
        p = root / ".fable-team" / "comm" / fn
        for ln in p.read_text(encoding="utf-8").splitlines() if p.exists() else []:
            r = json.loads(ln) if ln.strip() else {}
            if r.get("from") == seat and sha16(PREFIX.sub("", str(r.get("body", "")), count=1)) == digest:
                return True
    return False


def confirm(row: dict) -> bool:
    root, ev, key = env.ft_root(), row["ev"], row["key"]
    tail = key.rsplit(":", 1)[-1]
    if ev == "spawn":
        return row["seat"] in env.tmux_alive()
    if ev == "nano-close":
        return row["seat"] not in env.tmux_alive() and not _seat_in_roster(root, row["seat"])
    if ev == "land-candidate":
        return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{tail}^{{commit}}"], capture_output=True).returncode == 0
    if ev == "issue-close":
        return '"CLOSED"' in _gh_issue(key.split("#", 1)[1], "state")
    if ev == "label":
        num = re.match(r"label:#(\d+):", key)[1]
        return f'"{tail}"' in _gh_issue(num, "labels")
    if ev in ("stop-ready", "done"):
        return _mail_has(root, row["seat"], tail)
    return False
