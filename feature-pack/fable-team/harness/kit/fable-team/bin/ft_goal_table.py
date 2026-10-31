"""ft_goal_table — 자율 골 표(A6) 렌더 + 판정기 하나 (R362 · 쓰는 쪽 ft-goal-table.sh · 뉴스·매거진·쪽지 가드가 같은 함수를 부른다).

render  : 정본 표(골 → 팀 → 닫는 증거 N행 · N = 정본 표 행 수 · 1~FT_GOAL_MAX 기본 12 · r668) + planner 원장 `## 메인 골 …줄` 표(행 순번 결속 · ft_goal_ledger) → 마커 2줄(`★골 표 A6 (<sha10> · 상태 …)★` … `★/골 표★`) 사이 표 1개(≤1600B).
          r714a: 머리 줄 끝 «재조정: ok=<run> <HH:MM> · 최근=<run>-<nn> OK|ERROR <사유>» 1칸 + 행마다 «재조정» 칸(회차 파일 `state/goal-readjust/rounds/*.json` 의 라벨 · ft_goal_readjust_state 가 읽는다 — 기록 없음 `모름(기록 없음)` · 행 식별(번호+골 전문 해시)이 다르면 `모름(판 다름)`).
          예산(1600B)이 넘치면 «재조정» 칸을 라벨 글자만으로 줄이고(·카드k··대응 모름··정본 바뀜 뗌), 그래도 넘치면 팀·상태·증거 칸 폭을 24→20→16→12→8자로 차례로 줄인다(r731 · 8자 r1210 · 골 원문 칸은 끝까지 절단 0), 그래도 넘치면 아래 «예산 초과» ERROR 그대로다.
          골 원문 칸은 절단 0 · 팀·증거·상태 칸만 24자 + «…» · 넘치면 `ERROR 골 표 예산 초과` rc1 · 정본 없음/N행 아님 = `ERROR 골 표 정본 …` rc1.
          r668: 정본 sha 가 바뀌고 **골 번호표(행 수·순서)가 바뀐** 첫 렌더에서 전 팀장(명부 `_master` 전부)에게 «골 번호 바뀜 · 새 번호표» 1통(표식 `<루트>/.fable-team/state/goal-numbering.tsv` — 같은 정본 sha 로는 1회 · 실패 = WARN 1줄 · 렌더는 계속).
          r668 H4: 표식 없는 첫 렌더에서도 정본이 6행(옛 고정)이 아니면 1통 · 읽기→송신→쓰기에 파일 잠금(동시 렌더 중복 0) · 깨진 명부 = WARN + 표식 전진 0 · 송신 1통 7초 상한.
check   : 본문에 ⓐ마커 블록(N행 = 마커 sha10 의 정본 골 칸과 일치) ⓑ`골좌표: <1~N> — <그 행 골 원문 앞 min(12,len)자>` 가 있으면 `GOAL-OK n=<번호>` rc0 · 아니면 `REJECT 골 없음 — …` rc3.
          r668: 거절 문구에 «새 번호표 N줄(번호 — 골 앞 12자)» 를 싣는다 — 번호가 바뀐 판을 만난 좌석이 그 자리에서 고친다.
          r668 H2: 옛 마커 sha10 을 허용하는 것은 «현재 정본과 번호표(행 수·각 행 골 앞 12자)가 같을 때» 뿐이다(6→5행 바뀜 직후 옛 6행 블록이 통과하던 구멍).
          r726: 번호표가 바뀐 판이면 «표식에 기록한 직전 정본 1판» 만, 번호표가 바뀐 시각 뒤 FT_GOAL_RENUMBER_GRACE_H(기본 24)시간 안에서 인정한다 — `GOAL-OK n=<번호> 옛 번호표(유예 <남은>시간 남음 · 새 번호표 …)` rc0 + stderr 로그 1줄(FT_SEAT). 유예 밖·두 판 이상 옛 판·표식 없음/손상 = 지금처럼 REJECT rc3(유예로 새지 않는다).
          r726 r2: 결속 키 = «번호표 지문»(마커 sha == 표식 직전 판 sha 비교는 거뒀다 — 마커 sha 는 렌더 순간의 main 커밋이라 한 커밋 앞 렌더가 유예 밖으로 떨어졌다) · 신선도 상한 = 마커가 첫 부모 줄기에 있고 dist(마커) <= dist(직전 판)+STALE_FP_MAX(12) · 줄기에 없음/git 실패/직전 판이 줄기에 없음 = 유예 0(REJECT).
          r726 r3(DA⑥ r1 처방 5): 표식 두 줄 형식을 «정확히» 본다(`<sha10>\t<지문12>` · `prev\t<sha10>\t<지문12>\t<유한 정수 epoch>`, 아니면 유예 0) · «직전 판» 을 `git show <rec[0]>:<정본>` 으로 다시 계산해 지문 대조 · 표식 첫 줄 지문 == 지금 정본 지문 · 경과는 `0 <= 경과 < 유예`(미래 시각 0) · env 유예는 `min(env,24)` 로 줄이기만(0 = 끄기 · NaN/Inf = 기본).
          r728: 번호 공지·표식 쓰기는 «기본 ref(FT_TEAMS_REF·origin/main) 의 gitref + 정본 꼴 이름(AUTONOMY-GOAL-A6-<8자리>.md)» 일 때만 — 시안·시험 렌더(FT_GOAL_A6_MD 에 파일 경로 · 다른 ref · 다른 이름을 주입)는 표만 그리고 공지·표식 0 + stderr `INFO 시안 렌더 — 번호 공지·표식 0 (정본 <spec>)` 1줄(시안 렌더가 표식을 옛 판으로 밀어 다음 진짜 렌더가 재공지하던 것).
          r600: gitref 정본이면 마커 sha 신선도도 본다 — 지금 ref 첫 부모 줄기에서 STALE_FP_MAX(12) 넘게 뒤 = `REJECT 골 표 낡음 — …` rc3 · 줄기에 없음 = rc3 · git 실패 = `REJECT 골 표 신선도 확인 실패` rc3(fail-closed · 파일 정본은 검사 생략).
          `--block-only` = ⓑ 생략(다골 글: 뉴스·매거진).
teams   : 원장 `## 팀별 완성 진행` 첫 표(팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것) → 마커 2줄(`★팀별 완성 진행 (<원장 sha10>)★` … `★/팀별 완성 진행★`) 사이 표(≤1600B · R458).
          표 없음·예산 초과 = 빈 출력 + stderr WARN rc0 — 거절 게이트 0(뉴스·매거진을 멈추지 않는다 · check 는 골 표만).
procs   : 원장 «메인 골 …줄» 만 읽어 안 보이던 오늘 등록 표준절차 골(r644) — planner 팀 폴더(ref 트리) 의 `GOAL-*-<8자리 날짜>.md` 마다 1줄(골 이름 = 파일 머리 `# 골 — …` · 담당 = 진행표 «담당» 칸 → 골 파일 `담당:` 줄 → `—`) · «지금 단계» = 원장 `## 표준절차 골 진행표` 의 «골 파일» 칸이 그 파일인 행(없으면 «진행표 행 없음» + stderr WARN) → 마커 2줄(`★표준절차 골 (<원장 sha10>)★` … `★/표준절차 골★`).
          «지금 단계» 칸이 `완료` 로 시작하고 그 행에 저장소에 실재하는 sha10 이 있으면 그 골은 목록에서 빼 «완성 N: 이름들» 1줄로 위에 묶는다(sha 없음 = 완성 아님 + WARN). 행 `git blame` 시각이 `FT_GOAL_PROC_STALE_H`(24)시간을 넘으면 그 줄 끝 `⚠ N시간 정지` + 블록 끝 `정지 골 N: …` 1줄. 시계 = `FT_NOW`("YYYY-MM-DD HH:MM").
          예산 1600B 넘으면 «지금 단계» 칸부터 줄임(teams 와 같은 꼴) · 골 파일 0개 = `표준절차 골 0` 1줄 · 원장·폴더 못 읽음 = `ERROR` rc1(조용히 빈 블록 0) — 소비처는 실패를 WARN + 빈 글로 받는다(뉴스·매거진을 멈추지 않는다).
정본 = env FT_GOAL_A6_MD(파일 경로 | `gitref:<ref>:<경로>` · 기본 = `gitref:<FT_TEAMS_REF·origin/main>:<planner 팀 폴더>/AUTONOMY-GOAL-A6-20261018.md` — r545: 체크아웃(LIVE_ROOT) 파일이 아니라 그 ref 에 올라간 판 · 폴더도 ref 트리에서 푼다) · 상태 = 원장 env FT_GOAL_A6_LEDGER(같은 두 형식 · 기본 같은 꼴) · 저장소 = FT_GOAL_REPO(기본 FT_LEDGER_REPO · FT_ROOT). sha10 = 파일이면 내용 sha256 · gitref 면 commit sha. 머리에는 출처 종류(`origin/main@` | `file:`)를 sha10 앞에 붙인다(r545 · 옛 꼴 `(<sha10> · …)` 도 읽는다).
원장: 행 수 ≠ N = ERROR rc1(N = 정본 표 행 수 · r668) · 파일·절 없음 = «상태 없음» + stderr WARN · 머리 `원장:<갱신>` · 24h 초과 = «상태 낡음».
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

from ft_goal_ledger import NO_STATE, default_spec, find_root, goal_max, ledger_repo, ledger_spec, ledger_state, planner_ref, read_spec, table_rows, table_with_header
from ft_goal_readjust_state import header as readjust_header
from ft_goal_readjust_state import read as readjust_read
from ft_goal_readjust_state import row_cell as readjust_cell

DEFAULT_NAME = "AUTONOMY-GOAL-A6-20261018.md"  # planner 팀 폴더 안(폴더는 ft_team_lib 가 푼다)
BUDGET = 1600
CELL = 24
GOAL_CELLS = (24, 20, 16, 12, 8)  # r731: 팀·상태·증거 칸 폭 — 예산(1600B)에 들 때까지 차례로 줄인다(골 원문 칸은 keep_all 그대로)
# r1210: 8자 단계 — 원장 머리 « · 상태 낡음»(+12B)이 붙으면 12자로도 1612B 라 전 팀 [발주]가 막혔다
HEAD = re.compile(r"^★골 표 A6 \((?:(?:[^()\s]+@)|(?:file:))?([0-9a-f]{10}) · [^)]*\)★$")  # r545: 출처 표지(`origin/main@`|`file:`) 붙은 새 꼴 + 표지 없는 옛 꼴 둘 다
TAIL = "★/골 표★"
COORD = re.compile(r"^골좌표:\s*(\d+)\s*[—-]\s*(.+?)\s*$")
STALE_FP_MAX = 12  # r600: 마커 판이 지금 ref 첫 부모 줄기에서 이만큼(약 2시간 · 시간당 약 6커밋) 넘게 뒤면 «골 표 낡음»
STALE_OLD = "REJECT 골 표 낡음"  # r726: 이 문구만 «직전 판 유예» 가 넘길 수 있다(줄기에 없음·확인 실패는 그대로 REJECT)
TEAMS_SECTION = re.compile(r"^##\s+팀별 완성 진행")
TEAMS_HEAD = "★팀별 완성 진행 ("
TEAMS_TAIL = "★/팀별 완성 진행★"
TEAMS_NOW_CELLS = (24, 16, 8)  # «지금 하는 것» 칸 — 예산(1600B)에 들 때까지 줄인다 · 팀·끝선·착지 칸은 12자
PROCS_SECTION = re.compile(r"^##\s+표준절차 골 진행표")  # r644: 원장의 표준절차 골 진행표(골 | 골 파일 | 지금 단계 | 다음 · 담당 열은 있을 때만)
PROCS_HEAD = "★표준절차 골 ("
PROCS_TAIL = "★/표준절차 골★"
# r1006: 뉴스 본문에 실리면 안 되는 블록 3종의 마커 목록 — 머리 정규식 + 꼬리 글자(문을 보는 쪽이 이 한 곳에서 가져간다 · 문자열 두 벌 0)
BLOCK_MARKS: tuple[tuple[str, re.Pattern[str], str], ...] = (
    ("골 표", HEAD, TAIL),
    ("팀별 완성 진행", re.compile("^" + re.escape(TEAMS_HEAD) + r"[0-9a-f]{10}\)★$"), TEAMS_TAIL),
    ("표준절차 골", re.compile("^" + re.escape(PROCS_HEAD) + r"[0-9a-f]{10}\)★$"), PROCS_TAIL),
)
PROCS_NAME_CELLS = (40, 24, 12)  # «지금 단계» 칸 — 예산(1600B)에 들 때까지 줄인다(teams 와 같은 꼴)
PROCS_FILE = re.compile(r"^GOAL-.+-[0-9]{8}\.md$")  # 날짜 붙은 골 파일만(AUTONOMY-GOAL-A6·GOAL-planner.md·날짜 없는 파일 제외)
PROCS_TITLE = re.compile(r"^#\s*골\s*[—–-]\s*(.+?)\s*$")
PROCS_OWNER = re.compile(r"^[>\s]*담당\s*[:：]\s*(\S.*)$")
SHORT_SHA = re.compile(r"(?<![0-9a-f])[0-9a-f]{10}(?![0-9a-f])")
PROCS_STALE_H = 24
RENUMBER_STATE = "goal-numbering.tsv"  # r668 — «골 번호 공지» 표식(같은 정본 sha 로 두 번 보내지 않는다 · r726: 둘째 줄에 «직전 판» 을 적는다)
PREV_TAG = "prev"  # r726 — 표식 둘째 줄 `prev	<sha10>	<번호표 지문>	<번호표 바뀐 시각 epoch>`
SHA10 = re.compile(r"[0-9a-f]{10}")  # r726 r3 — 표식 형식 검사(첫 줄·직전 줄의 sha 칸)
FP12 = re.compile(r"[0-9a-f]{12}")  # r726 r3 — 번호표 지문 칸(_num_hash = sha256 앞 12자)
GRACE_H = 24.0  # r726 — 직전 정본 1판을 인정하는 시간(시간 단위 · FT_GOAL_RENUMBER_GRACE_H · 0 = 유예 없음 = 지금 판과 같다)
GRACE_ENV = "FT_GOAL_RENUMBER_GRACE_H"
LEGACY_N = 6  # r668 H4: 예전 코드가 박아 둔 골 개수 — 표식 없는 첫 렌더에서 «바뀐 판인가» 의 기준
CANON_NAME = re.compile(r"^AUTONOMY-GOAL-A6-\d{8}\.md$")  # r728 — 정본 꼴 이름(기본 spec 과 같은 꼴 · DEFAULT_NAME)
NOTIFY_TIMEOUT = 7  # r668 H4: 송신 1통 상한(초) — mbox 가 멈춰도 렌더는 계속


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


def _canon_render() -> bool:
    """r728 — «진짜 정본 렌더» 인가: 기본 ref(FT_TEAMS_REF·origin/main) 의 gitref + 정본 꼴 이름(AUTONOMY-GOAL-A6-<8자리>.md).
    기본 spec 글자와 같은 값도 이 규칙에 들어간다. 파일 경로(`file:` 표지)·다른 ref 의 gitref·다른 이름 = 시안·시험 렌더 → 공지·표식 쓰기 0.
    기본 spec 을 풀어 비교하지 않는 이유: 명부(`design/TEAMS.md`) 없는 시험 픽스처에서도 기본 렌더를 기본으로 알아야 한다(오공지 0 은 시안에만 적용)."""
    spec = _spec()
    parts = spec.split(":", 2)
    if len(parts) != 3 or parts[0] != "gitref":
        return False
    ref, name = parts[1], parts[2].rsplit("/", 1)[-1]
    return ref == (os.environ.get("FT_TEAMS_REF") or "origin/main") and CANON_NAME.match(name) is not None


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
    """정본 표 «## 골 → 팀 → 닫는 증거» 의 N행 → 각 행의 칸 3개 `|`-분리 (골·팀·증거) — N = 표의 데이터 행 수(1~FT_GOAL_MAX · r668).
    r668 H1: 절 아래 «첫 표의 연속 행» 만 센다 — 빈 줄이나 다음 `##` 에서 멈춘다(뒤쪽 다른 절의 표가 N 을 부풀리지 않는다)."""
    sect = re.split(r"^##\s+골\s*→\s*팀\s*→\s*닫는 증거\s*$", text, maxsplit=1, flags=re.M)
    rows: list[list[str]] = []
    started = False
    for ln in sect[1].splitlines() if len(sect) > 1 else []:
        if not ln.startswith("|"):
            if started:
                break
            continue
        started = True
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if cells[0].startswith("골(") or all(set(c) <= set("-: ") for c in cells):
            continue  # 머리 줄·구분선
        rows.append(cells)
    n, cap = len(rows), goal_max()
    if not 1 <= n <= cap or any(len(r) != 3 or not all(r) for r in rows):
        raise GoalError(f"ERROR 골 표 정본 표가 {n}행(칸 3개)이 아니다 — 1~{cap}행(FT_GOAL_MAX)이어야 한다: {n}행")
    return rows


def numbering(rows: list[list[str]]) -> str:
    """새 번호표 N줄 — «1 — <골 앞 12자> · 2 — …» (r668 · 번호가 바뀐 판을 만난 좌석이 그 자리에서 고친다)."""
    return " · ".join(f"{i} — {_norm(r[0])[:12]}" for i, r in enumerate(rows, 1))


def _ledger_show(spec: str) -> str | None:
    """`gitref:<ref>:<경로>` 원장 → 그 ref 의 commit 으로 1회 확정해 읽는다 · 그 ref 에 경로가 없으면 None(«상태 없음» WARN 경로 · r545)."""
    _, ref, rel = spec.split(":", 2)
    commit = _git(_repo(), "rev-parse", "--verify", ref).strip()
    return _git(_repo(), "show", f"{commit}:{rel}") if _git_ok(_repo(), "cat-file", "-e", f"{commit}:{rel}") else None


def _cut(s: str, keep_all: bool = False, width: int = CELL) -> str:
    s = _norm(s).replace("|", "/")
    return s if keep_all or len(s) <= width else s[:width] + "…"


def _root_state(root: Path, name: str) -> Path:
    """표식 파일 = `<루트>/.fable-team/state/<name>` — 뉴스 기동 기록과 같은 자리(r510)."""
    return root / ".fable-team" / "state" / name


def _notify_root() -> Path | None:
    """공지에 쓸 루트 = env FT_ROOT › find_root() · 없으면 None. ★렌더는 출처 env 만으로도 돈다★(예: 뉴스 시험 픽스처) — 공지 때문에 렌더를 죽이지 않는다(r668)."""
    if env := os.environ.get("FT_ROOT"):
        return Path(env)
    try:
        return _root()
    except GoalError:
        return None


def _masters(root: Path) -> tuple[list[str], list[str]]:
    """(전 팀장 이름들, 깨진 명부 파일 이름들) — 명부 `_master`(백업 `.bak*` 제외 · 중복 0).
    r668 H4: 깨진 명부는 조용히 빼지 않고 둘째 값으로 돌려준다(부르는 쪽이 WARN + 표식 전진 0)."""
    out: list[str] = []
    bad: list[str] = []
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        if ".bak" in f.name:
            continue
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            bad.append(f.name)
            continue
        if not isinstance(data, dict):
            bad.append(f.name)
            continue
        name = str(data.get("_master") or "").strip()
        if name and name not in out:
            out.append(name)
    return out, bad


def _num_hash(num: str) -> str:
    """번호표 지문 = numbering() 글의 sha256 앞 12자(행 수·각 행 골 앞 12자가 바뀌면 값이 바뀐다)."""
    return hashlib.sha256(num.encode("utf-8")).hexdigest()[:12]


def _renumber_sig(sha: str, rows: list[list[str]]) -> str:
    """표식 첫 줄 = «정본 sha10<TAB>번호표 지문» — 번호표 = 행 수·각 행 골 앞 12자(numbering)."""
    return f"{sha}\t{_num_hash(numbering(rows))}"


def _split_mark(text: str) -> tuple[str, str]:
    """표식 글 → (첫 줄 = 지금 판, «직전 판» 줄 또는 빈 글). 옛 꼴(한 줄)도 그대로 읽는다."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return (lines[0] if lines else ""), next((ln for ln in lines[1:] if ln.startswith(PREV_TAG + "\t")), "")


