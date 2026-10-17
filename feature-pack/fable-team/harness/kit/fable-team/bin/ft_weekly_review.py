#!/usr/bin/env python3
"""주간 점검표 2장(planner P1~P6 · 하네스 H1~H7)의 «사실 칸»만 채우고 두 master 에 1통씩 알린다 (R131 · 판정 1483·1487).

도구는 판단 0 — 결정 칸은 항상 비운다. 외부 호출 0(로컬 git·파일·mbox 큐). 같은 주 재실행 = 파일 덮어쓰기 0 · «재측정» 절만 추가 · 쪽지 0.
env: FT_PLANNER_REPO · FT_HARNESS_REPO · FT_MBOX · FT_HARNESS_INFO · FT_DRIFT_CMD · FT_DUMB_LEDGER · FT_LIVE_BIN · FT_REVIEW_NOW
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

from ft_weekly_table import carry, notified_state, render, set_notified, table_rows

MAIL_ON_RERUN = False
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PRUNE = {".git", "node_modules", ".worktrees", ".venv"}


def run(cmd: str, *extra: str) -> tuple[int, str]:
    p = subprocess.run(shlex.split(cmd) + list(extra), capture_output=True, text=True, timeout=60)
    return p.returncode, (p.stdout + p.stderr).strip()


def p1_queue(repo: Path) -> str:
    d = repo / "design/planner"
    if not d.is_dir():
        raise FileNotFoundError(d)
    queues = sorted(d.glob("DECISIONS-oppa-queue-*.md"))
    if not queues:
        return "없음 (대기열 파일 0)"
    ids = [c[0] for c in table_rows(queues[-1].read_text(encoding="utf-8")) if re.fullmatch(r"[A-Z]?\d+", c[0]) and not c[-1]]
    return f"열린 행 {len(ids)}건: {', '.join(ids)}" if ids else "없음 (열린 행 0)"


def p2_ledger(repo: Path) -> str:
    rows = table_rows((repo / "design/planner/PLAN-oppa-ledger.md").read_text(encoding="utf-8"))
    bad = [c[1][:30] for c in rows if len(c) == 5 and c[3].startswith("진행") and not re.search(r"\d", c[4])]
    return f"진행 줄인데 쪽지 번호 0: {len(bad)}줄 ({' / '.join(bad)})" if bad else "없음 (쪽지 번호 0 진행 줄 0)"


def dumb_keys(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    keys = [f"{c[1]}|{c[2][:24]}" for c in table_rows(text) if len(c) > 2 and c[0].isdigit()]
    return keys + [ln[:40] for ln in text.splitlines() if ln.startswith("- [")]


def p4_penalty(keys: list[str], prev: dict) -> str:
    if "dumb_keys" not in prev:
        return f"과징 원장 {len(keys)}행 · 확인 못 함: 지난주 기준 없음(첫 점검)"
    new = [k for k in keys if k not in prev["dumb_keys"]]
    return f"과징 원장 {len(keys)}행 · 지난주 {len(prev['dumb_keys'])}행 · 새 행 {len(new)}" + (f": {'; '.join(new)}" if new else "")


def h1_cards(repo: Path, now: datetime) -> list[tuple[str, str]]:
    d = repo / "design/harness/indices/진행"
    cards = sorted(d.glob("*.md"))
    out = []
    for c in cards:
        r = subprocess.run(["git", "-C", str(repo), "log", "-1", "--format=%ct", "--", str(c.relative_to(repo))], capture_output=True, text=True)
        ct = r.stdout.strip()
        out.append((f"H1 {c.stem}", f"마지막 변경 {(now - datetime.fromtimestamp(int(ct))).days}일" if ct else "확인 못 함: git 이력 없음"))
    return out or [("H1 진행 카드", "없음 (진행 카드 0장)")]


def h2_requests(repo: Path) -> list[tuple[str, str]]:
    rows = table_rows((repo / "design/harness/REQUEST-LEDGER.md").read_text(encoding="utf-8"))
    op = [c for c in rows if len(c) >= 7 and re.fullmatch(r"R\d+", c[0]) and not c[6] and not re.match(r"(닫힘|보류|반려|폐기|완료)", c[5])]
    op.sort(key=lambda c: int(c[0][1:]))
    return [(f"H2 {c[0]}", f"접수 {c[1]} · {c[3][:60]}") for c in op] or [("H2 요청 원장", "없음 (열린 요청 0)")]


def h4_drift(live_bin: Path) -> str:
    rc, out = run(os.environ.get("FT_DRIFT_CMD") or f"bash {HERE}/ft-live-bin-drift-check.sh --bin {live_bin}")
    return f"drift-check rc={rc} · " + " / ".join(ln[:80] for ln in out.splitlines()[:3])


def h8_secret_scan() -> str:  # R135b ③ — 스캐너 --report 1줄(스캔 0 · 쪽지 0)
    rc, out = run(os.environ.get("FT_SECRET_SCAN_CMD") or f"bash {HERE}/ft-secret-scan.sh --report")
    return out.splitlines()[0] if rc == 0 and out else f"확인 못 함: ft-secret-scan.sh --report rc={rc}"


def h6_growth(repo: Path, live_bin: Path, prev: dict) -> tuple[str, int]:
    baks = 0
    for root in (repo, live_bin):
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in PRUNE]
            baks += sum(".bak-" in f for f in fns)
    size = (repo / "design/harness/REQUEST-LEDGER.md").stat().st_size
    diff = f"{size - prev['req_ledger']:+d}B" if "req_ledger" in prev else "기준 없음"
    return f".bak-* {baks}개 · REQUEST-LEDGER.md {size}B (지난주 대비 {diff})", size


def safe(key: str, fn) -> list[tuple[str, str]]:
    try:
        got = fn()
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        return [(key, "확인 못 함: " + re.sub(r"\s+", " ", str(e)))]
    return got if isinstance(got, list) else [(key, got)]


def previous(weekly: Path, kind: str, monday: str) -> tuple[str, dict]:
    old = [p for p in sorted(weekly.glob(f"REVIEW-{kind}-*.md")) if p.stem.rsplit("-", 1)[1] < monday] if weekly.is_dir() else []
    text = old[-1].read_text(encoding="utf-8") if old else ""
    m = re.search(r"<!-- snap: (\{.*\}) -->", text)
    return text, json.loads(m.group(1)) if m else {}


def write_week(path: Path, title: str, monday: str, rows, snap: dict, prev_text: str, now: datetime, seat: str) -> None:
    """새 주 = 표 파일 생성(통보 상태 fail 로 시작) · 같은 주 = «재측정» 절만 추가."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        with path.open("a", encoding="utf-8") as f:
            f.write(f"\n## 재측정 {now:%H:%M}\n" + "".join(f"- {k}: {fact}\n" for k, fact in rows))
    else:
        path.write_text(render(title, monday, rows, snap, carry(prev_text), seat), encoding="utf-8")


