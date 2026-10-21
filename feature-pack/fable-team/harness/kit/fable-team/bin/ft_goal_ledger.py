r"""ft_goal_ledger — 골 표 «지금 상태» N칸의 출처 = planner 원장 `## 메인 골 N줄` 표 (R371 · ft_goal_table.render 가 부른다 · r668: N = 정본 표 행 수).

루트 = env FT_ROOT(그 안에 .fable-team/LIVE_BIN 필수) · 없으면 cwd 의 git 공용 루트(.fable-team/LIVE_BIN 실재) · 옛 설치 꼴이면 이 파일 위치 조상 중 `.fable-team/LIVE_BIN` 이 있는 첫 폴더 · LIVE_ROOT = `<루트>/.fable-team/LIVE_ROOT` 1행(절대경로 · 실재 폴더 · R382: 코드 위치 LIVE_BIN/../.. 유도 폐지 — 하네스 코드가 팩으로 가도 데이터 루트가 안 틀어진다) (정본·원장·뉴스 셋이 이 함수 하나).
원장 = env FT_GOAL_A6_LEDGER(파일 경로 | `gitref:<ref>:<경로>`) 우선 · 없으면 ★기본 = `gitref:<FT_TEAMS_REF·origin/main>:<planner 팀 폴더>/PLAN-oppa-ledger.md`(r545 — 공용 체크아웃(LIVE_ROOT)의 디스크 파일이 아니라 그 ref 에 올라간 판 · 폴더도 ref 트리에서 푼다 · 체크아웃이 main 에서 뒤처져도 안 멈춘다)★. LIVE_BIN 없음/무효 = ERROR rc1(옛 v6 고정 경로 후퇴 0). 절 `## 메인 골 …줄`(숫자 없는 꼴·다른 숫자 꼴도 읽는다 · r668 · ★끝 경계: 뒤에는 줄 끝·«N줄»·« —» 만★) 의 첫 표 «데이터 행 N개» 를 행 순번(1~N)으로 정본 골에 묶는다(원장 골 글자는 정본과 달라 글자 대조 0) · 2열 = 지금 상태.
★N = 정본 표 행 수★(1 ≤ N ≤ FT_GOAL_MAX 기본 12 · `canon_count` — r668: 골 개수를 코드에 박지 않는다).
셀 = `\|` 를 글자 `|` 로 복원해 분리 · 열 수가 머리 줄과 다르면 ERROR(조용한 절단 0) · ★구분선(`---`)만 빼고 빈 칸 행은 ERROR★(r668 H1 — 빈 칸을 구분선처럼 빼면 행이 조용히 줄어든다) · 행 수 ≠ N = ERROR rc1 · 파일·절 없음 = «상태 없음» + stderr WARN 1줄 ·
머리 `원장:<MM-DD HH:mm>` · 마지막 갱신 24h 초과 또는 갱신 시각 없음 = «· 상태 낡음»(파일 mtime 으로 되돌아가지 않는다).
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable

from ft_team_lib import TeamPathError, team_rows_ref

NO_STATE = "상태 없음"
SECTION = re.compile(r"^##\s+메인 골(?:\s*\d+\s*줄)?\s*(?:$|—)")  # r668: «메인 골 6줄»·«메인 골 5줄»·«메인 골»(숫자 없는 꼴) 모두 — 옛 원장 호환. ★끝 경계(r668 H3)★: 뒤에는 줄 끝·«N줄»·« —» 만 («## 메인 골 참고» 는 안 잡힌다)
STAMP = re.compile(r"마지막 갱신:\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}):(\d[\dx])")
STALE_AFTER = timedelta(hours=24)
GOAL_MAX = 12  # r668 — 골 수 상한(env FT_GOAL_MAX 로 바꾼다 · 0 이하·글자 = 기본값)


def _no_live_bin(file: Path, value: str = "") -> str:
    return (f"ERROR 골 표 기본 출처: {file.name} 이 없거나 무효 {file} = {value!r} (절대경로 · 실재 폴더 필요 — ft-root-bin-shim.sh 가 설치 때 만든다 · env FT_GOAL_A6_MD·FT_GOAL_A6_LEDGER 로 직접 지정 가능)")


def find_root(error: type[Exception]) -> Path:
    """루트 = ①FT_ROOT(LIVE_BIN 필수) ②cwd 의 git 공용 루트(`git rev-parse --git-common-dir` 의 부모)에 `.fable-team/LIVE_BIN` 실재
    ③옛 설치 꼴(이 파일이 `*/.fable-team/bin`)일 때만 파일 위치 조상 중 `.fable-team/LIVE_BIN` 이 있는 첫 폴더 ④error(사유에 경로) — r385 r3:
    설치본(`~/.claude/fable-team/live/<버전>/bin` · git 밖)의 조상에는 LIVE_BIN 이 없다."""
    if env := os.environ.get("FT_ROOT"):
        file = Path(env) / ".fable-team" / "LIVE_BIN"
        if not file.is_file():
            raise error(_no_live_bin(file))
        return Path(env)
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=7).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        common = ""
    if common and (Path(common).parent / ".fable-team" / "LIVE_BIN").is_file():
        return Path(common).parent
    start = Path(__file__).resolve()
    if start.parent.name == "bin" and start.parent.parent.name == ".fable-team":
        for d in start.parents:
            if (d / ".fable-team" / "LIVE_BIN").is_file():
                return d
    raise error(_no_live_bin(Path.cwd() / "(cwd git 공용 루트 · 옛 설치 꼴 조상 탐색 실패) .fable-team" / "LIVE_BIN"))


def live_root(error: type[Exception], root: Path | None = None) -> Path:
    """LIVE_ROOT = 루트의 `.fable-team/LIVE_ROOT` 1행(절대경로·실재 폴더) — 못 풀면 error(LIVE_BIN 유도·고정 경로·옛 원장으로 되돌아가지 않는다)."""
    file = (root or find_root(error)) / ".fable-team" / "LIVE_ROOT"
    try:
        value = file.read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, IndexError):
        value = ""
    if not value.startswith("/") or not Path(value).is_dir():
        raise error(_no_live_bin(file, value))
    return Path(value)


def ledger_repo(error: type[Exception]) -> Path:
    """원장 리포 = env FT_LEDGER_REPO · 없으면 LIVE_ROOT(r545: 폴더·본문 둘 다 이 리포의 ref 에서 읽는다)."""
    return Path(os.environ["FT_LEDGER_REPO"]) if os.environ.get("FT_LEDGER_REPO") else live_root(error)


def _ref_has(root: Path, ref: str, rel: str) -> bool:
    """`<ref>:<rel>` 이 그 ref 트리에 있나 — 디스크 실재 여부는 안 본다(r545)."""
    done = subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{ref}:{rel.rstrip('/')}"],
                          capture_output=True, text=True, timeout=7)
    return done.returncode == 0


def planner_rel_in_ref(error: type[Exception], ref: str, root: Path) -> str:
    """planner 팀 폴더 «ref 안의» 상대 경로 — 명단 = `ref:design/TEAMS.md` · 후보 = 명단 꼴 + 쌍둥이(ft_team_lib._cands_ref 와 같은 규칙) · ref 트리에 있는 후보 정확히 1개.
    r545: 체크아웃(LIVE_ROOT) 디스크에 그 폴더가 있나로 고르지 않는다 — 뒤처진 체크아웃에서 폴더가 사라져도 출처가 안 흔들린다."""
    try:
        rows = team_rows_ref(ref, root)
    except TeamPathError as e:
        raise error(str(e)) from e
    if "planner" not in rows:
        raise error(f"ERROR planner 은 팀 명단({ref}:design/TEAMS.md)에 없다: {root}")
    raw = rows["planner"]
    cands = [raw] if raw.startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")) else [
        raw, raw.replace("design/teams/", "design/", 1) if raw.startswith("design/teams/") else raw.replace("design/", "design/teams/", 1)]
    hits = [c.rstrip("/") for c in cands if _ref_has(root, ref, c)]
    if len(hits) != 1:
        raise error(f"ERROR planner 폴더가 {ref} 에 {len(hits)}개 — 정확히 1개여야 한다(명단 {ref}:design/TEAMS.md · 후보 {' '.join(c.rstrip('/') for c in cands)} · 리포 {root})")
    return hits[0]


def planner_ref(error: type[Exception]) -> tuple[str, str]:
    """(ref, planner 폴더 상대 경로) — ref = env FT_TEAMS_REF(기본 origin/main) · 리포 = ledger_repo."""
    root = ledger_repo(error)
    ref = os.environ.get("FT_TEAMS_REF") or "origin/main"
    return ref, planner_rel_in_ref(error, ref, root)


def default_spec(error: type[Exception], name: str) -> str:
    """기본 출처 = `gitref:<ref>:<planner 폴더>/<name>`(r545 · 체크아웃 파일 출처 아님). 골 정본·원장이 같은 함수 하나를 쓴다."""
    ref, rel = planner_ref(error)
    return f"gitref:{ref}:{rel}/{name}"


def ledger_spec(error: type[Exception]) -> str:
    """원장 = FT_GOAL_A6_LEDGER › 원장 정본 한 값(FT_LEDGER_REPO + FT_LEDGER_PATH · 뉴스와 같은 값 · R458) › `gitref:<ref>:<planner 폴더>/PLAN-oppa-ledger.md`(r545)."""
    if os.environ.get("FT_GOAL_A6_LEDGER"):
        return os.environ["FT_GOAL_A6_LEDGER"]
    if os.environ.get("FT_LEDGER_PATH"):
        return str(ledger_repo(error) / os.environ["FT_LEDGER_PATH"])
    return default_spec(error, "PLAN-oppa-ledger.md")


def read_spec(spec: str, git_show: Callable[[str], str | None]) -> str | None:
    """출처 본문 — 없으면 None(파일 없음 = `상태 없음` WARN 경로 그대로 · r545: gitref 에 그 경로가 없을 때도 같은 자리로 온다).
    git_show 는 «그 ref 에 경로가 없으면 None» 을 돌려준다(부르는 쪽 몫) — git 자체 실패는 예외 그대로(fail-closed)."""
    if spec.startswith("gitref:"):
        return git_show(spec)
    try:
        return Path(spec).read_text(encoding="utf-8")
    except OSError:
        return None


def goal_max() -> int:
    """골 수 상한 = env FT_GOAL_MAX(기본 12) — 못 읽는 값은 기본값(조용한 0 행 0)."""
    try:
        value = int(os.environ.get("FT_GOAL_MAX") or GOAL_MAX)
    except ValueError:
        return GOAL_MAX
    return value if value > 0 else GOAL_MAX


def canon_count(error: type[Exception]) -> int:
    """정본 표 행 수 N — ft_goal_table 을 «부를 때» import 한다(그쪽이 이 모듈을 먼저 import · 순환 0 · r668).
    정본을 못 읽으면 ft_goal_table 의 GoalError(= error 와 같은 부류)가 그대로 올라간다(조용한 통과 0)."""
    import ft_goal_table as gt  # noqa: PLC0415 — 순환 import 회피(이 모듈이 아래 층)
    return len(gt.parse_rows(gt.load_canon()[0]))


def _cells(line: str) -> list[str]:
    r"""표 한 줄 → 칸 — 칸 안의 `\|` 는 글자 `|` 로 복원(단순 split 0)."""
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", body)]


def table_with_header(text: str, error: type[Exception], section: re.Pattern[str] = SECTION) -> tuple[list[str], list[tuple[int, list[str]]]] | tuple[None, None]:
    """절(기본 `## 메인 골 …줄`(r668 — 숫자 없는/다른 숫자 꼴도 읽는다 · 끝 경계 포함) · R458 `## 팀별 완성 진행` · r644 `## 표준절차 골 진행표`) 아래 첫 표 = (머리 줄 칸, [(줄번호, 데이터 칸)]) — 절이 없으면 (None, None) · 열 수가 머리 줄과 다른 행 = error.
    r668 H1: 구분선(`---` 만 있는 줄)만 뺀다 — 기본 절(골 표 상태)에서 빈 칸이 있는 데이터 행은 error(구분선처럼 빠져 행이 조용히 줄어들지 않는다).
    줄번호 = 1부터 센 파일 줄(r644: git blame 으로 «그 행 마지막 변경» 을 잰다)."""
    rows: list[tuple[int, list[str]]] = []
    head: list[str] = []
    inside = False
    width = 0
    for lineno, ln in enumerate(text.splitlines(), 1):
        if section.match(ln):
            inside = True
        elif inside and ln.startswith("## "):
            break
        elif inside and ln.startswith("|"):
            cells = _cells(ln)
            if not width:
                width, head = len(cells), cells  # 첫 표 줄 = 머리 줄 → 열 수 기준
            elif len(cells) != width:
                raise error(f"ERROR 골 표 원장 열 수 {len(cells)}≠{width} (표 {len(rows) + 1}번째 데이터 줄 · `|` 글자는 `\\|` 로 적는다): {ln.strip()[:60]}")
            elif all(set(c) <= set("-: ") for c in cells):
                continue  # 구분선(---)만 뺀다 — r668 H1: 첫 칸만 빈 데이터 행을 구분선처럼 빼지 않는다
            elif not all(cells) and section is SECTION:
                raise error(f"ERROR 골 표 원장 빈 칸 (표 {len(rows) + 1}번째 데이터 줄 · 빈 칸을 두면 행이 조용히 줄어든다): {ln.strip()[:60]}")
            else:
                rows.append((lineno, cells))
        elif inside and width:
            break
    return (head, rows) if inside else (None, None)


def table_rows(text: str, error: type[Exception], section: re.Pattern[str] = SECTION) -> list[list[str]] | None:
    """절 아래 첫 표의 데이터 행(칸 분리) — 절이 없으면 None · 열 수가 머리 줄과 다른 행 = error."""
    head, rows = table_with_header(text, error, section)
    return [cells for _line, cells in rows] if head is not None else None


def _stale(text: str, now: datetime) -> tuple[str, bool]:
    """(`MM-DD HH:mm` 표기 그대로 · 24h 초과 여부) — 분이 `0x` 처럼 흐려도 앞 숫자 × 10 분으로 잰다."""
    m = STAMP.search(text)
    if not m:
        return "갱신 시각 없음", True
    minute = int(m[3]) if m[3].isdigit() else int(m[3][0]) * 10
    stamp = datetime.strptime(f"{m[1]} {m[2]}", "%Y-%m-%d %H") + timedelta(minutes=minute)
    return f"{m[1][5:]} {m[2]}:{m[3]}", now - stamp > STALE_AFTER


def ledger_state(git_show: Callable[[str], str | None], error: type[Exception], now: datetime | None = None, n: int | None = None) -> tuple[str, dict[int, str]]:
    """(머리 글자, {행번호: 지금 상태}) — error = 호출자의 GoalError · n = 골 수 N(정본 표 행 수 · 없으면 canon_count 로 잰다)."""
    spec = ledger_spec(error)
    text = read_spec(spec, git_show)
    rows = table_rows(text, error) if text is not None else None
    n = canon_count(error) if n is None else n
    if rows is None:
        print(f"WARN 골 표 원장 상태 칸 없음({'파일' if text is None else '절'}): {spec} — «{NO_STATE}» {n}칸으로 발행", file=sys.stderr)
        return NO_STATE, {}
    if len(rows) != n:
        raise error(f"ERROR 골 표 원장 행 수 {len(rows)}≠{n} ({spec} 절 `## 메인 골 …줄` 첫 표 · N = 정본 표 행 수)")
    when, old = _stale(text or "", now or datetime.now())
    return f"원장:{when}{' · 상태 낡음' if old else ''}", {i: (r[1] or NO_STATE) for i, r in enumerate(rows, 1)}