def _advance(mark: Path, sig: str, prev_line: str = "") -> None:
    try:
        mark.parent.mkdir(parents=True, exist_ok=True)
        mark.write_text(sig + "\n" + (prev_line + "\n" if prev_line else ""), encoding="utf-8")
    except OSError as e:
        print(f"WARN 골 번호 공지 표식 못 씀 {mark}: {e}", file=sys.stderr)


def _prev_record(mark: Path) -> tuple[str, str, int, str] | None:
    """표식의 «직전 판» = (sha10, 번호표 지문, 번호표 바뀐 시각 epoch, 첫 줄의 번호표 지문) · 형식·손상 = None(= 유예 없음 → 지금처럼 REJECT).
    r726 r3: 표식 두 줄을 «정확한 형식» 으로 본다(DA 질문 1) — 첫 줄 `<sha10 hex>\t<지문 12 hex>` · prev 줄 `prev\t<sha10 hex>\t<지문 12 hex>\t<유한 정수 epoch>`.
    아니면 유예 0 — `garbage` 첫 줄·빈 prev sha(`_fp_dist("")` 가 0 을 도는 것)·소수/NaN 시각을 한 자리에서 막는다."""
    try:
        text = mark.read_text(encoding="utf-8")
    except OSError:
        return None
    cur_line, prev = _split_mark(text)
    cur = cur_line.split("\t")
    if len(cur) != 2 or not SHA10.fullmatch(cur[0]) or not FP12.fullmatch(cur[1]):
        return None
    f = prev.split("\t")
    if len(f) != 4 or f[0] != PREV_TAG or not SHA10.fullmatch(f[1]) or not FP12.fullmatch(f[2]):
        return None
    try:
        ts = int(f[3])
    except ValueError:
        return None
    return f[1], f[2], ts, cur[1]


