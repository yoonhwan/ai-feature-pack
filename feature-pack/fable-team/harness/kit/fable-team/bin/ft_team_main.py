#!/usr/bin/env python3
"""ft_team_main.py render <팀>|--all — r1315 1단계: 팀 메인 파일(STATE)을 «머리 + ①절대 지침 + ②카드 + ③배정받은 작업» 고정 꼴로 다시 쓴다.
쓰기 = `<데이터 루트>/.fable-team/state/team-main/<팀>/{STATE.md,archive/STATE-closed-YYYYMM.md,cards-baseline.tsv}` 뿐(추적 파일 0 · 커밋 0 · 도구 실행 0).
닫힌 줄 = 직전 «정상 회차» 기준 파일에 있고 이번에 빠진 ② 진행 카드 → 그 달 archive append(삭제 0). ② 판정 불가 회차 = 비교·기준 갱신 0.
절당 40줄 넘으면 계속 쓰고 머리줄 WARN · 실패는 그 칸만 «판정 불가(사유)» · stderr 팀마다 1줄 `team-main <팀> 진행 N 대기 N 완성미확인 N 발주 N 결정 N`
env: FT_ROOT · FT_TEAMS_MD · FT_TEAM_MAIN_NOW(epoch) · FT_DIRECTIVE_TABLE · FT_DIRECTIVE_REF · FT_TEAM_MAIN_GIT_SEC(7)
"""
from __future__ import annotations

import os
import re
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ft_team_lib  # noqa: E402
import ft_team_main_inputs as inputs  # noqa: E402

MAX_LINES = 40  # 절당 상한(넘으면 WARN · 내용 보존)
USAGE = "사용: ft-team-main.sh render <팀>|--all"

