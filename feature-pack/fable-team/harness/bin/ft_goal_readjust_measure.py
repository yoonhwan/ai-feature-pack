"""ft_goal_readjust_measure — 골 재조정 «회차 측정» (r714a · ft_goal_readjust 가 부른다 · 200줄 규칙으로 나눈 파일).

한 회차의 «사실» 만 잰다: fetch 로 commit 을 고정하고 정본·원장·팀 폴더·카드·증거를 **그 commit 트리**에서 읽어
행별 사실(카드 추가 수 · 증거 전환 · 원장 그 행 변화 · 원장 «✅ 시작») + 라벨 5종(기준/확인 불가/마감/움직임/변화 0(N시간)) + 경보를 만든다.
★디스크 폴더 실재로 팀 폴더를 고르지 않는다★(`cat-file -e <commit>:<후보>` 정확히 1개 — 설계 §3) · ★쓰기 0★(읽기·fetch 뿐 · 회차 파일은 ft_goal_readjust 몫).
선택 입력(다른 카드 자리 · 없으면 «모름» 글자 · 0 으로 합치지 않는다): `goal-evidence.json`(r693) · `goal-row-swap.json`(r702) · `goal-landed.json`(r664) · `goal-live.json`(r708).
7초 상한 = git 한 번 · fetch 만 재시도 1회(실패 2회 = ERROR).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
import unicodedata
from datetime import datetime, timedelta
from pathlib import Path

import ft_goal_ledger as gl
import ft_goal_table as gt
import ft_team_lib as tl

COORD = re.compile(r"^골좌표:\s*(\d+)\s*[—-]")
COORD_SECTION = re.compile(r"^##\s+골좌표", re.M)
_T0 = time.monotonic()  # 회차 총 예산의 기산점(모듈 import = 본체 시작 · DA H10)
PROCS_FILE = re.compile(r"^GOAL-.+-[0-9]{8}\.md$")
DIRTY_PARENS = str.maketrans({"(": "/", ")": "/"})
STALL_H = 24
QUOTE = ("-c", "core.quotePath=false")  # 한글 경로를 따옴표·8진 이스케이프 없이 받는다(diff·ls-tree 이름 대조)
BODY_MAX = 700
SKIP = (".sent.json", ".send-failed.json")
LABELS = ("기준", "확인 불가", "마감", "움직임")

class ReadjustError(RuntimeError):
    pass


def _now() -> datetime:
    """회차 시계 — FT_NOW("YYYY-MM-DD HH:MM")가 있으면 그 분(시험 고정 시계) · 없으면 지금. started·finished 가 같은 시계를 쓴다."""
    value = os.environ.get("FT_NOW")
    return datetime.strptime(value, "%Y-%m-%d %H:%M") if value else datetime.now()


def _flat(s: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", s)).strip()


def _hash(s: str) -> str:
    """골 칸·원장 행 지문 = 정규화(NFC·공백 1칸) 전문 sha256 앞 10자."""
    return hashlib.sha256(_flat(s).encode("utf-8")).hexdigest()[:10]


def _sha10(text: str) -> str:
    """입력 본문 지문 = 원문 바이트 sha256 앞 10자(render 가 마커·대응 대조에 쓰는 값과 같은 함수)."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]


def _git(repo: Path, *args: str, timeout: float = 7) -> str:
    """git 한 번(7초 상한 · ★남은 회차 예산도 넘지 않는다★ — DA H10 · 카드·행 반복 안에서도 마감이 선다) — 실패는 ReadjustError(조용한 통과 0)."""
    left = _remaining()
    if left <= 0:
        raise ReadjustError(f"시간 초과 — 예산 {int(_budget_sec())}초를 다 썼다(git {args[0]})")
    try:
        done = subprocess.run(["git", "-C", str(repo), *QUOTE, *args], capture_output=True, text=True, encoding="utf-8",
                              timeout=min(timeout, left), check=False)
    except subprocess.TimeoutExpired as e:
        raise ReadjustError(f"시간 초과 — git {args[0]} 가 남은 예산 {left:.1f}초를 넘겼다") from e
    except (OSError, subprocess.SubprocessError) as e:
        raise ReadjustError(f"git {args[0]} 실패: {e}") from e
    if done.returncode != 0:
        raise ReadjustError(f"git {args[0]} 실패: {done.stderr.strip()[:140]}")
    return done.stdout


