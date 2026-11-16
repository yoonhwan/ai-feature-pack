"""ft_board_news — 오빠 thread 상태 답글의 본문·열쇠 (r2058 · 판정 4175). ft-board-publish.sh --news 가 부른다.

  ft_board_news.py --collect <collect dict> --last <news-last.json> --body <본문 출력> --state <새 news-last 출력>
  stdout 1줄: «POST» = 본문·새 상태를 썼다(발행은 부르는 쪽) · «변화 없음 …» · «디바운스 …» = 발행 0 · rc≠0 = 본문 못 만듦
열쇠 = 근거 줄 · 바뀐 것 줄 · «다음» 칸을 뺀 본문 줄(r2095 · 골 · 승인 대기 · 확인 불가 팀) — 끝난 일이 있으면 열쇠가 같아도 발행.
팀 카드 수 · 좌석 열림 · 대기↔진행 이동 · 시각은 열쇠에 없다(같은 글 0통).
골 진행 정본 = env FT_GOAL_PROGRESS_MD(파일 | gitref:<ref>:<경로> · 기본 gitref:origin/main:design/teams/planner/PLAN-oppa-ledger.md) «## 골 진행» 첫 표.
도구는 골 진행 수를 만들지 않는다 — 표가 없으면 «골 진행 표 없음» 1줄 · 수가 이상하면 «수 판독 불가».
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from ft_board_news_body import MAX_BYTES, NO_TABLE, body, news, stale_warns, standing
from ft_board_news_name import card_disp, titles  # noqa: F401 — card_disp = 옛 이름(시험 호환)

DEBOUNCE_S = 300
DEFAULT_MD = "gitref:origin/main:design/teams/planner/PLAN-oppa-ledger.md"
FOLDERS = ("대기", "진행", "완성")
CLOSED = ("닫힘", "은퇴", "정지(세션 없음)")  # SeatCells text — 명부상 닫힌 좌석 = 열린 세션 아님(A6 · DA R2)


def read_md(spec: str, root: str) -> tuple[str | None, str]:
    """(본문 | None, 원장 sha10) — gitref 는 git show 1회(7초) · 파일은 그대로 읽는다."""
    try:
        if spec.startswith("gitref:"):
            _, ref, path = spec.split(":", 2)
            run = lambda *a: subprocess.run(["git", "-C", root, *a], capture_output=True, text=True, timeout=7)  # noqa: E731
            r = run("show", f"{ref}:{path}")
            if r.returncode != 0:
                return None, "원장 없음"
            return r.stdout, run("rev-parse", ref).stdout.strip()[:10] or "sha 불명"
        text = Path(spec).read_text(encoding="utf-8")
        return text, hashlib.sha1(text.encode()).hexdigest()[:10]
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None, "원장 없음"


def goal_rows(text: str | None) -> list[list[str]] | None:
    """«## 골 진행» 절의 첫 표 행들 [번호, 이름, n, m, 지금 상태] — 절·표·행 없음 = None."""
    if text is None:
        return None
    lines, inside, table = text.splitlines(), False, []
    for line in lines:
        s = line.strip()
        if s.startswith("## "):
            if inside:
                break
            inside = s == "## 골 진행"
        elif inside and s.startswith("|"):
            table.append([c.strip() for c in s.strip("|").split("|")])
        elif inside and table:
            break
    rows = [(r + [""] * 5)[:5] for r in table[2:]] if len(table) > 2 and set(table[1][0]) <= set("-: ") else []
    return rows or None


def seat_card(name: str, block: dict, all_states: dict) -> tuple[str, str]:
    """(카드 id | —, 단계) — 나노 = 좌석 이름의 카드 slug · 그 밖 = collect 진행 카드의 좌석 · 단계 = 카드 폴더."""
    m = re.match(r"byz-[^-]+-nano-(.+?)(#\d+)?$", name)
    if m:
        slug = m.group(1)
        for states in (block.get("states") or {}, all_states):
            for cid, st in states.items():
                if cid == slug or re.sub(r"[^a-z0-9-]", "-", cid.lower())[:40] == slug:
                    return cid, st
        return slug, "카드 없음"
    for cid, p in (block.get("progress") or {}).items():
        if any(s.get("name") == name for s in p.get("seats", [])):
            return cid, (block.get("states") or {}).get(cid, "카드 없음")
    return "—", "—"


