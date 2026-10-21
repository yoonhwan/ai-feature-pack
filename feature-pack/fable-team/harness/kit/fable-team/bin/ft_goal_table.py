"""ft_goal_table — 자율 골 표(A6) 렌더 + 판정기 하나 (R362 · 쓰는 쪽 ft-goal-table.sh · 뉴스·매거진·쪽지 가드가 같은 함수를 부른다).

render  : 정본 표(골 → 팀 → 닫는 증거 6행) + planner 원장 `## 메인 골 6줄` 표(행 순번 결속 · ft_goal_ledger) → 마커 2줄(`★골 표 A6 (<sha10> · 상태 …)★` … `★/골 표★`) 사이 표 1개(≤1600B).
          골 원문 칸은 절단 0 · 팀·증거·상태 칸만 24자 + «…» · 넘치면 `ERROR 골 표 예산 초과` rc1 · 정본 없음/6행 아님 = `ERROR 골 표 정본 …` rc1.
check   : 본문에 ⓐ마커 블록(6행 = 마커 sha10 의 정본 골 칸과 일치) ⓑ`골좌표: <1~6> — <그 행 골 원문 앞 min(12,len)자>` 가 있으면 `GOAL-OK n=<번호>` rc0 · 아니면 `REJECT 골 없음 — …` rc3.
          r600: gitref 정본이면 마커 sha 신선도도 본다 — 지금 ref 첫 부모 줄기에서 STALE_FP_MAX(12) 넘게 뒤 = `REJECT 골 표 낡음 — …` rc3 · 줄기에 없음 = rc3 · git 실패 = `REJECT 골 표 신선도 확인 실패` rc3(fail-closed · 파일 정본은 검사 생략).
          `--block-only` = ⓑ 생략(다골 글: 뉴스·매거진).
teams   : 원장 `## 팀별 완성 진행` 첫 표(팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것) → 마커 2줄(`★팀별 완성 진행 (<원장 sha10>)★` … `★/팀별 완성 진행★`) 사이 표(≤1600B · R458).
          표 없음·예산 초과 = 빈 출력 + stderr WARN rc0 — 거절 게이트 0(뉴스·매거진을 멈추지 않는다 · check 는 골 표만).
procs   : 원장 «메인 골 6줄» 만 읽어 안 보이던 오늘 등록 표준절차 골(r644) — planner 팀 폴더(ref 트리) 의 `GOAL-*-<8자리 날짜>.md` 마다 1줄(골 이름 = 파일 머리 `# 골 — …` · 담당 = 진행표 «담당» 칸 → 골 파일 `담당:` 줄 → `—`) · «지금 단계» = 원장 `## 표준절차 골 진행표` 의 «골 파일» 칸이 그 파일인 행(없으면 «진행표 행 없음» + stderr WARN) → 마커 2줄(`★표준절차 골 (<원장 sha10>)★` … `★/표준절차 골★`).
          «지금 단계» 칸이 `완료` 로 시작하고 그 행에 저장소에 실재하는 sha10 이 있으면 그 골은 목록에서 빼 «완성 N: 이름들» 1줄로 위에 묶는다(sha 없음 = 완성 아님 + WARN). 행 `git blame` 시각이 `FT_GOAL_PROC_STALE_H`(24)시간을 넘으면 그 줄 끝 `⚠ N시간 정지` + 블록 끝 `정지 골 N: …` 1줄. 시계 = `FT_NOW`("YYYY-MM-DD HH:MM").
          예산 1600B 넘으면 «지금 단계» 칸부터 줄임(teams 와 같은 꼴) · 골 파일 0개 = `표준절차 골 0` 1줄 · 원장·폴더 못 읽음 = `ERROR` rc1(조용히 빈 블록 0) — 소비처는 실패를 WARN + 빈 글로 받는다(뉴스·매거진을 멈추지 않는다).
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
from datetime import datetime
from pathlib import Path

from ft_goal_ledger import NO_STATE, default_spec, find_root, ledger_repo, ledger_spec, ledger_state, planner_ref, read_spec, table_rows, table_with_header

DEFAULT_NAME = "AUTONOMY-GOAL-A6-20261018.md"  # planner 팀 폴더 안(폴더는 ft_team_lib 가 푼다)
BUDGET = 1600
CELL = 24
HEAD = re.compile(r"^★골 표 A6 \((?:(?:[^()\s]+@)|(?:file:))?([0-9a-f]{10}) · [^)]*\)★$")  # r545: 출처 표지(`origin/main@`|`file:`) 붙은 새 꼴 + 표지 없는 옛 꼴 둘 다
TAIL = "★/골 표★"
COORD = re.compile(r"^골좌표:\s*(\d+)\s*[—-]\s*(.+?)\s*$")
STALE_FP_MAX = 12  # r600: 마커 판이 지금 ref 첫 부모 줄기에서 이만큼(약 2시간 · 시간당 약 6커밋) 넘게 뒤면 «골 표 낡음»
TEAMS_SECTION = re.compile(r"^##\s+팀별 완성 진행")
TEAMS_TAIL = "★/팀별 완성 진행★"
TEAMS_NOW_CELLS = (24, 16, 8)  # «지금 하는 것» 칸 — 예산(1600B)에 들 때까지 줄인다 · 팀·끝선·착지 칸은 12자
PROCS_SECTION = re.compile(r"^##\s+표준절차 골 진행표")  # r644: 원장의 표준절차 골 진행표(골 | 골 파일 | 지금 단계 | 다음 · 담당 열은 있을 때만)
PROCS_TAIL = "★/표준절차 골★"
PROCS_NAME_CELLS = (40, 24, 12)  # «지금 단계» 칸 — 예산(1600B)에 들 때까지 줄인다(teams 와 같은 꼴)
PROCS_FILE = re.compile(r"^GOAL-.+-[0-9]{8}\.md$")  # 날짜 붙은 골 파일만(AUTONOMY-GOAL-A6·GOAL-planner.md·날짜 없는 파일 제외)
PROCS_TITLE = re.compile(r"^#\s*골\s*[—–-]\s*(.+?)\s*$")
PROCS_OWNER = re.compile(r"^[>\s]*담당\s*[:：]\s*(\S.*)$")
SHORT_SHA = re.compile(r"(?<![0-9a-f])[0-9a-f]{10}(?![0-9a-f])")
PROCS_STALE_H = 24


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


def _procs_now() -> datetime:
    v = os.environ.get("FT_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now()


def _stale_h() -> float:
    try:
        return float(os.environ.get("FT_GOAL_PROC_STALE_H") or PROCS_STALE_H)
    except ValueError:
        return PROCS_STALE_H


def _goal_files(ref: str, folder: str) -> list[str]:
    """planner 팀 폴더(ref 트리) 의 날짜 붙은 골 파일 이름만 — 정렬(이름) 해 돌려준다."""
    out = _git(_repo(), "ls-tree", "--name-only", ref, "--", folder.rstrip("/") + "/")
    names = [p.rsplit("/", 1)[-1] for p in out.split()]
    return sorted(n for n in names if PROCS_FILE.match(n))


def _goal_head(file: str, ref: str, folder: str) -> str:
    """골 이름 = 파일 머리 `# 골 — <이름>` · 못 읽으면 파일 이름(확장자 뺀 것)."""
    try:
        text = _git(_repo(), "show", f"{ref}:{folder}/{file}")
    except GoalError as e:
        print(f"WARN 표준절차 골 파일 못 읽음({file}): {e}", file=sys.stderr)
        return file[:-3]
    return next((m[1] for ln in text.splitlines() if (m := PROCS_TITLE.match(ln.strip()))), file[:-3])


def _goal_owner(file: str, ref: str, folder: str) -> str:
    """골 파일 `담당:` 줄 → 그 값 · 없으면 빈 글(진행표 «담당» 칸도 없을 때 `—` 로 채운다)."""
    try:
        text = _git(_repo(), "show", f"{ref}:{folder}/{file}")
    except GoalError:
        return ""
    return next((m[1] for ln in text.splitlines() if (m := PROCS_OWNER.match(ln))), "")


def _row_sha(row: list[str]) -> bool:
    """그 행에 저장소에 실재하는 sha10 이 있나(닫는 증거) — git 이 죽으면 «없음»(완성 판정을 억지로 만들지 않는다)."""
    for cell in row:
        for sha in SHORT_SHA.findall(cell):
            if _git_ok(_repo(), "cat-file", "-e", f"{sha}^{{commit}}"):
                return True
    return False


def _row_age(spec: str, lineno: int) -> float | None:
    """그 행이 마지막으로 바뀐 지 몇 시간인가(git blame) — 못 재면 None(정지 판정 안 함).
    gitref = `<ref>:<경로>` 그 ref 로 · 파일 출처 = 그 절대경로(리포 안일 때만 잰다)."""
    ref, path = (spec.split(":", 2)[1], spec.split(":", 2)[2]) if spec.startswith("gitref:") else ("HEAD", spec)
    try:
        blamed = _git(_repo(), "blame", "--porcelain", "-L", f"{lineno},{lineno}", ref, "--", path).split()[0]
        stamp = float(_git(_repo(), "show", "-s", "--format=%ct", blamed).strip())
    except (GoalError, ValueError, IndexError):
        return None
    return (_procs_now().timestamp() - stamp) / 3600


def _procs_lines(rows: list[tuple[int, list[str]]], head: list[str]) -> list[dict]:
    """진행표 데이터 행 → 골 파일마다 1줄 재료(이름 · 담당 · 단계 · 완성 · 정지)."""
    ref, folder = planner_ref(GoalError)
    col = lambda *keys: next((i for i, h in enumerate(head) if all(k in h for k in keys)), None)  # noqa: E731
    file_col, stage_col, owner_col = col("골 파일"), col("지금 단계"), col("담당")
    out = []
    for file in _goal_files(ref, folder):
        row = next((r for _ln, r in rows if file_col is not None and file_col < len(r) and file in r[file_col]), None)
        lineno = next((ln for ln, r in rows if r is row), 0)
        stage = row[stage_col] if row and stage_col is not None and stage_col < len(row) else ""
        owner = (row[owner_col] if row and owner_col is not None and owner_col < len(row) else "") or _goal_owner(file, ref, folder) or "—"
        if row is None:
            print(f"WARN 표준절차 골 진행표 행 없음: {file}", file=sys.stderr)
            stage = "진행표 행 없음"
        done = bool(row) and _norm(stage).startswith("완료")
        if done and not _row_sha(row or []):
            print(f"WARN 표준절차 골 완료 표기인데 저장소에 닫는 증거 sha 가 없다: {file}", file=sys.stderr)
            done = False
        age = _row_age(ledger_spec(GoalError), lineno) if row is not None and lineno else None
        out.append({"name": _goal_head(file, ref, folder), "owner": _norm(owner), "stage": _norm(stage),
                    "done": done, "stale": 0 if age is None else int(age // 1), "late": age is not None and age > _stale_h()})
    return out


def render_procs() -> str:
    """표준절차 골 블록(r644) — planner 팀 폴더의 골 파일마다 1줄 + 완성 묶음 + 정지 경보. 원장·폴더 못 읽음 = ERROR rc1."""
    spec = ledger_spec(GoalError)
    text = read_spec(spec, _ledger_show)
    if text is None:
        raise GoalError(f"ERROR 표준절차 골 원장 못 읽음: {spec}")
    head, rows = table_with_header(text, GoalError, PROCS_SECTION)
    if head is None:
        raise GoalError(f"ERROR 표준절차 골 진행표 절이 없다: {spec} (`## 표준절차 골 진행표`)")
    sha = _git(_repo(), "rev-parse", "--verify", spec.split(":", 2)[1]).strip()[:10] if spec.startswith("gitref:") else hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]
    items = _procs_lines(rows, head)
    if not items:
        return "\n".join([f"★표준절차 골 ({sha})★", "표준절차 골 0", PROCS_TAIL]) + "\n"
    done = [i for i in items if i["done"]]
    late = [i for i in items if i["late"] and not i["done"]]
    for width in PROCS_NAME_CELLS:
        body = [f"- {i['name']} · {i['owner']} · {_clip(i['stage'], width)}" + (f" ⚠ {i['stale']}시간 정지" if i["late"] else "") for i in items if not i["done"]]
        out = "\n".join([f"★표준절차 골 ({sha})★", *([f"완성 {len(done)}: " + ", ".join(i["name"] for i in done)] if done else []), *body,
                         *([f"정지 골 {len(late)}: " + ", ".join(i["name"] for i in late)] if late else []), PROCS_TAIL])
        if len(out.encode("utf-8")) <= BUDGET:
            return out + "\n"
    print(f"WARN 표준절차 골 예산 초과 {len(out.encode('utf-8'))}B > {BUDGET}B ({len(items)}줄) — 블록 없이 발행", file=sys.stderr)
    return ""


def _canon_for(sha: str) -> list[list[str]]:
    text, cur, _ = load_canon()
    if cur == sha:
        return parse_rows(text)
    spec = _spec()
    if spec.startswith("gitref:"):
        return parse_rows(_git(_repo(), "show", f"{sha}:{spec.split(':', 2)[2]}"))
    raise GoalError(f"마커 sha10 {sha} 이 정본({cur})과 다르다")


def _stale_reason(sha: str) -> str:
    """r600: 마커 sha 신선도 — 지금 ref 첫 부모 줄기에서 STALE_FP_MAX 넘게 뒤거나 줄기에 없으면 REJECT 문구(파일 정본 = 검사 생략 · git 실패 = fail-closed)."""
    spec = _spec()
    if not spec.startswith("gitref:"):
        return ""
    ref = spec.split(":", 2)[1]
    try:
        tip = _git(_repo(), "rev-parse", "--verify", ref).strip()
        chain = _git(_repo(), "rev-list", "--first-parent", ref).split()
    except GoalError as e:
        return f"REJECT 골 표 신선도 확인 실패 — 마커 {sha} 신선도: {e}"
    dist = next((i for i, c in enumerate(chain) if c.startswith(sha)), None)
    if dist is None:
        return f"REJECT 골 표 낡음 — 마커 sha 가 {ref} 첫 부모 줄기에 없다"
    if dist > STALE_FP_MAX:
        return f"REJECT 골 표 낡음 — 마커 {sha} 은 지금 {ref}({tip[:10]})보다 첫 부모 {dist}커밋 앞(상한 {STALE_FP_MAX}) · ft-goal-table.sh 를 다시 돌려 붙인다"
    return ""


def check(body: str, block_only: bool = False) -> tuple[int, str]:
    lines = body.splitlines()
    heads = [i for i, ln in enumerate(lines) if HEAD.match(ln.strip())]
    tails = [i for i, ln in enumerate(lines) if ln.strip() == TAIL]
    if not heads or not tails or tails[-1] < heads[0]:
        return 3, "REJECT 골 없음 — 골 표 블록(★골 표 A6 … ★/골 표★ 마커 2줄)이 없다 · bash <루트>/.fable-team/bin/ft-goal-table.sh 출력을 머리 줄 아래에"
    block = lines[heads[0]:tails[-1] + 1]
    m0 = HEAD.match(block[0].strip())
    sha = m0[1] if m0 else ""
    stale = _stale_reason(sha) if sha else ""
    if stale:
        return 3, stale
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
        sys.stdout.write({"teams": render_teams, "procs": render_procs}.get(argv[0] if argv else "", render)())
        return 0
    except GoalError as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
