"""ft_board_news — 오빠 thread 상태 답글의 본문·열쇠 (r2058 · 판정 4175). ft-board-publish.sh --news 가 부른다.

  ft_board_news.py --collect <collect dict> --last <news-last.json> --body <본문 출력> --state <새 news-last 출력>
  stdout 1줄: «POST» = 본문·새 상태를 썼다(발행은 부르는 쪽) · «변화 없음 …» · «디바운스 …» = 발행 0 · rc≠0 = 본문 못 만듦
열쇠 = 골 진행 (번호·n·m) · 팀 카드 수 (대기·진행·완성) · 열린 팀 세션 (이름·카드·단계) — 시각·유휴 분·BUSY/IDLE 은 넣지 않는다.
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

DEBOUNCE_S = 300
MAX_CHANGES, MAX_SEATS, MAX_BYTES, MAX_LINE = 5, 12, 3500, 150
DEFAULT_MD = "gitref:origin/main:design/teams/planner/PLAN-oppa-ledger.md"
NO_TABLE = "골 진행 표 없음 — planner 원장 «## 골 진행»"
FOLDERS = ("대기", "진행", "완성")


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


def goal_line(row: list[str]) -> str:
    _, name, n, m, status = row
    if n in ("—", "-") or m in ("—", "-"):
        return f"{name} — {status}"
    if not (n.isdigit() and m.isdigit()) or int(m) == 0 or int(n) > int(m):
        return f"{name} 수 판독 불가"
    k = int(10 * int(n) / int(m) + 0.5)
    return f"{name} `{'▓' * k}{'░' * (10 - k)}` {n}/{m}" + (" 완성" if n == m else "")


def card_disp(cid: str) -> str:
    return re.sub(r"^r\d+[a-z]?-", "", cid)


def seat_short(name: str) -> str:
    s = re.sub(r"^byz-[^-]+-", "", re.sub(r"#\d+$", "", name))
    return re.sub(r"(^|-)r\d+[a-z]?(?=-)", r"\1", s).replace("--", "-")


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


def snapshot(d: dict, rows: list | None) -> dict:
    teams = [t for t in d["teams"] if "error" not in t]
    all_states = {c: s for t in teams for c, s in (t.get("states") or {}).items()}
    sessions = {}
    for t in teams:
        for name in sorted(t.get("seats") or {}):
            sessions[name] = [t["label"], *seat_card(name, t, all_states)]
    return {"goals": rows, "cards": {t["label"]: t.get("states") or {} for t in teams},
            "counts": {t["label"]: [(t.get("counts") or {}).get(f, 0) for f in FOLDERS] for t in teams},
            "sessions": sessions, "h": len({n for t in teams for n in t.get("oppa_todo") or []})}


def key(s: dict) -> dict:
    return {"goals": [[r[0], r[2], r[3]] for r in s["goals"]] if s["goals"] else None,
            "counts": s["counts"], "sessions": {n: v[1:] for n, v in s["sessions"].items()}}


def changes(prev: dict | None, cur: dict) -> list[str]:
    if prev is None:
        return ["첫 발행 — 직전 발행 없음"]
    out, before = [], {r[0]: r for r in prev.get("goals") or []}
    for r in cur["goals"] or []:
        p = before.get(r[0])
        if p is None or (p[2], p[3]) != (r[2], r[3]):
            out.append(f"{r[1]} {p[2] if p else '—'}→{r[2]} ({r[3]} 중)")
    for team in sorted(set(prev["cards"]) | set(cur["cards"])):
        a, b = prev["cards"].get(team, {}), cur["cards"].get(team, {})
        out += [f"{team} {card_disp(c)} {a.get(c, '없음')}→{b.get(c, '없음')}" for c in sorted(set(a) | set(b)) if a.get(c) != b.get(c)]
    ps, cs = prev["sessions"], cur["sessions"]
    for n in sorted(set(ps) | set(cs)):
        if n not in ps or n not in cs:
            out.append(f"{seat_short(n)} {'열림' if n in cs else '닫힘'}")
        elif ps[n][1] != cs[n][1]:
            out.append(f"{seat_short(n)} 카드 {card_disp(ps[n][1])}→{card_disp(cs[n][1])}")
    out = out or ["세부 줄 없음 — 카드 수만 바뀜"]
    return out[:MAX_CHANGES] + ([f"외 {len(out) - MAX_CHANGES}건"] if len(out) > MAX_CHANGES else [])


def body(cur: dict, prev: dict | None, now: datetime, sha: str) -> str:
    goals = [goal_line(r) for r in cur["goals"]] if cur["goals"] else [NO_TABLE]
    seats = [f"{v[0]} · {seat_short(n)} · {card_disp(v[1])} · {v[2]}" for n, v in sorted(cur["sessions"].items(), key=lambda x: (x[1][0], x[0]))]
    seats = (seats[:MAX_SEATS] + [f"외 {len(seats) - MAX_SEATS}석"] if len(seats) > MAX_SEATS else seats) or ["열린 팀 세션 없음"]
    todo = f"오빠 승인 대기 {cur['h']}건" if cur["h"] else "없음"
    lines = ["① 골 진행", *goals, "② 지금", *changes(prev, cur), "③ 다음", *seats, "④ 막힌 것·오빠 할 일", todo]
    lines = [ln if len(ln) <= MAX_LINE else ln[:MAX_LINE - 1] + "…" for ln in lines]
    return "\n".join(lines + [f"근거: 발행 {now:%Y-%m-%d %H:%M} · 골 진행 원장 {sha}"]) + "\n"


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
    cur = snapshot(json.loads(Path(a.collect).read_text(encoding="utf-8")), rows)
    last = json.loads(Path(a.last).read_text(encoding="utf-8")) if Path(a.last).is_file() else None
    if last and last.get("key") == key(cur):
        print("변화 없음 — 발행 0")
        return 0
    if last and (gap := (now - datetime.fromisoformat(last["at"])).total_seconds()) < DEBOUNCE_S:
        print(f"디바운스 — 직전 발행 {int(gap)}초 전 · 발행 0")
        return 0
    out = body(cur, last and last.get("snap"), now, sha)
    if len(out.encode()) > MAX_BYTES:
        print(f"ERROR ft_board_news: 본문 {len(out.encode())}B > {MAX_BYTES}B — 발행 0", file=sys.stderr)
        return 1
    Path(a.body).write_text(out, encoding="utf-8")
    Path(a.state).write_text(json.dumps({"at": now.isoformat(), "key": key(cur), "snap": cur}, ensure_ascii=False), encoding="utf-8")
    print("POST")
    return 0


if __name__ == "__main__":
    sys.exit(main())
