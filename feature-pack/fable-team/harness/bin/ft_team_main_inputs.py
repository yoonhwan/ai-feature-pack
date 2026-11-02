"""ft_team_main_inputs — r1315 STATE 렌더 입력: 로컬 파일·로컬 git 만(도구 실행 0 · 네트워크 0).
① 지시 정본 표(`design/teams/planner/THREAD-oppa-directives-<ts>-*.md` 중 ts 최대 · origin/main) 의 «팀» 열 행
② 카드 = directive-roots.tsv ref 의 카드 폴더(진행·대기·완성) + «## 상태» 끝 줄 + «- 지시 #» + «- 확인:» · 머리·좌석 = `state/<팀>-tick/HEADLINE*`(좌석 칸은 초안 1줄을 ft_headline_seats.parse 로 푼다 · r1290 W1~W5)
③ 집계 = `state/{card-assign,decision,hil}/latest.json`(20분 넘게 다르면 판정 불가) · 실패는 Undecided(그 칸만 «판정 불가(사유)» · 조용한 0 금지)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import ft_headline_seats as headline  # r1290 W1: 초안 1줄을 쓰는 꼴과 같은 모듈의 parse 로 푼다

GIT_SEC, STALE_MIN = float(os.environ.get("FT_TEAM_MAIN_GIT_SEC") or 7), 20
DIR, PRE, KINDS = "design/teams/planner", "THREAD-oppa-directives-", ("진행", "대기", "완성")
SEAT = re.compile(r"byz-([a-z0-9_-]+?)-(?:master|arch|da|pm|desk|nano|tester|checker|analyst|impl)")
SEQ, NL = re.compile(r"^#(\d+)"), re.compile(r"^-\s*지시\s*#\s*:\s*(\d+)", re.M)
CK, SPLIT = re.compile(r"^-\s*확인\s*:", re.M), re.compile(r"[,\s·/]+")
TS, SEP = re.compile(r"-(\d{9,})-"), re.compile(r":?-{2,}:?")


class Undecided(Exception):
    """그 칸만 «판정 불가(사유)» — 다른 칸은 쓴다."""


def _git(repo: str | Path, *args: str) -> str:  # 7초 + 재시도 1(하드 룰 12) · 실패 = Undecided
    err = ""
    for _ in range(2):
        try:
            p = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=GIT_SEC)
        except (OSError, subprocess.SubprocessError) as e:
            err = f"{e.__class__.__name__} {e}"[:80]
            continue
        if p.returncode == 0:
            return p.stdout
        err = f"git {args[0]} rc={p.returncode} {p.stderr.strip()[:80]}"
    raise Undecided(err)


def roots(root: Path) -> list[list[str]]:  # 카드 루트 표 — 팀·리포·ref·카드 폴더 4열(없음·유효 행 0 = 판정 불가)
    path = root / ".fable-team/state/directive-roots.tsv"
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    rows = [r for r in (ln.split("\t")[:4] for ln in text.splitlines() if ln.strip() and not ln.startswith("#")) if len(r) == 4 and all(c.strip() for c in r)]
    if not rows:
        raise Undecided(f"카드 루트 표 없음·유효 행 0({path})")
    return rows


def route(root: Path, rows: list[list[str]], team: str) -> tuple[str, str, str]:  # 이 팀 행(없으면 `*` 행) → (리포, ref, 카드 폴더)
    row = next((r for r in rows if r[0] == team), None) or next((r for r in rows if r[0] == "*"), None)
    if row is None:
        raise Undecided("카드 루트 표에 이 팀 행 없음")
    return (row[1] if os.path.isabs(row[1]) else str((root / row[1]).resolve()), row[2],
            row[3].replace("*", team) if "*" in row[3] else row[3])


def _tables(text: str) -> list[tuple[list[str], list[list[str]]]]:  # 구분선 웃줄 = 머리 · 그 뒤부터 다음 표 머리 앞까지 = 본문
    lines = [ln.strip() for ln in text.splitlines() if ln.strip().startswith("|")]
    cells = lambda ln: [c.strip() for c in ln.strip("|").split("|")]  # noqa: E731
    sep = lambda row: bool(row) and all(SEP.fullmatch(c.replace(" ", "")) for c in row)  # noqa: E731
    marks = [i for i, ln in enumerate(lines) if i > 0 and sep(cells(ln))]
    return [(cells(lines[i - 1]), [cells(ln) for ln in lines[i + 1:(marks[k + 1] - 1 if k + 1 < len(marks) else len(lines))]])
            for k, i in enumerate(marks)]


def directive(repo: str, ref: str, team: str, override: str | None = None) -> tuple[list[dict], list[str]]:  # (이 팀 행, 팀 미지정 번호)
    _idx = lambda h, *k: next((i for i, c in enumerate(h) if any(x in c for x in k)), None)  # noqa: E731
    if override:
        try:
            text = Path(override).read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            raise Undecided("지시 표 없음") from None
    else:
        names = [p for p in _git(repo, "ls-tree", "--name-only", ref, "--", f"{DIR}/").splitlines()
                 if p.startswith(f"{DIR}/{PRE}") and p.endswith(".md")]
        if not names:
            raise Undecided("지시 표 없음")
        text = _git(repo, "show", f"{ref}:{max(names, key=lambda p: int((TS.search(p.rsplit('/', 1)[-1]) or TS.search('-0-')).group(1)))}")
    for header, body in _tables(text):
        if "팀" not in header or len(header) < 3:
            continue
        ti, wi, xi = header.index("팀"), _idx(header, "시각", "ts", "날짜"), _idx(header, "지시", "원문")
        si, ei = _idx(header, "상태"), _idx(header, "닫는", "증거")
        rows = [{"team": c[ti], "n": c[0], "when": c[wi] if wi is not None else "", "text": c[xi] if xi is not None else "",
                 "status": c[si] if si is not None else "", "ev": c[ei] if ei is not None else ""}
                for c in (cells + [""] * (len(header) - len(cells)) for cells in body)]
        keep, miss = [], []
        for r in rows:
            parts = [x for x in SPLIT.split(r["team"].strip()) if x]
            if "닫힘" in r["status"]:
                continue
            if not parts:
                miss.append(r["n"] or "?")
            elif team in parts or any(x in ("전팀", "전체", "*") for x in parts):
                keep.append(r)
        return keep, miss
    raise Undecided("지시 표 팀 열 없음")


def _blobs(repo: str, ref: str, paths: list[str]) -> dict[str, str]:  # `git cat-file --batch` 1회로 카드 본문 여러 개
    if not paths:
        return {}
    try:  # (paths 빈 목록 = 호출 전에 걸러진다)
        p = subprocess.run(["git", "-C", repo, "cat-file", "--batch"], input="".join(f"{ref}:{x}\n" for x in paths).encode(),
                           capture_output=True, timeout=GIT_SEC * 3)
    except (OSError, subprocess.SubprocessError) as e:
        raise Undecided(f"git cat-file {e.__class__.__name__}") from None
    if p.returncode:
        raise Undecided(f"git cat-file rc={p.returncode} {p.stderr.decode('utf-8', 'replace').strip()[:80]}")
    out, got, i = p.stdout, {}, 0
    for path in paths:
        nl = out.find(b"\n", i)
        if nl < 0:
            break
        head, i = out[i:nl].decode("utf-8", "replace").split(), nl + 1
        if len(head) >= 3 and head[1] != "missing":
            got[path], i = out[i:i + int(head[2])].decode("utf-8", "replace"), i + int(head[2]) + 1
    return got


def status_line(text: str) -> str | None:  # 줄 머리 제목 «## 상태» 절의 마지막 줄(카드 상태 정본) · 70자 넘으면 «…»
    m = re.search(r"(?m)^##[ \t]*상태", text)
    tail = text[m.end():] if m else ""
    nxt = re.search(r"(?m)^##[ \t]", tail)
    lines = [ln.strip() for ln in (tail[:nxt.start()] if nxt else tail).splitlines() if ln.strip()]
    if not lines:
        return None
    line = re.sub(r"^[-*]\s*", "", lines[-1])
    return line[:70] + "…" if len(line) > 70 else line


def cards(repo: str, ref: str, folder: str) -> dict[str, list[dict]]:  # → {진행·대기·완성: [{stem,status,n,check}]}
    pat = folder.rstrip("/")
    paths = [p for p in _git(repo, "ls-tree", "-r", "--name-only", ref, "--", pat).splitlines() if p.startswith(f"{pat}/") and p.endswith(".md")]
    groups: dict[str, list[str]] = {}
    for p in paths:
        seg = p[len(pat) + 1:].split("/")
        if len(seg) == 2 and seg[0] in KINDS:  # archive 등 하위 폴더 제외
            groups.setdefault(seg[0], []).append(p)
    texts = _blobs(repo, ref, [p for group in groups.values() for p in group])
    out: dict[str, list[dict]] = {}
    for kind, ps in groups.items():
        out[kind] = sorted(({"stem": p.rsplit("/", 1)[-1][:-3], "status": status_line(texts[p]) if texts.get(p) else None,
                             "n": int(m.group(1)) if (m := NL.search(texts.get(p) or "")) else None,
                             "check": bool(CK.search(texts.get(p) or ""))} for p in ps), key=lambda r: r["stem"])
    return out


def latest(root: Path, kind: str, now: float) -> dict:  # 없음·JSON 아님·최상위 객체 아님·꼴 다름·20분 넘게 다름 = Undecided
    path = root / ".fable-team/state" / kind / "latest.json"
    if not path.is_file():
        raise Undecided("latest 없음")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise Undecided("latest JSON 아님") from None
    w, items = (doc.get("written_at"), doc.get("items")) if isinstance(doc, dict) else (None, None)  # 최상위 []·null·문자열도 «꼴 다름»
    if not isinstance(w, int) or not isinstance(items, list):
        raise Undecided("latest 꼴 다름(written_at·items)")
    gap = int((now - w) / 60)
    if abs(gap) > STALE_MIN:
        raise Undecided(f"집계 {gap}분 전" if gap > 0 else f"집계 {-gap}분 뒤")
    return {"items": items, "stamp": doc["stamp"] if "stamp" in doc else None}


def _read(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return []


def _text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return ""


def tick_files(root: Path, team: str) -> tuple[str | None, dict]:  # (머리 = HEADLINE.md 첫 줄, 좌석 칸 {cells, folded, why})
    d = root / f".fable-team/state/{team}-tick"
    head = next((x.strip() for x in _read(d / "HEADLINE.md") if x.strip()), None)
    path = d / "HEADLINE-seats.txt"
    if not path.is_file():
        return head, {"cells": {}, "folded": False, "why": "초안 없음"}  # W3: 파일 없음 = 판정 불가(초안 없음)
    cells, folded = headline.parse(_text(path))
    return head, {"cells": cells, "folded": folded, "why": None if cells else "초안 꼴 다름"}  # W2·W6·W7


def card_seat(seats: dict, stem: str) -> str:  # 카드 1장 → 좌석 칸(W2~W5) · 조용한 «?» 금지
    """조회 키 = 카드 stem 첫 낱말(«r1290-headline-…» → «r1290»). 칸 없음 = «좌석 칸 없음»(접힘 묶음 있으면 «유휴(접힘)»)."""
    if seats.get("why"):
        return f"판정 불가({seats['why']})"
    key = str(stem).split("-", 1)[0]
    if key in (seats.get("cells") or {}):
        return str(seats["cells"][key])
    return "유휴(접힘)" if seats.get("folded") else "좌석 칸 없음"