def _data_root(root: Path) -> Path:  # FT_ROOT · 아니면 공용 루트의 LIVE_ROOT(ft_team_lib.data_root 규칙)
    out = ft_team_lib._git_out(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    c = out.stdout.strip()
    if not out.returncode and c:
        return Path(ft_team_lib.data_root(Path(c).parent if c.endswith("/.git") else Path(c)))
    raise inputs.Undecided("git 공용 루트 못 읽음")

def _write(path: Path, lines: list[str]) -> None:  # 임시 파일 + os.replace = 중간에 잘린 STATE 0
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp-{os.getpid()}")
    with tmp.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
        fh.flush(), os.fsync(fh.fileno())
    os.replace(tmp, path)

def _sec_directive(team: str, ctx: dict) -> list[str]:
    out = [f"## ① 절대 지침 (지시 정본 표 · 이 팀 행 · render {ctx['hhmm']})"]
    try:
        keep, miss = inputs.directive(ctx["repo"], ctx["dref"], team, os.environ.get("FT_DIRECTIVE_TABLE"))
    except inputs.Undecided as e:
        return out + [f"판정 불가({e})"]
    out += ["| 지시 # | 날짜·ts | 원문(표 그대로) | 상태 | 닫는 증거 |", "|---|---|---|---|---|",
            *(f"| {r['n']} | {r['when']} | {r['text']} | {r['status']} | {r['ev']} |" for r in keep)]
    out += [] if keep else ["이 팀 행 없음"]
    return out + ([f"팀 미지정 {len(miss)}: " + " ".join(f"#{n}" for n in miss)] if miss else [])

def _sec_cards(ctx: dict) -> tuple[list[str], dict[str, str]]:
    out = [f"## ② 카드 (render {ctx['hhmm']})"]
    if ctx["seats"] is None:
        out.append("좌석 칸 판정 불가(seats 파일 없음 · r1290 대기)")
    rows, seats = ctx["cards"], ctx["seats"] or {}
    if rows is None:
        return out + [f"판정 불가({ctx['cards_why']})"], {}
    prog, wait, done = rows.get("진행", []), rows.get("대기", []), rows.get("완성", [])
    out.append(f"진행 {len(prog)}장")
    cur = {r["stem"]: (f"- {r['stem']} · 지시 {'#' + str(r['n']) if r['n'] else '없음'}"
                       f" · 좌석 {seats.get(r['stem'], '?')} · 상태 {r['status'] or '판정 불가'}") for r in prog}
    out += list(cur.values())
    dated = sorted(m.group(0) for m in (re.search(r"\d{4}-\d{2}-\d{2}", r["status"] or "") for r in wait) if m)
    out.append(f"대기 {len(wait)}장 · 가장 오래 {dated[0] if dated else '판정 불가(날짜 없음)'}")
    bad = [r for r in done if not r["check"]]
    out.append(f"완성(확인 전) {len(bad)}장" + (f" · 최근 {', '.join(r['stem'] for r in bad[-3:])}" if bad else ""))
    return out, cur

def _feed(kind: str, items: list, team: str) -> tuple[str, dict]:
    """집계 종류별 ③ 한 줄 — 꼴 다름 = 그 줄만 판정 불가 · 결정은 좌석 토큰으로 귀속(같은 seq 1건)."""
    if kind == "card-assign":
        if not all(isinstance(i, dict) and isinstance(i.get("team"), str) and isinstance(i.get("kind"), str) for i in items):
            return "판정 불가(card-assign latest 꼴 다름)", {}
        c = Counter(i["kind"] for i in items if i["team"] == team)
        return (f"배정 없음 {c.get('없음', 0)} · 대기 초과 {c.get('초과', 0)} · 카드 없는 발주 {c.get('발주', 0)}"
                f" · 판정 불가 {c.get('판정 불가', 0)}"), {"발주": c.get("발주", 0)}
    if kind == "decision":
        if not all(isinstance(i, str) for i in items):
            return "판정 불가(decision latest 꼴 다름)", {}
        void, seen = 0, {}
        for it in items:
            token = inputs.SEAT.search(it)
            if not token:
                void += 1
            else:
                seen.setdefault(token.group(1), set()).add((inputs.SEQ.search(it.strip()) or ["", it.strip()[:20]])[1])
        mine = len(seen.get(team, ()))
        return f"결정 대기 {mine}건" + (f" · 좌석 토큰 없음 {void}건(planner 몫)" if team == "planner" and void else ""), {"결정": mine}
    if not all(isinstance(i, dict) and "id" in i and "minutes" in i for i in items):
        return "판정 불가(hil latest 꼴 다름)", {}
    if team != "planner":
        return "미실행 h 은 planner 몫", {}
    ids = " ".join(f"h{str(i['id']).lstrip('h')}" for i in items)
    return (f"미실행 h {len(items)}건" + (f" : {ids}" if ids else "")), {}


def _sec_assign(team: str, ctx: dict) -> tuple[list[str], dict[str, int]]:
    out, nums = [f"## ③ 배정받은 작업 (render {ctx['hhmm']} · 집계 판본 {ctx['stamp'] or '없음'})"], {"발주": 0, "결정": 0}
    for kind in ("card-assign", "decision", "hil"):
        try:
            line, extra = _feed(kind, inputs.latest(ctx["root"], kind, ctx["now"])["items"], team)
        except inputs.Undecided as e:
            line, extra = f"판정 불가({kind} {e})", {}
        out.append(line)
        nums.update(extra)
    cards = ctx["cards"] or {}
    out.append(f"지시 # 없음: 카드 {sum(1 for k in ('진행', '대기') for r in cards.get(k, []) if not r['n'])}장")
    return out, nums

def _baseline(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    return {ln.partition("\t")[0]: ln.partition("\t")[2] for ln in lines if "\t" in ln}

def _archive(folder: Path, now: float, prev: dict[str, str], cur: dict[str, str]) -> None:  # 빠진 진행 카드 → 그 달 archive(삭제 0)
    gone = [(s, v) for s, v in sorted(prev.items()) if s not in cur]
    if not gone:
        return
    path = folder / "archive" / f"STATE-closed-{time.strftime('%Y%m', time.localtime(now))}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(now))
    with path.open("a", encoding="utf-8", newline="\n") as fh:
        fh.writelines(f"- {stamp} 닫힘 · {line}\n" for _stem, line in gone)

def one(team: str, root: Path, data: Path, now: float, dormant: tuple[str, ...] = ()) -> str:  # → stderr 1줄 · 휴면은 머리 «휴면» 1줄
    folder, (head, seats) = data / ".fable-team/state/team-main" / team, inputs.tick_files(root, team)
    head = head or "헤드라인 없음"
    if team in dormant:
        _write(folder / "STATE.md", [f"{head}  [휴면]"])
        return f"team-main {team} 휴면"
    ctx: dict = {"root": root, "now": now, "hhmm": time.strftime("%m-%d %H:%M", time.localtime(now)), "seats": seats,
                 "cards": None, "cards_why": "", "stamp": "", "repo": str(root),
                 "dref": os.environ.get("FT_DIRECTIVE_REF") or "origin/main"}  # ① 지시 표는 언제나 origin/main(카드 설계 3)
    try:
        ctx["repo"], ref, rel = inputs.route(root, inputs.roots(root), team)
        ctx["cards"] = inputs.cards(ctx["repo"], ref, rel)
    except inputs.Undecided as e:
        ctx["cards_why"] = str(e)
    try:
        ctx["stamp"] = inputs.latest(root, "card-assign", now).get("stamp") or ""
    except inputs.Undecided:
        pass
    sec2, cur = _sec_cards(ctx)
    sec3, nums = _sec_assign(team, ctx)
    head_line = head + (f"  [상한 초과 ②+{len(cur) - MAX_LINES}줄 — 닫기 우선]" if len(cur) > MAX_LINES else "")
    if ctx["cards"] is not None:
        _archive(folder, now, _baseline(folder / "cards-baseline.tsv"), cur)
        _write(folder / "cards-baseline.tsv", [f"{k}\t{v}" for k, v in sorted(cur.items())])
    _write(folder / "STATE.md", [head_line, *_sec_directive(team, ctx), *sec2, *sec3])
    rows, unk = ctx["cards"] or {}, "?"
    return (f"team-main {team} 진행 {len(rows.get('진행', [])) if rows else unk} 대기 {len(rows.get('대기', [])) if rows else unk}"
            f" 완성미확인 {len([r for r in rows.get('완성', []) if not r['check']]) if rows else unk} 발주 {nums['발주']} 결정 {nums['결정']}")


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] != "render" or not argv[1]:
        print(USAGE, file=sys.stderr)
        return 2
    target, now = argv[1], float(os.environ.get("FT_TEAM_MAIN_NOW") or time.time())
    root = Path(os.environ["FT_ROOT"]) if os.environ.get("FT_ROOT") else Path(ft_team_lib.repo_root())
    try:
        active, dormant = ft_team_lib.team_names(root), tuple(ft_team_lib.team_names(root, "휴면"))
        data = _data_root(root)
    except (ft_team_lib.TeamPathError, inputs.Undecided) as e:
        print(f"ERROR 팀 메인 파일 렌더 판정 불가: {e}", file=sys.stderr)
        return 4
    teams = [*active, *dormant] if target == "--all" else [target]
    if target != "--all" and target not in teams:
        print(f"ERROR 팀 명단(TEAMS.md)에 없는 팀: {target}", file=sys.stderr)
        return 2
    rc = 0
    for team in teams:
        try:
            print(one(team, root, data, now, dormant), file=sys.stderr)
        except (OSError, inputs.Undecided) as e:
            print(f"team-main {team} 렌더 판정 불가 · {' '.join(str(e).split())[:120]}", file=sys.stderr)
            rc = 1
    return rc

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