def snapshot(d: dict, rows: list | None, prev: dict | None = None) -> dict:
    """수집 실패 팀(error 블록) = 직전 발행 상태를 이어 씀(열쇠·변화 0 · DA R1) — 직전에도 없으면 빈칸 · err 에 이름."""
    teams = [t for t in d["teams"] if "error" not in t]
    err = sorted(t["label"] for t in d["teams"] if "error" in t)
    all_states = {c: s for t in teams for c, s in (t.get("states") or {}).items()}
    sessions = {}
    for t in teams:
        for name, cell in sorted((t.get("seats") or {}).items()):
            if not str((cell or {}).get("text", "")).startswith(CLOSED):
                sessions[name] = [t["label"], *seat_card(name, t, all_states)]
    snap = {"goals": rows, "cards": {t["label"]: t.get("states") or {} for t in teams},
            "counts": {t["label"]: [(t.get("counts") or {}).get(f, 0) for f in FOLDERS] for t in teams},
            "sessions": sessions, "h_by": {t["label"]: sorted(set(t.get("oppa_todo") or [])) for t in teams}, "err": err, "carried": []}
    for label in err if prev else []:  # carried = 직전 상태를 실제로 이어 쓴 팀만(«확인 불가» 줄 · R3)
        if label in prev["cards"]:
            snap["cards"][label], snap["counts"][label] = prev["cards"][label], prev["counts"][label]
            snap["carried"].append(label)
        old = {n: v for n, v in prev["sessions"].items() if v[0] == label}
        snap["sessions"].update(old)
        snap["carried"] += [label] if old and label not in snap["carried"] else []
        snap["h_by"][label] = (prev.get("h_by") or {}).get(label, [])  # 승인 대기도 직전 값(R4 · 열쇠 밖)
    snap["h"] = len({n for v in snap["h_by"].values() for n in v})
    return snap


def key(s: dict) -> list[str]:
    return standing(s)


def main() -> int:
    ap = argparse.ArgumentParser()
    for a in ("--collect", "--last", "--body", "--state"):
        ap.add_argument(a, required=True)
    a = ap.parse_args()
    now = datetime.fromisoformat(os.environ["FT_BOARD_NOW"]) if os.environ.get("FT_BOARD_NOW") else datetime.now()
    text, sha = read_md(os.environ.get("FT_GOAL_PROGRESS_MD") or DEFAULT_MD, os.environ.get("FT_ROOT") or ".")
    rows = goal_rows(text)
    if rows is None:
        print(f"WARN ft_board_news: {NO_TABLE} — 골 줄 없이 발행", file=sys.stderr)
    for w in stale_warns(rows):
        print(w, file=sys.stderr)
    last = json.loads(Path(a.last).read_text(encoding="utf-8")) if Path(a.last).is_file() else None
    cur = snapshot(d := json.loads(Path(a.collect).read_text(encoding="utf-8")), rows, last and last.get("snap"))
    done = any(ids for _, ids in news(last and last.get("snap"), cur, lambda team, cid: cid))
    if last and last.get("key") == key(cur) and not done:
        print("변화 없음 — 발행 0")
        return 0
    if last and (gap := (now - datetime.fromisoformat(last["at"])).total_seconds()) < DEBOUNCE_S:
        print(f"디바운스 — 직전 발행 {int(gap)}초 전 · 발행 0")
        return 0
    out = body(cur, last and last.get("snap"), now, sha, titles(d))
    if len(out.encode()) > MAX_BYTES:
        print(f"ERROR ft_board_news: 본문 {len(out.encode())}B > {MAX_BYTES}B — 발행 0", file=sys.stderr)
        return 1
    Path(a.body).write_text(out, encoding="utf-8")
    Path(a.state).write_text(json.dumps({"at": now.isoformat(), "key": key(cur), "snap": cur}, ensure_ascii=False), encoding="utf-8")
    print("POST")
    return 0


if __name__ == "__main__":
    sys.exit(main())