def _grace_h() -> float:
    """유예 시간(시간) — env FT_GOAL_RENUMBER_GRACE_H · 값이 깨지면 기본 24 · 0 이면 유예 없음(지금 판과 같다).
    r726 r3(DA 질문 3): env 는 «줄이기» 만 — `min(env, 24)` · 음수 = 0 · NaN/Inf = 기본 24(늘리기 0)."""
    try:
        h = float(os.environ.get(GRACE_ENV) or GRACE_H)
    except ValueError:
        return GRACE_H
    if not math.isfinite(h):
        return GRACE_H
    return min(max(h, 0.0), GRACE_H)


def _grace_mark() -> Path | None:
    """유예 표식 경로 — 루트를 못 풀면 None(유예 없음). 판정 경로도 같은 표식을 «읽기만» 한다(쓰기는 렌더만)."""
    root = _notify_root()
    return _root_state(root, RENUMBER_STATE) if root is not None else None


def _hours(h: float) -> str:
    return f"{h:.1f}".rstrip("0").rstrip(".")


def _fp_dist(sha: str) -> int | None:
    """sha 가 지금 ref 의 첫 부모 줄기에서 몇 커밋 앞인가 — 줄기에 없음·git 실패·gitref 아님 = None(fail-closed)."""
    spec = _spec()
    if not spec.startswith("gitref:"):
        return None
    try:
        chain = _git(_repo(), "rev-list", "--first-parent", spec.split(":", 2)[1]).split()
    except GoalError:
        return None
    return next((i for i, c in enumerate(chain) if c.startswith(sha)), None)


