"""ft_goal_table — 자율 골 표(A6) 렌더 + 판정기 하나 (R362 · 쓰는 쪽 ft-goal-table.sh · 뉴스·매거진·쪽지 가드가 같은 함수를 부른다).

render  : 정본 표(골 → 팀 → 닫는 증거 6행) + planner 원장 `## 메인 골 6줄` 표(행 순번 결속 · ft_goal_ledger) → 마커 2줄(`★골 표 A6 (<sha10> · 상태 …)★` … `★/골 표★`) 사이 표 1개(≤1600B).
          골 원문 칸은 절단 0 · 팀·증거·상태 칸만 24자 + «…» · 넘치면 `ERROR 골 표 예산 초과` rc1 · 정본 없음/6행 아님 = `ERROR 골 표 정본 …` rc1.
check   : 본문에 ⓐ마커 블록(6행 = 마커 sha10 의 정본 골 칸과 일치) ⓑ`골좌표: <1~6> — <그 행 골 원문 앞 min(12,len)자>` 가 있으면 `GOAL-OK n=<번호>` rc0 · 아니면 `REJECT 골 없음 — …` rc3.
          `--block-only` = ⓑ 생략(다골 글: 뉴스·매거진).
teams   : 원장 `## 팀별 완성 진행` 첫 표(팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것) → 마커 2줄(`★팀별 완성 진행 (<원장 sha10>)★` … `★/팀별 완성 진행★`) 사이 표(≤1600B · R458).
          표 없음·예산 초과 = 빈 출력 + stderr WARN rc0 — 거절 게이트 0(뉴스·매거진을 멈추지 않는다 · check 는 골 표만).
정본 = env FT_GOAL_A6_MD(파일 경로 | `gitref:<ref>:<경로>` · 기본 = `gitref:<FT_TEAMS_REF·origin/main>:<planner 팀 폴더>/AUTONOMY-GOAL-A6-20261018.md` — r545: 체크아웃(LIVE_ROOT) 파일이 아니라 그 ref 에 올라간 판 · 폴더도 ref 트리에서 푼다) · 상태 = 원장 env FT_GOAL_A6_LEDGER(같은 두 형식 · 기본 같은 꼴) · 저장소 = FT_GOAL_REPO(기본 FT_LEDGER_REPO · FT_ROOT). sha10 = 파일이면 내용 sha256 · gitref 면 commit sha. 머리에는 출처 종류(`origin/main@` | `file:`)를 sha10 앞에 붙인다(r545 · 옛 꼴 `(<sha10> · …)` 도 읽는다).
원장: 행 수 ≠ 6 = ERROR rc1 · 파일·절 없음 = «상태 없음» + stderr WARN · 머리 `원장:<갱신>` · 24h 초과 = «상태 낡음».
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

from ft_goal_ledger import NO_STATE, default_spec, find_root, ledger_repo, ledger_spec, ledger_state, read_spec, table_rows

DEFAULT_NAME = "AUTONOMY-GOAL-A6-20261018.md"  # planner 팀 폴더 안(폴더는 ft_team_lib 가 푼다)
BUDGET = 1600
CELL = 24
HEAD = re.compile(r"^★골 표 A6 \((?:(?:[^()\s]+@)|(?:file:))?([0-9a-f]{10}) · [^)]*\)★$")  # r545: 출처 표지(`origin/main@`|`file:`) 붙은 새 꼴 + 표지 없는 옛 꼴 둘 다
TAIL = "★/골 표★"
COORD = re.compile(r"^골좌표:\s*(\d+)\s*[—-]\s*(.+?)\s*$")
TEAMS_SECTION = re.compile(r"^##\s+팀별 완성 진행")
TEAMS_TAIL = "★/팀별 완성 진행★"
TEAMS_NOW_CELLS = (24, 16, 8)  # «지금 하는 것» 칸 — 예산(1600B)에 들 때까지 줄인다 · 팀·끝선·착지 칸은 12자


class GoalError(RuntimeError):  # RuntimeError — 뉴스 원장 실행의 기존 except(RuntimeError) 가 «발행 0» 으로 받는다
    pass


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", s)).strip()


def _root() -> Path:
    return find_root(GoalError)


def _git(repo: Path, *a: str) -> str:
    done = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False)
    if done.returncode != 0:
        raise GoalError(f"ERROR 골 표 정본 git {a[0]} 실패: {done.stderr.strip()[:120]}")
    return done.stdout


def _git_ok(repo: Path, *a: str) -> bool:
    return subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False).returncode == 0


def _repo() -> Path:
    """gitref 읽기 리포 = FT_GOAL_REPO › 원장 리포(FT_LEDGER_REPO · LIVE_ROOT — r545: planner 파일이 사는 리포가 기본. 루트는 데이터 루트일 뿐 git 이 아닐 수 있다)."""
    return Path(os.environ.get("FT_GOAL_REPO") or ledger_repo(GoalError))


def _spec() -> str:
    return os.environ.get("FT_GOAL_A6_MD") or default_spec(GoalError, DEFAULT_NAME)


def load_canon() -> tuple[str, str, str]:
    """(본문, sha10, 출처 표지) — gitref = `origin/main@` · 파일 = `file:` · gitref 는 commit 으로 1회 확정(r545: 머리가 «어느 판에서 읽었나» 를 보여준다)."""
    spec = _spec()
    if spec.startswith("gitref:"):
        _, ref, rel = spec.split(":", 2)
        commit = _git(_repo(), "rev-parse", "--verify", ref).strip()
        return _git(_repo(), "show", f"{commit}:{rel}"), commit[:10], f"{ref}@"
    try:
        raw = Path(spec).read_bytes()
    except OSError as e:
        raise GoalError(f"ERROR 골 표 정본 읽기 실패 {spec}: {e.strerror}") from e
    return raw.decode("utf-8"), hashlib.sha256(raw).hexdigest()[:10], "file:"


def parse_rows(text: str) -> list[list[str]]:
    """정본 표 «## 골 → 팀 → 닫는 증거» 의 6행 → 각 행의 칸 3개 `|`-분리 (골·팀·증거)."""
    sect = re.split(r"^##\s+골\s*→\s*팀\s*→\s*닫는 증거\s*$", text, maxsplit=1, flags=re.M)
    rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in (sect[1].splitlines() if len(sect) > 1 else []) if ln.startswith("| ")]
    rows = [r for r in rows if not r[0].startswith("골(")]
    if len(rows) != 6 or any(len(r) != 3 or not all(r) for r in rows):
        raise GoalError(f"ERROR 골 표 정본 표가 6행(칸 3개)이 아니다: {len(rows)}행")
    return rows


