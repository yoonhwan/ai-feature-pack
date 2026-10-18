"""ft_goal_gate — 뉴스 발행 경로의 골 표 문 (R362 · ft_news_publish·ft_news_post·ft_news_ledger 가 부른다 · 판정은 ft_goal_table.check 하나).

무장 표식 = <루트>/.fable-team/state/goal-gate.armed — 있으면 REJECT(발행 0 + planner [긴급] 1통) · 없으면 WOULD-REJECT 로그(state/mbox-guard-goal.log)만 남기고 진행(설치 전환 · 되돌림 = 표식 삭제).
첫 판 = 골 표 블록 필수(check --block-only · 후속 표지가 있어도 첫 원소는 «무조건» 실제 블록 검사). 후속 판 `(n/N)` n>1 = 머리에 `골표 <sha10>·<run id>` + 같은 묶음의 «검증 영수증»(state/goal-bundle.json)과 일치해야 한다.
영수증 = ft_news_post 가 판 묶음 «전체»(첫 판 블록 · 묶음 표지 · 판번호 2..N 연속 · 총수 · run id 동일)를 보내기 전에 검증한 뒤 쓴다 — 단독 publisher 는 영수증 없는 후속 표지·이미 나간 판번호를 REJECT.
무장 거절 통지 = refuse() 한 곳(공통 함수 1개 · 같은 거절 10분 안 중복 억제 · 쪽지는 [긴급] 이라 가드 재귀 0). CLI: `python3 ft_goal_gate.py notify <루트> <진입점> <사유>`(매거진 등 다른 프로세스용).
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import ft_goal_table as gt
from ft_goal_receipt import CONT, TOKEN, begin, check_part, finish, is_done, mark_done  # noqa: F401 — 영수증 수명은 ft_goal_receipt 한 곳(재노출)
from ft_goal_receipt import first as _first

LOG = logging.getLogger("ft_goal_gate")
MSG_CHARS = 280  # 쪽지에 싣는 사유 글자 수(시간 상한 아님)
DEDUP_S = 10 * 60  # 같은 거절 통지 억제 창
SHA = re.compile(r"^★골 표 A6 \(([0-9a-f]{10}) ", re.M)


def armed(state_dir: Path) -> bool:
    return (state_dir / "goal-gate.armed").is_file()


def problem(body: str, state_dir: Path) -> str:
    """이 판 하나의 문제(없으면 빈 글) — 판정 중 예외도 «문제» 로 돌려준다(조용한 통과 0)."""
    try:
        first = _first(body)
        m = CONT.search(first)
        if not (m and int(m[1]) > 1):
            rc, msg = gt.check(body, block_only=True)
            return "" if rc == 0 else msg.removeprefix("REJECT ")
        if not (t := TOKEN.search(first)):
            return "이어진 판 머리에 `골표 <sha10>·<run id>` 묶음 표지가 없다"
        return check_part(state_dir, body, int(m[1]), int(m[2]), t)
    except Exception as e:  # noqa: BLE001 — 판정기 자체 예외도 문(fail-closed) 의 입력이다
        return f"골 표 판정 실패 {type(e).__name__}: {e}"


def verify_bundle(parts: list[str]) -> str:
    """판 목록 «전체» 사전검증 — 첫 원소는 무조건 실제 블록 check · 이어진 판은 판번호 2..N 연속·총수·sha10·run id 동일."""
    try:
        if not parts:
            return ""
        rc, msg = gt.check(parts[0], block_only=True)
        if rc != 0:
            return f"1/{len(parts)}판: {msg.removeprefix('REJECT ')}"
        head = CONT.search(_first(parts[0]))
        if head and int(head[1]) != 1:
            return f"1/{len(parts)}판: 첫 판 머리가 {head[1]}/{head[2]} 판으로 표기됐다"
        sha, runs = SHA.search(parts[0])[1], set()  # type: ignore[index]
        for i, p in enumerate(parts[1:], 2):
            first = _first(p)
            c, t = CONT.search(first), TOKEN.search(first)
            if not c or (int(c[1]), int(c[2])) != (i, len(parts)):
                return f"{i}/{len(parts)}판: 판번호·총수 표기가 순서와 다르다(누락·중복)"
            if not t or t[1] != sha:
                return f"{i}/{len(parts)}판: 묶음 표지(골표 sha10)가 첫 판 블록과 다르다"
            runs.add(t[2])
        return "" if len(runs) <= 1 else "판마다 run id 가 다르다(다른 묶음 혼합)"
    except Exception as e:  # noqa: BLE001
        return f"골 표 묶음 검증 실패 {type(e).__name__}: {e}"


def write_receipt(state_dir: Path, parts: list[str]) -> str:
    """검증을 통과한 묶음의 영수증을 열거나 이어 받는다 — 후속 판이 1장이라도 있을 때만 · 문제(이미 완료·다른 본문)면 그 글, 쓰기 실패도 문제로."""
    try:
        return begin(state_dir, parts)
    except Exception as e:  # noqa: BLE001 — 영수증을 못 쓰면 후속 판 검증이 불가능하다 = 문 입력(조용한 통과 0)
        return f"검증 영수증 쓰기 실패 {type(e).__name__}: {e}"


def log(state_dir: Path, line: str) -> None:
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        with (state_dir / "mbox-guard-goal.log").open("a", encoding="utf-8") as f:
            f.write(f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} {line}\n")
    except OSError as e:
        LOG.warning("골 표 문 로그 쓰기 실패: %s", e)


def notify_planner(root: Path, who: str, why: str) -> bool:
    """`[긴급] 뉴스 발행 거절 — 골 표` 1통 → 현역 planner(seats-planner.json _master) · 같은 거절은 10분 안 1번만. 실패는 로그(거절 자체는 이미 났다)."""
    state = root / ".fable-team" / "state"
    key, stamp = hashlib.sha1(f"{who}\n{why}".encode()).hexdigest()[:16], state / "goal-notify.json"  # 지문 = 진입점 + 사유 «전체» (본문만 줄인다)
    try:
        seen = json.loads(stamp.read_text(encoding="utf-8")) if stamp.exists() else {}
        if time.time() - seen.get(key, 0) < DEDUP_S:
            return False
        master = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"]
        mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
        body = f"[긴급] 뉴스 발행 거절 — 골 표\n진입점: {who}\n{why[:MSG_CHARS]}\n조치: ft-goal-table.sh 출력·정본·상태 파일 점검"
        done = subprocess.run(["bash", mbox, "send", master, "ft-news-ledger", body], capture_output=True, check=False, timeout=15)
        if done.returncode == 0:
            stamp.parent.mkdir(parents=True, exist_ok=True)
            stamp.write_text(json.dumps({**seen, key: time.time()}), encoding="utf-8")
        return done.returncode == 0
    except (OSError, KeyError, ValueError, subprocess.TimeoutExpired) as e:
        LOG.warning("planner 거절 알림 실패: %s", e)
        return False


def refuse(state_dir: Path, who: str, why: str) -> bool:
    """True = 막는다(무장 · 로그 + planner [긴급] 1통). 아니면 WOULD-REJECT 로그만. 모든 진입점이 이 한 함수를 부른다."""
    on = armed(state_dir)
    log(state_dir, f"{'REJECT' if on else 'WOULD-REJECT'} news={who} {why[:200]}")
    if on:
        notify_planner(state_dir.parents[1], who, why)
    return on


def goal_block(state_dir: Path) -> str:
    """뉴스에 실을 골 표 블록 — 무장이면 렌더 실패 = 로그 + 통지 + 예외(발행 0) · 비무장이면 WOULD-REJECT 로그 + 빈 글(블록 없이 진행)."""
    try:
        return gt.render()
    except (gt.GoalError, OSError, ValueError) as e:
        if refuse(state_dir, "render", str(e)):
            raise gt.GoalError(str(e)) from e
        return ""


if __name__ == "__main__":
    if sys.argv[1:2] == ["notify"] and len(sys.argv) == 5:
        raise SystemExit(0 if notify_planner(Path(sys.argv[2]), sys.argv[3], sys.argv[4]) else 1)
    raise SystemExit("usage: ft_goal_gate.py notify <루트> <진입점> <사유>")