def _fp_of_commit(sha: str) -> str | None:
    """그 커밋이 가리키는 정본의 번호표 지문 — gitref 정본이 아니거나 읽기 실패 = None(유예 0).
    r726 r3(DA 질문 3): 표식에 임의의 옛 sha·지문을 써 넣어도 유예가 열리지 않게 «실제 이력» 과 대조한다."""
    spec = _spec()
    if not spec.startswith("gitref:"):
        return None
    try:
        return _num_hash(numbering(parse_rows(_git(_repo(), "show", f"{sha}:{spec.split(':', 2)[2]}"))))
    except GoalError:
        return None


def _grace(sha: str, old_num: str, rows: list[list[str]]) -> str:
    """r726 — 옛 마커의 «번호표 지문» 이 표식의 직전 판 지문과 같고 번호표가 바뀐 시각 뒤 유예 시간 안이면 GOAL-OK 에 붙일 글을, 아니면 빈 글.
    결속 키는 번호표 지문이다(마커 sha 는 렌더 순간의 main 커밋이라 «한 커밋 앞» 렌더가 유예 밖으로 떨어졌다 — r2 반송).
    신선도 상한: 마커가 첫 부모 줄기에 있고 dist(마커) <= dist(rec[0]) + STALE_FP_MAX 일 때만(낡은 블록이 유예로 새지 않는다).
    두 판 이상 옛 판·표식 없음/손상·번호표가 그대로인 판·유예 밖은 모두 «빈 글» = 지금처럼 REJECT."""
    if (hours := _grace_h()) <= 0:
        return ""
    mark = _grace_mark()
    rec = _prev_record(mark) if mark is not None else None
    cur_num = _num_hash(numbering(rows))
    if rec is None or rec[1] != _num_hash(old_num) or rec[1] == cur_num:
        return ""
    if rec[3] != cur_num:
        return ""  # r726 r3: 표식 첫 줄이 «지금 정본 판» 을 가리켜야 한다 — 공지 실패로 뒤처진 표식은 두 판 전 블록을 열지 않는다(DA 질문 5)
    if _fp_of_commit(rec[0]) != rec[1]:
        return ""  # r726 r3: «직전 판» 은 실제 이력의 그 판이어야 한다 — 표식에 임의로 적은 sha·지문은 유예 0(DA 질문 3)
    base, dist = _fp_dist(rec[0]), _fp_dist(sha)
    if base is None or dist is None or dist > base + STALE_FP_MAX:
        return ""
    elapsed = _procs_now().timestamp() - rec[2]
    if elapsed < 0 or elapsed >= hours * 3600:
        return ""  # r726 r3: 미래 시각(경과 < 0)·경계(경과 >= 유예) 는 유예 0 — 리셋되는 시계를 만들지 않는다
    rem = hours - elapsed / 3600
    seat = os.environ.get("FT_SEAT") or os.environ.get("FT_SENDER") or "-"
    new = f"새 번호표 {len(rows)}줄: {numbering(rows)}"
    print(f"GRACE 옛 번호표 수용 — 좌석 {seat} · 마커 {sha} · 남은 {_hours(rem)}시간 · {new}", file=sys.stderr)
    return f" 옛 번호표(유예 {_hours(rem)}시간 남음 · {new})"