def _ledger_show(spec: str) -> str | None:
    """`gitref:<ref>:<경로>` 원장 → 그 ref 의 commit 으로 1회 확정해 읽는다 · 그 ref 에 경로가 없으면 None(«상태 없음» WARN 경로 · r545)."""
    _, ref, rel = spec.split(":", 2)
    commit = _git(_repo(), "rev-parse", "--verify", ref).strip()
    return _git(_repo(), "show", f"{commit}:{rel}") if _git_ok(_repo(), "cat-file", "-e", f"{commit}:{rel}") else None


def _cut(s: str, keep_all: bool = False) -> str:
    s = _norm(s).replace("|", "/")
    return s if keep_all or len(s) <= CELL else s[:CELL] + "…"


def render() -> str:
    text, sha, src = load_canon()
    rows = parse_rows(text)
    head, states = ledger_state(_ledger_show, GoalError)
    body = [f"| {_cut(g, True)} | {_cut(t)} | {_cut(states.get(i, NO_STATE))} | {_cut(e)} |" for i, (g, t, e) in enumerate(rows, 1)]
    out = "\n".join([f"★골 표 A6 ({src}{sha} · {head})★", "| 골 | 팀 | 지금 상태 | 닫는 증거 |", "|---|---|---|---|", *body, TAIL])
    if len(out.encode("utf-8")) > BUDGET:
        raise GoalError(f"ERROR 골 표 예산 초과 {len(out.encode('utf-8'))}B > {BUDGET}B (골 원문 칸은 절단하지 않는다)")
    return out + "\n"


