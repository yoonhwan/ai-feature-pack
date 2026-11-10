"""ft_team_move_classify — 팀 폴더 이동(R382) 뒤 남은 옛 경로를 «고칠 것 / 보관할 기록 / 그냥 글자» 로 가른다 (r899 · 읽기 전용).

ft_team_move.py 가 부른다(--verify 의 코드 칸 · --classify · --cleanup-plan). 여기서는 쓰기 0.
좌석 기록(명부 index · nano-card-base card_path):
  LIVE-OK      살아 있는 좌석(tmux 세션 있음) · 카드가 다른 기준(카드 워크트리·팀 루트)에 실재 — 고칠 것 0(검사 기준 차이)
  LIVE-FIX     살아 있는 좌석 · 옮긴 폴더(design/<팀>/ → design/teams/<팀>/ · 나머지 경로 그대로)에 카드 실재 → 그 경로로 다시 씀
  LIVE-HAND    살아 있는 좌석 · 옮긴 경로에 없음 → 사람이 고친다(자동 0) · 상태 폴더(대기·진행·완성·보류)만 다른 후보는 사유에 적는다
               (상태 폴더 이동은 spawn·close 와 겹치는 순간이 있어 자동으로 따라가지 않는다 — 실측: 막 열린 나노 카드가 다른 워크트리엔 아직 대기/)
  ARCHIVE      tmux 세션 없음(닫힌 좌석) → 명부·nano-card-base 에서 빼서 보관(지우기 0)
  KEEP-FIX     KEEP-LINEAGE 행인데 옮긴 폴더에 index 실재 → 행은 남기고 index 만 새 경로로
  KEEP-LINEAGE 닫힌 역할 좌석(이름에 -nano-·-temp- 없음 · 나노는 카드 이름이라 번호 계보 아님) 중 그 계보(<베이스>#N)의 최댓값 행 — 남긴다(ft-role-spawn.sh 가 명부 키 최댓값+1 로 다음 번호를 매김 · 빼면 번호 재사용)
코드·시험 옛 경로(`design/<팀>/`):
  CODE-RUN     실행되는 글자(셸 비주석 줄 전부 · 그 밖은 주석·독스트링 밖 · 따옴표·대입(=)·pathspec(!)·$변수/ 바로 뒤에서 경로가 시작) → 새 경로로 고칠 것(ERR 유지)
  CODE-NOTE    주석·독스트링·문장 중간 글자(메시지·설명) → WARN(보임 유지 · ERR 아님)
  CODE-RECORD  기록 폴더(design/evidence/** · */archive|evidence*|closeout|research/** · .omc/**) 안 → WARN(재실행 0 기록)
  CODE-FIXTURE 시험 데이터 파일(tests/** 의 비코드 · fixtures/**) — design/TEAM-MOVE-ALLOW.tsv 에 사유와 함께 있으면 셈 밖, 없으면 ERR
tmux 목록을 못 읽으면 좌석 분류 전체를 멈춘다(MoveError) — «살아 있는 좌석을 닫힌 것으로» 보는 길 0.
env: FT_TEAM_MOVE_TMUX(기본 tmux) · FT_TEAM_MOVE_ALLOW(기본 <리포>/design/TEAM-MOVE-ALLOW.tsv)
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

STATUS_DIRS = ("대기", "진행", "완성", "보류")
CODE_EXT = (".py", ".sh", ".ts", ".tsx", ".js")
NOTE_LEAD = {".py": ("#",), ".sh": ("#",), ".yaml": ("#",), ".toml": ("#",),
             ".ts": ("//", "*", "/*"), ".tsx": ("//", "*", "/*"), ".js": ("//", "*", "/*")}


def row_sha(obj) -> str:
    """행 전체 지문 — 계획이 «읽은 판» 과 실행이 «다시 읽은 판» 을 같은지 견준다(r899 r2 반례 3·4)."""
    return hashlib.sha256(json.dumps(obj, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def norm_text(team: str, text: str) -> str:
    """판정용 글자 정규화 — 경로 앞 «./» 와 따옴표 안 앞뒤 공백을 지운 «뒤» 로 가른다(파일은 안 고친다 · 반례 5)."""
    t = re.sub(rf"\./design/{re.escape(team)}/", f"design/{team}/", text)
    t = re.sub(r"""(["'`])\s+""", r"\1", t)
    return re.sub(r"""\s+(["'`])""", r"\1", t)


def live_sessions(run, MoveError) -> set[str]:
    """tmux 세션 이름 집합 — 못 읽으면(서버 없음 포함) MoveError: 살아 있음 판정 불가면 보관 판정도 0."""
    try:
        tm = run(os.environ.get("FT_TEAM_MOVE_TMUX", "tmux"), "list-sessions", "-F", "#{session_name}")
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MoveError(f"ERROR tmux 세션 목록을 못 읽었다({e}) — 좌석 분류 생략(보관 판정 0)")
    names = {ln.strip() for ln in tm.stdout.splitlines() if ln.strip()}
    if tm.returncode != 0 or not names:
        raise MoveError(f"ERROR tmux 세션 목록 rc={tm.returncode} 세션 {len(names)}개 — 좌석 분류 생략(보관 판정 0)")
    return names


def candidates(cp: str, team: str) -> list[str]:
    """옛 card_path/index → 새 경로 후보(옮긴 폴더 · 상태 폴더 이동). 원본은 넣지 않는다."""
    moved = re.sub(rf"^design/{re.escape(team)}/", f"design/teams/{team}/", cp)
    out = [moved] if moved != cp else []
    for base in (cp, moved):
        m = re.match(r"^(.*/indices/)([^/]+)/(.+)$", base)
        if m and m.group(2) in STATUS_DIRS:
            out += [f"{m.group(1)}{s}/{m.group(3)}" for s in STATUS_DIRS if s != m.group(2)]
    return list(dict.fromkeys(out))


def seat_class(ref: str, team: str, bases: list[Path], live: bool) -> tuple[str, str]:
    """(분류, 새 경로 또는 사유)."""
    if not live:
        return "ARCHIVE", "tmux 세션 없음"
    if any((b / ref).exists() for b in bases):
        return "LIVE-OK", "다른 기준에 실재: " + ",".join(b.name for b in bases if (b / ref).exists())
    moved = re.sub(rf"^design/{re.escape(team)}/", f"design/teams/{team}/", ref)
    if moved != ref and any((b / moved).exists() for b in bases):
        return "LIVE-FIX", moved
    found = sorted({c for c in candidates(ref, team) for b in bases if (b / c).exists()})
    return "LIVE-HAND", f"옮긴 경로에 없음 · 상태 폴더만 다른 후보 {len(found)}개" + (f": {','.join(found)}" if found else "")


def bases_for(ctx, data: dict, row: dict, team_repo: Path | None, store_base) -> list[Path]:
    """카드를 찾을 기준들 — 행 worktree(경로·이름) · 명부 _cards_wt · 팀 루트 리포 · 프로젝트 루트 · 이동 커밋 워크트리."""
    out = [store_base(ctx, data, row)]
    wt = row.get("worktree") if isinstance(row, dict) else None
    if wt and os.path.isabs(str(wt)):
        out.insert(0, Path(wt))
    if data.get("_cards_wt"):
        out.append(ctx.project / ".worktrees" / data["_cards_wt"])
    out += [p for p in (team_repo, ctx.project, ctx.root) if p]
    return list(dict.fromkeys(out))


def lineage_max(keys) -> dict[str, int]:
    """<베이스>#N 의 베이스별 최댓값 — 명부 키 + 살아 있는 세션."""
    top: dict[str, int] = {}
    for k in keys:
        base, _, n = str(k).rpartition("#")
        if base and n.isdigit():
            top[base] = max(top.get(base, -1), int(n))
    return top


def seats(ctx, team: str, live: set[str], team_repo: Path | None, store_base, snaps: dict | None = None) -> list[dict]:
    """명부·nano-card-base 에서 «실재 안 함» 행만 분류해 돌려준다(check_stores 와 같은 대상).
    snaps 를 주면 «그때 읽은 바이트» 를 파일별로 담는다 — 분류와 row_sha 가 «한 판» 에서 나온다(반례 3)."""
    out: list[dict] = []
    snaps = snaps if snaps is not None else {}
    ros = ctx.roster(team)
    raw = ros.read_text(encoding="utf-8") if ros.is_file() else ""
    snaps[str(ros)] = raw
    data = json.loads(raw) if raw else {}
    top = lineage_max([*data, *live])
    for seat, row in data.items():
        if seat.startswith("_") or not isinstance(row, dict) or not str(row.get("index", "")).startswith("design/"):
            continue
        if (store_base(ctx, data, row) / row["index"]).exists():
            continue
        cls, why = seat_class(row["index"], team, bases_for(ctx, data, row, team_repo, store_base), seat in live)
        base, _, n = seat.rpartition("#")
        if cls == "ARCHIVE" and not ("-nano-" in seat or "-temp-" in seat) and n.isdigit() and top.get(base) == int(n):
            cls, why = "KEEP-LINEAGE", f"계보 {base} 최댓값 #{n} — 다음 번호 기준(빼지 않음)"
            moved = re.sub(rf"^design/{re.escape(team)}/", f"design/teams/{team}/", row["index"])
            if moved != row["index"] and any((b / moved).exists() for b in bases_for(ctx, data, row, team_repo, store_base)):
                cls, why = "KEEP-FIX", moved
        out.append({"store": "roster", "team": team, "file": str(ros), "seat": seat, "ref": row["index"], "cls": cls, "why": why,
                    "row_sha": row_sha(row)})
    cb = ctx.project / ".fable-team" / "state" / "nano-card-base"
    for p in sorted(cb.glob("*.json")) if cb.is_dir() else []:
        raw = p.read_text(encoding="utf-8")
        snaps[str(p)] = raw
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        cp = str(row.get("card_path", ""))
        if not (cp.startswith(f"design/teams/{team}/") or cp.startswith(f"design/{team}/")):
            continue
        if (Path(row.get("worktree") or ctx.project) / cp).exists():
            continue
        bases = bases_for(ctx, data, row, team_repo, store_base)
        cls, why = seat_class(cp, team, bases, str(row.get("name") or p.stem) in live)
        out.append({"store": "ncb", "team": team, "file": str(p), "seat": str(row.get("name") or p.stem), "ref": cp, "cls": cls, "why": why,
                    "row_sha": row_sha(row)})
    return out


def allow_list(root: Path) -> dict[str, str]:
    """design/TEAM-MOVE-ALLOW.tsv — `<경로>\\t<사유>` · # 주석 · 사유 빈 줄은 무효(예외 0)."""
    p = Path(os.environ.get("FT_TEAM_MOVE_ALLOW") or root / "design" / "TEAM-MOVE-ALLOW.tsv")
    out: dict[str, str] = {}
    for ln in p.read_text(encoding="utf-8").splitlines() if p.is_file() else []:
        path, _, why = ln.partition("\t")
        if path.strip() and not path.startswith("#") and why.strip():
            out[path.strip()] = why.strip()
    return out


def is_fixture(rel: str) -> bool:
    parts = rel.split("/")
    return "fixtures" in parts[:-1] or (parts[0] == "tests" and not rel.endswith(CODE_EXT))


def doc_lines(src: str) -> set[int]:
    """파이썬 독스트링이 차지한 줄 번호들(모듈·클래스·함수 첫 문장 문자열)."""
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError):
        return set()
    out: set[int] = set()
    for node in [tree, *ast.walk(tree)]:
        body = getattr(node, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(getattr(body[0], "value", None), ast.Constant) and isinstance(body[0].value.value, str):
            out.update(range(body[0].lineno, (body[0].end_lineno or body[0].lineno) + 1))
    return out


def is_record_path(rel: str) -> bool:
    parts = rel.split("/")[:-1]
    return rel.startswith("design/evidence/") or ".omc" in parts or (parts[:1] == ["design"] and any(
        p in ("archive", "closeout", "research") or p.startswith("evidence") for p in parts[1:]))


def run_re(team: str) -> re.Pattern:
    return re.compile(rf"""(?:["'=!]|\$\{{?\w+\}}?/)\s*design/{re.escape(team)}/""")


def code_class(root: Path, rel: str, no: int, allow: dict[str, str], cache: dict, team: str) -> tuple[str, str]:
    """(분류, 사유) — CODE-RUN · CODE-NOTE · CODE-RECORD · CODE-FIXTURE(허용 목록 사유) · CODE-FIXTURE-UNLISTED."""
    if is_fixture(rel) and not rel.endswith(CODE_EXT):   # 반례 5: 허용 목록은 «시험 데이터» 만 — 코드 확장자는 예외 0(코드면 RUN = ERR)
        return ("CODE-FIXTURE", allow[rel]) if rel in allow else ("CODE-FIXTURE-UNLISTED", "시험 데이터 · 허용 목록에 없음")
    if rel not in cache:
        try:
            src = (root / rel).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            src = ""
        cache[rel] = (src.splitlines(), doc_lines(src) if rel.endswith(".py") else set())
    lines, docs = cache[rel]
    text = norm_text(team, lines[no - 1].strip()) if 0 < no <= len(lines) else ""
    ext = os.path.splitext(rel)[1]
    if no in docs or text.startswith(NOTE_LEAD.get(ext, ())):
        return "CODE-NOTE", "주석·독스트링"
    if is_record_path(rel):
        return "CODE-RECORD", "기록 폴더"
    if ext != ".sh" and not run_re(team).search(text):   # 셸 비주석 줄은 인자째 실행 — 따옴표 없어도 RUN
        return "CODE-NOTE", "문장 중간 글자(경로 시작 아님)"
    return "CODE-RUN", "실행 글자"