def _notify_once(root: Path, mark: Path, sha: str, rows: list[list[str]]) -> None:
    """잠금 안에서 읽기 → (필요하면) 송신 → 표식 쓰기. 깨진 명부·송신 실패 = WARN · 표식 전진 0(다음 렌더가 다시 시도 · r668 H4③④).
    r726: 번호표가 바뀌면 표식 둘째 줄에 «직전 판(sha10·번호표 지문·바뀐 시각)» 을 남긴다 — 그 한 판만 유예로 인정한다."""
    sig = _renumber_sig(sha, rows)
    try:
        prev = mark.read_text(encoding="utf-8").strip()
    except OSError:
        prev = ""
    cur_line, prev_line = _split_mark(prev)
    if cur_line == sig:
        return
    old_sig = cur_line.partition("\t")[2]
    # 표식 없음 = 설치 직후 첫 렌더 — 옛 고정(6행)과 다르면 바뀐 판으로 본다(r668 H4①)
    changed = old_sig != sig.partition("\t")[2] if cur_line else len(rows) != LEGACY_N
    if not changed:
        _advance(mark, sig, prev_line)
        return
    masters, bad = _masters(root)
    for name in bad:
        print(f"WARN 골 번호 공지 — 깨진 명부(조용히 빼지 않는다): {name}", file=sys.stderr)
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    sent = True
    if not Path(mbox).is_file():
        print(f"WARN 골 번호 공지 못 함 — mbox 없음: {mbox}", file=sys.stderr)
        sent = False
    else:
        body = f"[골 번호 바뀜] 정본 {sha} · 새 번호표 {len(rows)}줄: {numbering(rows)}"
        for to in masters:
            try:
                done = subprocess.run(["bash", mbox, "send", to, "ft-goal-table", body], capture_output=True, text=True, check=False, timeout=NOTIFY_TIMEOUT)
            except (OSError, subprocess.SubprocessError) as e:
                print(f"WARN 골 번호 공지 실패 {to}: {e}", file=sys.stderr)
                sent = False
                continue
            if done.returncode != 0:
                print(f"WARN 골 번호 공지 실패 {to}: {done.stderr.strip()[:120]}", file=sys.stderr)
                sent = False
    if bad or not sent:
        return  # 표식 전진 0 — 굳히지 않고 다음 렌더가 다시 시도한다
    old_sha = cur_line.partition("\t")[0]  # r726: 번호표가 바뀐 순간 직전 판을 박아 둔다(유예 근거)
    _advance(mark, sig, f"{PREV_TAG}\t{old_sha}\t{old_sig}\t{int(_procs_now().timestamp())}" if old_sha else "")