def newest(lines: list[str], team: str) -> str | None:
    found = [(int(m.group(2)), m.group(1)) for ln in lines if (m := re.match(rf"(byz-{team}-master-claude)#(\d+)\b", ln))]
    return f"{max(found)[1]}#{max(found)[0]}" if found else None


def main() -> int:
    now = datetime.fromisoformat(os.environ["FT_REVIEW_NOW"]) if os.environ.get("FT_REVIEW_NOW") else datetime.now()
    monday = (now.date() - timedelta(days=now.weekday())).strftime("%Y%m%d")
    planner = Path(os.environ.get("FT_PLANNER_REPO") or ROOT / ".worktrees/v6-realtime-live")
    harness = Path(os.environ.get("FT_HARNESS_REPO") or ROOT / ".worktrees/harness-ops")
    live_bin = Path(os.environ.get("FT_LIVE_BIN") or ROOT / ".fable-team/bin")
    p = subprocess.run(shlex.split(os.environ.get("FT_HARNESS_INFO") or f"bash {HERE}/ft-harness-info.sh") + ["seats"], capture_output=True, text=True, timeout=60)
    rc, seats_out = p.returncode, p.stdout  # 좌석 줄은 stdout 만 — stderr 경고(로케일 등)는 좌석이 아니다
    seats = [ln for ln in seats_out.splitlines() if ln.strip()]
    to_planner, to_harness = newest(seats, "planner"), newest(seats, "harness")
    if rc != 0 or not (to_planner and to_harness):
        print(f"ERROR 받는 이(현역 master)를 seats 에서 못 찾음 rc={rc} planner={to_planner} harness={to_harness}", file=sys.stderr)
        return 3
    pw, hw = planner / "design/planner/weekly", harness / "design/harness/weekly"
    (p_text, p_prev), (h_text, h_prev) = previous(pw, "planner", monday), previous(hw, "harness", monday)
    dumb = Path(os.environ.get("FT_DUMB_LEDGER") or Path.home() / ".claude/rules/dumb-time-ledger.md")
    keys: list[str] = []
    try:
        keys = dumb_keys(dumb)
        p4 = [("P4 지난주 오빠 지적", p4_penalty(keys, p_prev))]
    except (OSError, ValueError) as e:
        p4 = [("P4 지난주 오빠 지적", f"확인 못 함: {e}")]
    p_rows = (safe("P1 결정 대기열", lambda: p1_queue(planner)) + safe("P2 원장↔발주 대조", lambda: p2_ledger(planner))
              + [("P3 정본 위생", "손 점검 — 복제 규칙 · 옛 좌석 이름 · 날짜 지난 서술")] + p4
              + [("P5 좌석 명부", f"현역 좌석 {len(seats)}줄 (ft-harness-info.sh seats) · planner master {to_planner} · 하네스 master {to_harness}"),
                 ("P6 팀 정의 변경 요청", "손 점검 — 다음 주로 넘길 것 / 오빠께 물을 것")])
    grown = h6_growth(harness, live_bin, h_prev) if (harness / "design/harness/REQUEST-LEDGER.md").is_file() else ("확인 못 함: REQUEST-LEDGER.md 없음", None)
    h_rows = (safe("H1 진행 카드", lambda: h1_cards(harness, now)) + safe("H2 요청 원장", lambda: h2_requests(harness))
              + [("H3 점검 도구", "손 점검 — 도구 없음 (R120 ft-harness-check.sh 랜딩 전)")] + safe("H4 설치 정합", lambda: h4_drift(live_bin))
              + [("H4 머신·자동로드", "손 점검 — 머신별 반영 행 · 자동 로드 예산(#3 RULE)"), ("H5 진화", "손 점검 — 이번 주 손으로 2회 이상 반복된 일"),
                 ("H6 노후·누적", grown[0]),
                 ("H7 드랍 후 재구성 이관", "빈 표 틀 — ①옛 것 아카이브(경로·sha) ②옮김/버림 목록 ③옛 경로 grep 0")]
              + safe("H8 비밀 기록 스캔", h8_secret_scan))
    targets = [(pw / f"REVIEW-planner-{monday}.md", "planner", p_rows, {"dumb_keys": keys}, p_text, to_planner),
               (hw / f"REVIEW-harness-{monday}.md", "하네스", h_rows, {"req_ledger": grown[1]} if grown[1] is not None else {}, h_text, to_harness)]
    failed = 0
    for path, title, rows, snap, prev_text, to in targets:
        write_week(path, title, monday, rows, snap, prev_text, now, to)
        if notified_state(path) != "ok" or MAIL_ON_RERUN:  # 이미 알린(ok) 좌석은 다시 보내지 않고 fail 만 재시도
            rc, out = send(to, path)
            set_notified(path, to, "ok" if rc == 0 else "fail")
            if rc != 0:
                failed += 1
                print(f"ERROR 통보 실패 to={to} rc={rc} {out.splitlines()[0][:80] if out else ''} — 같은 주 재실행이 재시도", file=sys.stderr)
        print(path)
    return 4 if failed else 0


def send(to: str, path: Path) -> tuple[int, str]:
    try:
        return run(os.environ.get("FT_MBOX") or f"bash {ROOT}/.fable-team/comm/mbox.sh", "send", to, "ft-weekly-review", f"[주간 점검] {path}")
    except (OSError, subprocess.SubprocessError) as e:
        return 127, str(e)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as e:
        print(f"ERROR {e}", file=sys.stderr)
        sys.exit(3)