def render_teams() -> str:
    """팀별 완성 진행 블록(R458) — 원장 = 골 표 상태 칸과 같은 파일(ledger_spec) · 표 없음/예산 초과 = "" + stderr WARN(raise 0)."""
    spec = ledger_spec(GoalError)
    text = read_spec(spec, _ledger_show)
    rows = table_rows(text, GoalError, TEAMS_SECTION) if text is not None else None
    if not rows:
        print(f"WARN 팀별 완성 진행 표 없음: {spec}", file=sys.stderr)
        return ""
    sha = _git(_repo(), "rev-parse", "--verify", spec.split(":", 2)[1]).strip()[:10] if spec.startswith("gitref:") else hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]
    out = ""
    for width in TEAMS_NOW_CELLS:
        body = [f"| {_clip(r[0], 12)} | {_clip(_at(r, 1), 12)} | {_clip(_at(r, 2), 12)} | {_clip(_at(r, 3), width)} |" for r in rows]
        out = "\n".join([f"★팀별 완성 진행 ({sha})★", "| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |", "|---|---|---|---|", *body, TEAMS_TAIL])
        if len(out.encode("utf-8")) <= BUDGET:
            return out + "\n"
    print(f"WARN 팀별 완성 진행 예산 초과 {len(out.encode('utf-8'))}B > {BUDGET}B ({len(rows)}행) — 블록 없이 발행", file=sys.stderr)
    return ""


def _at(row: list[str], i: int) -> str:
    return row[i] if i < len(row) and row[i] else "-"


def _clip(s: str, n: int) -> str:
    s = _norm(s).replace("|", "/")
    return s if len(s) <= n else s[:n] + "…"


def _canon_for(sha: str) -> list[list[str]]:
    text, cur, _ = load_canon()
    if cur == sha:
        return parse_rows(text)
    spec = _spec()
    if spec.startswith("gitref:"):
        return parse_rows(_git(_repo(), "show", f"{sha}:{spec.split(':', 2)[2]}"))
    raise GoalError(f"마커 sha10 {sha} 이 정본({cur})과 다르다")


def check(body: str, block_only: bool = False) -> tuple[int, str]:
    lines = body.splitlines()
    heads = [i for i, ln in enumerate(lines) if HEAD.match(ln.strip())]
    tails = [i for i, ln in enumerate(lines) if ln.strip() == TAIL]
    if not heads or not tails or tails[-1] < heads[0]:
        return 3, "REJECT 골 없음 — 골 표 블록(★골 표 A6 … ★/골 표★ 마커 2줄)이 없다 · bash <루트>/.fable-team/bin/ft-goal-table.sh 출력을 머리 줄 아래에"
    block = lines[heads[0]:tails[-1] + 1]
    m0 = HEAD.match(block[0].strip())
    sha = m0[1] if m0 else ""
    try:
        canon = _canon_for(sha)
    except GoalError as e:
        return 3, f"REJECT 골 없음 — 정본 대조 실패: {e}"
    got = [[_norm(c) for c in ln.strip().strip("|").split("|")] for ln in block if ln.startswith("| ") and not ln.startswith("| 골 |")]
    if len(got) != 6 or any(g[0] != _norm(c[0]) for g, c in zip(got, canon)):
        return 3, "REJECT 골 없음 — 블록의 6행이 정본(마커 sha10) 골 칸과 다르다"
    if block_only:
        return 0, "GOAL-OK block-only"
    for ln in lines:
        if m := COORD.match(ln.strip()):
            n, want = int(m[1]), _norm(canon[int(m[1]) - 1][0]) if 1 <= int(m[1]) <= 6 else ""
            if want and _norm(m[2]) == want[:12].rstrip():
                return 0, f"GOAL-OK n={n}"
            return 3, f"REJECT 골 없음 — 골좌표 번호와 골 원문이 안 맞는다(번호 1~6 · 원문 앞 {min(12, len(want))}자 복붙): {ln.strip()[:40]}"
    return 3, "REJECT 골 없음 — `골좌표: <1~6> — <골 원문 앞 12자>` 줄이 없다"


def main(argv: list[str]) -> int:
    try:
        if argv[:1] == ["check"]:
            args = [a for a in argv[1:] if a != "--block-only"]
            src = args[0] if args else "-"
            rc, msg = check(sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8"), "--block-only" in argv)
            print(msg)
            return rc
        sys.stdout.write(render_teams() if argv[:1] == ["teams"] else render())
        return 0
    except GoalError as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