def _git_ok(repo: Path, *args: str) -> bool:
    left = _remaining()
    if left <= 0:
        raise ReadjustError(f"시간 초과 — 예산 {int(_budget_sec())}초를 다 썼다(git {args[0]})")
    try:
        return subprocess.run(["git", "-C", str(repo), *QUOTE, *args], capture_output=True, text=True,
                              timeout=min(7, left), check=False).returncode == 0
    except subprocess.TimeoutExpired as e:
        raise ReadjustError(f"시간 초과 — git {args[0]} 가 남은 예산 {left:.1f}초를 넘겼다") from e
    except (OSError, subprocess.SubprocessError):
        return False


def _has(repo: Path, commit: str, rel: str) -> bool:
    return bool(rel) and _git_ok(repo, "cat-file", "-e", f"{commit}:{rel.rstrip('/')}")


def _env_h(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return default


def _spec_rel(spec: str) -> str | None:
    return spec.split(":", 2)[2] if spec.startswith("gitref:") else None


def _budget_sec() -> float:
    return _env_h("FT_GOAL_READJUST_BUDGET", 65)


def _remaining() -> float:
    """남은 회차 예산(초) — git 한 번도 이걸 넘기지 않는다(DA H10)."""
    return _budget_sec() - (time.monotonic() - _T0)


def _budget() -> None:
    """회차 총 마감 — 측정 «중»에도 넘기면 ERROR 회차로 끝난다(DA H10 · 래퍼 timeout 70 보다 먼저 선다)."""
    used = time.monotonic() - _T0
    if used > _budget_sec():
        raise ReadjustError(f"시간 초과 — {int(used)}초 > 예산 {int(_budget_sec())}초(이번 회차 측정 중단)")


def _repo_rel(repo: Path, path: Path) -> str | None:
    """파일 출처 → 리포 안 상대 경로(리포 밖이면 None)."""
    try:
        top = Path(_git(repo, "rev-parse", "--show-toplevel").strip()).resolve()
        rel = os.path.relpath(path.resolve(), top)
    except (ReadjustError, OSError, ValueError):
        return None
    return None if rel.startswith("..") else rel


def _read_input(repo: Path, commit: str, spec: str) -> str:
    """입력 본문 — ★모든 입력은 기록한 commit 트리에서★(설계 §3 · DA H6). 파일 출처도 리포 안이면 그 commit 판을 읽는다(작업 파일 직접 읽기 0)."""
    rel = _spec_rel(spec)
    if rel is None:
        rel = _repo_rel(repo, Path(spec))
        if rel is None:
            raise ReadjustError(f"입력이 리포 밖이다(고정 commit 으로 못 잰다): {spec}")
    if not _has(repo, commit, rel):
        raise ReadjustError(f"입력이 commit 트리에 없다 {commit[:10]}:{rel}")
    return _git(repo, "show", f"{commit}:{rel}")


def _ledger_env(repo: Path) -> str:
    """원장 출처 env — ★FT_LEDGER_PATH 상대 경로는 «리포 기준»★(옛 ft_goal_ledger.ledger_spec 과 같은 규칙 · cwd 기준이면 리포 밖에서 흔들린다 · DA 회귀 H6)."""
    spec = os.environ.get("FT_GOAL_A6_LEDGER") or ""
    if spec:
        return spec
    rel = os.environ.get("FT_LEDGER_PATH") or ""
    if not rel:
        return ""
    return rel if Path(rel).is_absolute() else str(repo / rel)


def _pin(spec: str, commit: str) -> str:
    """`gitref:<ref>:<경로>` 의 ref 를 «고정 commit» 으로 바꿔 둔다 — 가변 ref 재읽기 0(DA H6)."""
    return f"gitref:{commit}:{spec.split(':', 2)[2]}" if spec.startswith("gitref:") else spec


def _fetch(repo: Path, ref: str) -> None:
    """`git fetch origin <branch>` — 재시도 1회(7초씩) · 두 번 실패 = ERROR(설계 §2)."""
    branch = ref.split("/", 1)[1] if ref.startswith("origin/") else ref
    err = ""
    for _ in (1, 2):
        try:
            _git(repo, "fetch", "origin", branch, timeout=7)
            return
        except ReadjustError as e:
            err = str(e)
    raise ReadjustError(f"fetch 2회 실패({ref}): {err}")


def _byz() -> tuple[Path, str, str]:
    """(리포, ref, 고정 commit) — BYZ 저장소 = FT_GOAL_REPO › FT_LEDGER_REPO › LIVE_ROOT."""
    repo = Path(os.environ.get("FT_GOAL_REPO") or os.environ.get("FT_LEDGER_REPO") or gl.ledger_repo(ReadjustError))
    ref = os.environ.get("FT_TEAMS_REF") or "origin/main"
    _fetch(repo, ref)
    return repo, ref, _git(repo, "rev-parse", "--verify", ref).strip()


def _harness() -> tuple[Path, str, str, str] | None:
    """(하네스 리포, ref, commit, 리포 루트 → FT_HARNESS_ROOT 상대 prefix) — 없으면 None(harness 행만 «모름» · 다른 행 영향 0).
    ★하네스도 fetch(7초·재시도 1) 뒤 commit 고정★ · FT_HARNESS_ROOT 가 리포 하위 폴더면 prefix 를 붙인다(DA H5)."""
    root = os.environ.get("FT_HARNESS_ROOT")
    if not root or not Path(root).is_dir():
        return None
    root_p = Path(root).resolve()
    try:
        repo = Path(_git(root_p, "rev-parse", "--show-toplevel").strip()).resolve()
    except ReadjustError:
        return None
    ref = os.environ.get("FT_HARNESS_REF") or ("origin/main" if _git_ok(repo, "rev-parse", "--verify", "origin/main") else "")
    if not ref:
        return None
    try:
        _fetch(repo, ref)
        commit = _git(repo, "rev-parse", "--verify", ref).strip()
    except ReadjustError:
        return None
    prefix = "" if repo == root_p else os.path.relpath(root_p, repo).replace(os.sep, "/")
    return repo, ref, commit, prefix


def _team_cands(raw: str) -> list[str]:
    twins = [raw.rstrip("/")]
    if raw.startswith("design/teams/"):
        twins.append(raw.replace("design/teams/", "design/", 1).rstrip("/"))
    else:
        twins.append(raw.replace("design/", "design/teams/", 1).rstrip("/"))
    return twins


def _team_repo(team: str, byz: tuple[Path, str, str], harness: tuple[Path, str, str, str] | None,
               bases: dict[str, str | None]) -> dict:
    """팀 폴더를 «고정 commit 트리» 에서 푼다(`cat-file -e` 정확히 1개) — 꼴3($FT_HARNESS_ROOT)은 하네스 리포(설계 §3)."""
    repo, _ref, commit = byz
    try:
        rows = tl.team_rows_ref(commit, repo)
    except tl.TeamPathError as e:
        raise ReadjustError(str(e)) from e
    raw = rows.get(team)
    if raw is None:
        raise ReadjustError(f"{team} 팀이 명단(design/TEAMS.md)에 없다")
    if raw.startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")):
        if harness is None:
            raise ReadjustError("하네스 카드 모름(리포/ref 미정)")
        hrepo, _href, hcommit, hprefix = harness
        rel = raw.split("/", 1)[1].rstrip("/")
        return {"repo": hrepo, "commit": hcommit, "rel": f"{hprefix}/{rel}" if hprefix else rel, "base": bases.get("harness")}
    hits = [c for c in _team_cands(raw) if _has(repo, commit, c)]
    if len(hits) != 1:
        raise ReadjustError(f"{team} 폴더 후보 {len(hits)}개 — 정확히 1개여야 한다({' '.join(_team_cands(raw))})")
    return {"repo": repo, "commit": commit, "rel": hits[0], "base": bases.get("byz")}


def _tree_files(repo: Path, commit: str, rel: str) -> list[str]:
    if not _has(repo, commit, rel):
        return []
    out = _git(repo, "ls-tree", "-r", "--name-only", commit, "--", rel.rstrip("/") + "/")
    return [p for p in out.split() if p]


def _added_cards(info: dict) -> list[str]:
    """기준 commit → 이번 commit 사이 그 팀 `indices/완성/` 에 **추가된** 파일(설계 §2 골평가 ⓐ)."""
    base, commit = info.get("base"), info["commit"]
    folder = f"{info['rel']}/indices/완성"
    if not base:
        return []
    if base == commit:
        return []
    out = _git(info["repo"], "diff", "--name-only", "--diff-filter=A", base, commit, "--", folder.rstrip("/") + "/")
    return [p for p in out.split() if p]


def _card_row(text: str, rows_by_n: dict[int, str]) -> int | None:
    """카드 → 골 번호: `골좌표: <n> —` 줄 ∨ `## 골좌표` 절 첫 줄의 «골 <n>» + 골 전문 앞 12자(설계 §2 · 실제 꼴 대조는 DA 몫)."""
    for ln in text.splitlines():
        m = COORD.match(ln.strip())
        if m and int(m[1]) in rows_by_n:
            return int(m[1])
    parts = COORD_SECTION.split(text, maxsplit=1)
    if len(parts) > 1:
        first = next((ln.strip() for ln in parts[1].splitlines() if ln.strip()), "")
        m = re.search(r"골\s*(\d+)", first)
        if m and int(m[1]) in rows_by_n and rows_by_n[int(m[1])] in first:
            return int(m[1])
    return None


def _evidence(d: Path, n: int) -> str:
    """r693 «판별» 열(선택 입력) — 없음/미설정을 서로 다른 글자로(0 으로 합치지 않는다)."""
    path = d / "goal-evidence.json"
    if not path.is_file():
        return "모름(r693 미착지)"
    try:
        rows = (json.loads(path.read_text(encoding="utf-8")) or {}).get("rows") or {}
    except (OSError, ValueError):
        return "모름(r693 판별 미설정)"
    value = _flat(str(rows.get(str(n)) or ""))
    return value or "모름(r693 판별 미설정)"


def _stale_rows(d: Path) -> tuple[set[int], str]:
    """r702 표식(선택 입력) — «원장 미갱신(골 바뀜)» 행 번호 + «모름» 사유(DA H7: 손상·빈 표식도 «모름»)."""
    path = d / "goal-row-swap.json"
    if not path.is_file():
        return set(), "대응 유지 모름(r702 미착지)"
    try:
        data = json.loads(path.read_text(encoding="utf-8")) or {}
    except (OSError, ValueError):
        return set(), "대응 유지 모름(표식 손상)"
    if not isinstance(data, dict):
        return set(), "대응 유지 모름(표식 손상)"
    keys = [k for k in ("stale_rows", "rows") if k in data]
    if not keys:  # 키 자체가 없으면 «빈 표식» — 0 으로 합치지 않는다(DA H7)
        return set(), "대응 유지 모름(표식 비었음)"
    out: set[int] = set()
    for key in keys:
        for item in data.get(key) or []:
            if isinstance(item, int) and not isinstance(item, bool):
                out.add(item)
            elif isinstance(item, dict) and isinstance(item.get("n"), int):
                out.add(item["n"])
    return out, ""


def _option(d: Path, name: str, missing: str, broken: str) -> str:
    """선택 입력 파일 «있나» — 없음/손상/빈 파일을 서로 다른 «모름» 글자로(DA H7 · 0 으로 합치지 않는다)."""
    path = d / name
    if not path.is_file():
        return missing
    try:
        data = json.loads(path.read_text(encoding="utf-8") or "null")
    except (OSError, ValueError):
        return broken
    return "" if isinstance(data, dict) and data else broken


def _stamp(text: str, now: datetime) -> tuple[str, bool]:
    """원장 머리 `마지막 갱신:` → (`MM-DD HH:mm`, 24시간 초과 여부) — ft_goal_ledger._stale 와 같은 규칙(분 `0x` 꼴 대응)."""
    m = gl.STAMP.search(text)
    if not m:
        return "갱신 시각 없음", True
    minute = int(m[3]) if m[3].isdigit() else int(m[3][0]) * 10
    stamp = datetime.strptime(f"{m[1]} {m[2]}", "%Y-%m-%d %H") + timedelta(minutes=minute)
    return f"{m[1][5:]} {m[2]}:{m[3]}", now - stamp > gl.STALE_AFTER


def _age(repo: Path, commit: str, rel: str, lineno: int, now: datetime) -> float | None:
    """그 행이 마지막으로 바뀐 지 몇 시간인가(고정 commit 의 git blame) — 못 재면 None(«변화 0(시간 모름)»)."""
    try:
        blamed = _git(repo, "blame", "--porcelain", "-L", f"{lineno},{lineno}", commit, "--", rel).split()[0]
        stamp = float(_git(repo, "show", "-s", "--format=%ct", blamed).strip())
    except (ReadjustError, ValueError, IndexError):
        return None
    return (now.timestamp() - stamp) / 3600


def _baseline(d: Path, run: str) -> tuple[dict | None, str]:
    """기준 = 이름순 가장 최근 **status=OK ∧ run ≠ 이번 run** 파일 · 없으면 null «첫 회차»(설계 §1)."""
    for path in reversed(sorted((d / "rounds").glob("*.json"))):
        if path.name.endswith(SKIP):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and data.get("status") == "OK" and data.get("run") != run:
            return data, ""
    return None, "첫 회차"


def _label(row: dict, base_row: dict | None, base: bool, stale: set[int]) -> str:
    """라벨 우선순위(위가 이김 · 항상 하나) — 설계 §2 골평가."""
    if base:
        return "기준"
    if base_row is None or base_row.get("goal_hash") != row["goal_hash"] or row["n"] in stale:
        return "확인 불가"
    if row["ledger_closed"]:
        return "마감"
    if row["cards_added"] >= 1 or row["evidence_changed"] or row["ledger_row_changed"]:
        return "움직임"
    return f"변화 0({int(row['row_age_h'])}시간)" if row["row_age_h"] is not None else "변화 0(시간 모름)"


def measure(d: Path, now: datetime, run: str) -> dict:
    """한 회차 측정 — status=OK 회차 dict(실패는 예외로 올려 ERROR 파일을 쓴다)."""
    _budget()
    byz = _byz()
    repo, ref, commit = byz
    _budget()
    harness = _harness()
    base, reason = _baseline(d, run)
    repos = ((base or {}).get("inputs") or {}).get("repos") or {}
    bases = {kind: (repos.get(kind) or {}).get("commit") for kind in ("byz", "harness")}
    # ★입력 출처는 «이번에 고정한 commit» 으로 박는다★ — 가변 FT_TEAMS_REF 재읽기·작업 파일 직접 읽기 0(DA H6)
    planner_rel = gl.planner_rel_in_ref(ReadjustError, commit, repo)
    canon_spec = _pin(os.environ.get("FT_GOAL_A6_MD") or f"gitref:{commit}:{planner_rel}/{gt.DEFAULT_NAME}", commit)
    canon_text = _read_input(repo, commit, canon_spec)
    rows_canon = gt.parse_rows(canon_text)
    ledger_spec = _pin(_ledger_env(repo) or f"gitref:{commit}:{planner_rel}/PLAN-oppa-ledger.md", commit)
    ledger_text = _read_input(repo, commit, ledger_spec)
    ledger_rel = _spec_rel(ledger_spec) or str(ledger_spec)
    head, lrows = gl.table_with_header(ledger_text, ReadjustError)
    if head is None or len(lrows) != len(rows_canon):
        raise ReadjustError(f"원장 `## 메인 골 …줄` 표가 없거나 행 수가 다르다({len(lrows) if head else 0}≠{len(rows_canon)}) — {ledger_spec}")
    wanted = {r[1] for r in rows_canon} | {"planner"}
    info: dict[str, dict] = {}
    for team in sorted(wanted):
        try:
            info[team] = {**_team_repo(team, byz, harness, bases), "why": ""}
        except ReadjustError as e:
            info[team] = {"repo": None, "commit": commit, "rel": "", "base": None, "why": str(e)}
    rows_by_n = {i: _flat(g)[:12] for i, (g, _t, _e) in enumerate(rows_canon, 1)}
    cards: dict[int, int] = {}
    unassigned: list[str] = []
    for team, item in info.items():
        _budget()
        if not item["rel"]:
            unassigned.append(f"{team}: 카드 자리 모름({item['why']})")
            continue
        for path in _added_cards(item):
            try:
                text = _git(item["repo"], "show", f"{item['commit']}:{path}")
            except ReadjustError:
                continue
            n = _card_row(text, rows_by_n)
            if n is None:
                unassigned.append(path.rsplit("/", 1)[-1])
            else:
                cards[n] = cards.get(n, 0) + 1
    base_rows = {r.get("n"): r for r in (base or {}).get("rows") or [] if isinstance(r, dict)}
    stale, stale_why = _stale_rows(d)
    landed_why = _option(d, "goal-landed.json", "착지 모름(r664 미착지)", "착지 모름(r664 표식 손상)")
    live_why = _option(d, "goal-live.json", "라이브 판 모름(r708 미착지)", "라이브 판 모름(r708 표식 손상)")
    first = base is None
    rows = []
    for i, (goal, team, evidence) in enumerate(rows_canon, 1):
        _budget()
        lineno, cells = lrows[i - 1]
        state_cell = cells[1] if len(cells) > 1 else ""
        unknown = []
        if stale_why:
            unknown.append(stale_why)
        if info[team]["why"]:
            unknown.append(f"{team} 연결 모름({info[team]['why']})")
        if landed_why:
            unknown.append(landed_why)
        if live_why:
            unknown.append(live_why)
        row = {
            "n": i,
            "goal12": rows_by_n[i],
            "goal_hash": _hash(goal),
            "team": team,
            "ledger_row_hash": _hash(" | ".join(cells)),
            "ledger_row_head": _flat(state_cell)[:60],
            "ledger_closed": _flat(state_cell).startswith("✅"),
            "cards_added": cards.get(i, 0),
            "evidence": _evidence(d, i),
            "ledger_row_changed": bool(base_rows.get(i)) and base_rows[i].get("ledger_row_hash") != _hash(" | ".join(cells)),
            "row_age_h": _age(repo, commit, ledger_rel, lineno, now),
            "unknown": unknown,
        }
        row["evidence_changed"] = bool(base_rows.get(i)) and base_rows[i].get("evidence") != row["evidence"]
        row["label"] = _label(row, base_rows.get(i), first, stale)
        rows.append(row)
    _budget()
    facts = {
        "close_candidates": [r["n"] for r in rows if not r["label"] == "마감" and str(r["evidence"]).startswith("✅ 전부")],
        "goal_files_outside_canon": _outside_canon(info, rows_by_n),
        "open_cards": {t: _count_cards(i) for t, i in info.items() if i["rel"]},
        "unassigned_cards": unassigned,
        "stale_numbered_cards": _stale_numbered(info, len(rows_canon)),
        "broken_links": [r["n"] for r in rows if _broken(info, r)],
        "unknown": _handover_unknown(ledger_text, harness),
    }
    when, old = _stamp(ledger_text, now)
    alarms = _alarms(rows, facts, base, now, old, when)
    return {
        "run": run, "attempt": 0, "started": now.strftime("%Y-%m-%d %H:%M:%S"), "status": "OK", "error": "",
        "inputs": {
            "repos": {"byz": {"ref": ref, "commit": commit},
                      "harness": ({"root": str(harness[0]), "ref": harness[1], "commit": harness[2]} if harness else None)},
            "canon_sha10": _sha10(canon_text), "ledger_sha10": _sha10(ledger_text),
        },
        "rows": rows, "facts": facts, "alarms": alarms,
        "baseline": ({"file": base.get("_file") or f"{base.get('run')}-{base.get('attempt'):02d}.json"} if base else None),
        "baseline_reason": reason,
        "send": {"state": "none", "key": f"GR-{run}"},
    }


def _handover_unknown(ledger_text: str, harness: tuple[Path, str, str, str] | None) -> list[str]:
    """넘긴 3개의 «미착지» 글자 — r702 는 행 `unknown` 이 적고, r714c(응답 절)·r701(뉴스 표시)는 여기(DA H7).
    착지 판정 = 고정 commit 트리의 글자(원장 `## 골 재조정 응답` 절 · 뉴스 코드가 readjust_state 를 부름) — 사람 기억 0."""
    out = []
    if "## 골 재조정 응답" not in ledger_text:
        out.append("모름(r714c 미착지)")
    if not _news_landed(harness):
        out.append("모름(r701 미착지)")
    return out


def _news_landed(harness: tuple[Path, str, str, str] | None) -> bool:
    if harness is None:
        return False
    repo, _ref, commit, prefix = harness
    rel = f"{prefix}/kit/fable-team/bin/ft_news_html.py" if prefix else "kit/fable-team/bin/ft_news_html.py"
    try:
        return "ft_goal_readjust_state" in _git(repo, "show", f"{commit}:{rel}")
    except ReadjustError:
        return False


def _count_cards(item: dict) -> dict:
    out = {}
    for kind in ("진행", "대기"):
        out[kind] = len([p for p in _tree_files(item["repo"], item["commit"], f"{item['rel']}/indices/{kind}")])
    return out


def _outside_canon(info: dict, rows_by_n: dict[int, str]) -> list[str]:
    """planner 팀 폴더(commit 트리)의 `GOAL-*-<8자리>.md` 중 정본 표에 goal12 로 없는 파일명(설계 §2 골재설정)."""
    item = info.get("planner")
    if not item or not item["rel"]:
        return []
    names = [p.rsplit("/", 1)[-1] for p in _tree_files(item["repo"], item["commit"], item["rel"])]
    known = [g for g in rows_by_n.values() if g]
    return sorted(n for n in names if PROCS_FILE.match(n) and not any(g in n for g in known))


def _stale_numbered(repo_team: dict, n: int) -> list[str]:
    out = []
    for team, item in repo_team.items():
        if not item["rel"]:
            continue
        for kind in ("진행", "대기"):
            for path in _tree_files(item["repo"], item["commit"], f"{item['rel']}/indices/{kind}"):
                if not path.endswith(".md"):
                    continue
                try:
                    text = _git(item["repo"], "show", f"{item['commit']}:{path}")
                except ReadjustError:
                    continue
                num = next((int(m[1]) for ln in text.splitlines() if (m := COORD.match(ln.strip()))), None)
                if num is not None and not 1 <= num <= n:
                    out.append(path.rsplit("/", 1)[-1])
    return out


def _broken(info: dict, row: dict) -> bool:
    """골관리 ①② — ①담당 팀이 명단에 있음 ②`GOAL-<팀>.md` 가 `골좌표: <n> —` 를 참조 · 마감 행은 면제(설계 §2 골관리)."""
    if row["label"] == "마감":
        return False
    item = info.get(row["team"]) or {}
    if not item.get("rel"):
        return True
    try:
        text = _git(item["repo"], "show", f"{item['commit']}:{item['rel']}/GOAL-{row['team']}.md")
    except ReadjustError:
        return True
    nums = [int(m[1]) for ln in text.splitlines() if (m := COORD.match(ln.strip()))]
    return row["n"] not in nums


def _alarms(rows: list[dict], facts: dict, base: dict | None, now: datetime, old: bool, when: str) -> list[str]:
    """골점검 경보 ①~⑥ — 경보 0 이면 빈 목록(보고서가 «경보 0» 글자를 쓴다)."""
    out = []
    if old:
        out.append(f"원장 상태 낡음({when})")
    stall = _env_h("FT_GOAL_STALL_H", STALL_H)
    for r in rows:
        if r["label"].startswith("변화 0(") and r["row_age_h"] is not None and r["row_age_h"] >= stall:
            out.append(f"{r['n']}행 변화 0({int(r['row_age_h'])}시간)")
        if r["label"] == "확인 불가":
            out.append(f"{r['n']}행 확인 불가")
    out += [f"연결 끊김 행 {n}" for n in facts["broken_links"]]
    return out