DRAFT_INFO: list[str] = []  # r728 — 시안 렌더 INFO 1줄은 «블록을 stdout 에 쓴 뒤» stderr 로 낸다(2>&1 캡처에서 블록이 첫 줄 = 소비처 파싱 그대로)


def _notify_or_skip(sha: str, rows: list[list[str]]) -> None:
    """r728 — 정본 렌더만 공지·표식(notify_renumber). 시안·시험 렌더(파일 경로·다른 ref·다른 이름 주입)는 쓰기 0 + stderr 1줄."""
    if _canon_render():
        notify_renumber(sha, rows)
        return
    DRAFT_INFO.append(f"INFO 시안 렌더 — 번호 공지·표식 0 (정본 {_spec()})")


def notify_renumber(sha: str, rows: list[list[str]]) -> None:
    """r668 ⓖ — 정본 sha 가 바뀌고 골 번호표(행 수·순서)가 바뀐 첫 렌더에 전 팀장에게 1통. 같은 정본 sha 로는 1회(표식).
    읽기→송신→쓰기에 파일 잠금 — 동시 렌더가 겹쳐도 1통(r668 H4②). 공지 실패 = WARN 1줄(렌더는 계속 — 공지가 뉴스를 멈추지 않는다).
    루트를 못 풀면 조용히 건너뛴다(명부·표식 자리가 없다)."""
    root = _notify_root()
    if root is None:
        return
    mark = _root_state(root, RENUMBER_STATE)
    try:
        mark.parent.mkdir(parents=True, exist_ok=True)
        with open(mark.with_name(RENUMBER_STATE + ".lock"), "a+", encoding="utf-8") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                _notify_once(root, mark, sha, rows)
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    except OSError as e:
        print(f"WARN 골 번호 공지 표식 못 씀 {mark}: {e}", file=sys.stderr)


def _goal_hash(goal: str) -> str:
    """골 칸 전문(NFC·공백 정규화) sha256 앞 10자 — 회차 파일의 행 식별과 «같은 함수»(대응 대조 · 설계 r3 §4)."""
    return hashlib.sha256(_norm(goal).encode("utf-8")).hexdigest()[:10]


def render() -> str:
    text, sha, src = load_canon()
    rows = parse_rows(text)
    head, states = ledger_state(_ledger_show, GoalError, n=len(rows))
    state = readjust_read()                                   # r714a: 기록 없음도 정상(None 두 칸)
    note = readjust_header(state).replace("(", "/").replace(")", "/")   # 머리 괄호 = 마커 정규식 보호
    canon_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]
    cells = [readjust_cell(state, i, _goal_hash(g), canon_sha) for i, (g, _t, _e) in enumerate(rows, 1)]
    out = ""
    # 예산 넘치면 «재조정» 칸부터 라벨 글자만으로 줄이고(r714a), 그래도 넘치면 팀·상태·증거 칸 폭을 차례로 줄인다(r731)
    plan = [(True, GOAL_CELLS[0])] + [(False, w) for w in GOAL_CELLS]
    for keep_suffix, width in plan:
        pick = cells if keep_suffix else [c.split("·")[0] for c in cells]
        body = [f"| {_cut(g, True)} | {_cut(t, width=width)} | {_cut(states.get(i, NO_STATE), width=width)} | {_cut(e, width=width)} | {pick[i - 1]} |"
                for i, (g, t, e) in enumerate(rows, 1)]
        out = "\n".join([f"★골 표 A6 ({src}{sha} · {head} · {note})★",
                          "| 골 | 팀 | 지금 상태 | 닫는 증거 | 재조정 |", "|---|---|---|---|---|", *body, TAIL])
        if len(out.encode("utf-8")) <= BUDGET:
            _notify_or_skip(sha, rows)
            return out + "\n"
    raise GoalError(f"ERROR 골 표 예산 초과 {len(out.encode('utf-8'))}B > {BUDGET}B (골 원문 칸은 절단하지 않는다)")


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
        out = "\n".join([f"{TEAMS_HEAD}{sha})★", "| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |", "|---|---|---|---|", *body, TEAMS_TAIL])
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
        return "\n".join([f"{PROCS_HEAD}{sha})★", "표준절차 골 0", PROCS_TAIL]) + "\n"
    done = [i for i in items if i["done"]]
    late = [i for i in items if i["late"] and not i["done"]]
    for width in PROCS_NAME_CELLS:
        body = [f"- {i['name']} · {i['owner']} · {_clip(i['stage'], width)}" + (f" ⚠ {i['stale']}시간 정지" if i["late"] else "") for i in items if not i["done"]]
        out = "\n".join([f"{PROCS_HEAD}{sha})★", *([f"완성 {len(done)}: " + ", ".join(i["name"] for i in done)] if done else []), *body,
                         *([f"정지 골 {len(late)}: " + ", ".join(i["name"] for i in late)] if late else []), PROCS_TAIL])
        if len(out.encode("utf-8")) <= BUDGET:
            return out + "\n"
    print(f"WARN 표준절차 골 예산 초과 {len(out.encode('utf-8'))}B > {BUDGET}B ({len(items)}줄) — 블록 없이 발행", file=sys.stderr)
    return ""


def _canon_for(sha: str) -> tuple[list[list[str]], str, list[list[str]]]:
    """마커 sha10 의 정본 행 + 유예 문구 + 지금 정본 행 — sha 가 지금 정본과 같으면 그대로 · 옛 sha 면 «번호표가 같을 때»(r668 H2) 또는 «직전 판 유예»(r726)만 인정한다."""
    text, cur, _ = load_canon()
    rows = parse_rows(text)
    if cur == sha:
        return rows, "", rows
    spec = _spec()
    if not spec.startswith("gitref:"):
        raise GoalError(f"마커 sha10 {sha} 이 정본({cur})과 다르다")
    old = parse_rows(_git(_repo(), "show", f"{sha}:{spec.split(':', 2)[2]}"))
    if numbering(old) == numbering(rows):
        return old, "", rows
    if grace := _grace(sha, numbering(old), rows):
        return old, grace, rows
    raise GoalError(f"마커 sha10 {sha} 의 번호표({len(old)}줄)가 지금 정본 {cur}({len(rows)}줄)과 다르다 — 옛 번호표로는 판정하지 않는다"
                    f" · 새 번호표 {len(rows)}줄: {numbering(rows)} · ft-goal-table.sh 를 다시 돌려 붙인다")


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
    if stale and not stale.startswith(STALE_OLD):
        return 3, stale  # 줄기에 없음·신선도 확인 실패 = 유예로 넘기지 않는다(fail-closed)
    try:
        canon, grace, cur = _canon_for(sha)
    except GoalError as e:
        return 3, f"REJECT 골 없음 — 정본 대조 실패: {e}"
    if stale and not grace:
        return 3, stale  # r726: 유예로 인정한 직전 판만 신선도(«낡음»)를 넘긴다 — 유예 시간이 그 축을 대신한다
    got = [[_norm(c) for c in ln.strip().strip("|").split("|")] for ln in block if ln.startswith("| ") and not ln.startswith("| 골 |")]
    n = len(canon)
    if len(got) != n or any(g[0] != _norm(c[0]) for g, c in zip(got, canon)):
        return 3, f"REJECT 골 없음 — 블록의 {len(got)}행이 정본(마커 sha10) {n}행과 다르다 · 새 번호표 {len(cur)}줄: {numbering(cur)}"
    if block_only:
        return 0, "GOAL-OK block-only" + grace
    for ln in lines:
        if m := COORD.match(ln.strip()):
            num, want = int(m[1]), _norm(canon[int(m[1]) - 1][0]) if 1 <= int(m[1]) <= n else ""
            if want and _norm(m[2]) == want[:12].rstrip():
                return 0, f"GOAL-OK n={num}{grace}"
            return 3, (f"REJECT 골 없음 — 골좌표 번호와 골 원문이 안 맞는다(번호 1~{n} · 원문 앞 {min(12, len(want)) or 12}자 복붙)"
                       f" · 새 번호표 {len(cur)}줄: {numbering(cur)} — {ln.strip()[:40]}")
    return 3, f"REJECT 골 없음 — `골좌표: <1~{n}> — <골 원문 앞 12자>` 줄이 없다 · 새 번호표 {len(cur)}줄: {numbering(cur)}"


def main(argv: list[str]) -> int:
    try:
        if argv[:1] == ["check"]:
            args = [a for a in argv[1:] if a != "--block-only"]
            src = args[0] if args else "-"
            rc, msg = check(sys.stdin.read() if src == "-" else Path(src).read_text(encoding="utf-8"), "--block-only" in argv)
            print(msg)
            return rc
        sys.stdout.write({"teams": render_teams, "procs": render_procs}.get(argv[0] if argv else "", render)())
        sys.stdout.flush()
        for line in DRAFT_INFO:   # r728 — 시안 렌더 INFO(블록 뒤 · 소비처가 첫 줄을 머리로 읽는다)
            print(line, file=sys.stderr)
        return 0
    except GoalError as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
