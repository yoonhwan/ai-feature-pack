r"""ft_goal_ledger — 골 표 «지금 상태» 6칸의 출처 = planner 원장 `## 메인 골 6줄` 표 (R371 · ft_goal_table.render 가 부른다).

루트 = env FT_ROOT(그 안에 .fable-team/LIVE_BIN 필수) · 없으면 이 파일 위치에서 조상으로 올라가 `.fable-team/LIVE_BIN` 이 있는 첫 폴더 · LIVE_ROOT = LIVE_BIN 1행(절대경로 · 실재 폴더)/../.. (정본·원장 둘이 이 함수 하나).
원장 = env FT_GOAL_A6_LEDGER(파일 경로 | `gitref:<ref>:<경로>`) 우선 · 없으면 <LIVE_ROOT>/design/planner/PLAN-oppa-ledger.md. LIVE_BIN 없음/무효 = ERROR rc1(옛 v6 고정 경로 후퇴 0). 절 `## 메인 골 6줄…` 의 첫 표 «데이터 행 6개» 를 행 순번(1~6)으로 정본 골에 묶는다(원장 골 글자는 정본과 달라 글자 대조 0) · 2열 = 지금 상태.
셀 = `\|` 를 글자 `|` 로 복원해 분리 · 열 수가 머리 줄과 다르면 ERROR(조용한 절단 0) · 행 수 ≠ 6 = ERROR rc1 · 파일·절 없음 = «상태 없음» + stderr WARN 1줄 ·
머리 `원장:<MM-DD HH:mm>` · 마지막 갱신 24h 초과 또는 갱신 시각 없음 = «· 상태 낡음»(파일 mtime 으로 되돌아가지 않는다).
"""
from __future__ import annotations

import os
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable

NO_STATE = "상태 없음"
SECTION = re.compile(r"^##\s+메인 골 6줄")
STAMP = re.compile(r"마지막 갱신:\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}):(\d[\dx])")
STALE_AFTER = timedelta(hours=24)


def _no_live_bin(file: Path, value: str = "") -> str:
    return (f"ERROR 골 표 기본 출처: LIVE_BIN 이 없거나 무효 {file} = {value!r} (절대경로 · 실재 폴더 필요 · env FT_GOAL_A6_MD·FT_GOAL_A6_LEDGER 로 직접 지정 가능)")


def find_root(error: type[Exception]) -> Path:
    """루트 = FT_ROOT(LIVE_BIN 필수) 또는 파일 위치 조상 중 `.fable-team/LIVE_BIN` 이 있는 첫 폴더 — 없으면 error(사유에 경로)."""
    if env := os.environ.get("FT_ROOT"):
        file = Path(env) / ".fable-team" / "LIVE_BIN"
        if not file.is_file():
            raise error(_no_live_bin(file))
        return Path(env)
    start = Path(__file__).resolve()
    for d in start.parents:
        if (d / ".fable-team" / "LIVE_BIN").is_file():
            return d
    raise error(_no_live_bin(start / "…위로 탐색 실패 · .fable-team" / "LIVE_BIN"))


def live_root(error: type[Exception]) -> Path:
    """LIVE_ROOT = 루트의 LIVE_BIN 1행(절대경로·실재 폴더) /../.. — 못 풀면 error(고정 경로·옛 원장으로 되돌아가지 않는다)."""
    file = find_root(error) / ".fable-team" / "LIVE_BIN"
    try:
        value = file.read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, IndexError):
        value = ""
    if not value.startswith("/") or not Path(value).is_dir():
        raise error(_no_live_bin(file, value))
    return Path(os.path.normpath(Path(value) / ".." / ".."))


def _spec(error: type[Exception]) -> str:
    return os.environ.get("FT_GOAL_A6_LEDGER") or str(live_root(error) / "design" / "planner" / "PLAN-oppa-ledger.md")


def _read(spec: str, git_show: Callable[[str], str]) -> str | None:
    if spec.startswith("gitref:"):
        return git_show(spec)
    try:
        return Path(spec).read_text(encoding="utf-8")
    except OSError:
        return None


def _cells(line: str) -> list[str]:
    r"""표 한 줄 → 칸 — 칸 안의 `\|` 는 글자 `|` 로 복원(단순 split 0)."""
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", body)]


def _rows(text: str, error: type[Exception]) -> list[list[str]] | None:
    """절 아래 첫 표의 데이터 행(칸 분리) — 절이 없으면 None · 열 수가 머리 줄과 다른 행 = error."""
    rows: list[list[str]] = []
    inside = False
    width = 0
    for ln in text.splitlines():
        if SECTION.match(ln):
            inside = True
        elif inside and ln.startswith("## "):
            break
        elif inside and ln.startswith("|"):
            cells = _cells(ln)
            if not width:
                width = len(cells)  # 첫 표 줄 = 머리 줄 → 열 수 기준
            elif len(cells) != width:
                raise error(f"ERROR 골 표 원장 열 수 {len(cells)}≠{width} (표 {len(rows) + 1}번째 데이터 줄 · `|` 글자는 `\\|` 로 적는다): {ln.strip()[:60]}")
            elif not set(cells[0]) <= set("-: "):
                rows.append(cells)
        elif inside and width:
            break
    return rows if inside else None


def _stale(text: str, now: datetime) -> tuple[str, bool]:
    """(`MM-DD HH:mm` 표기 그대로 · 24h 초과 여부) — 분이 `0x` 처럼 흐려도 앞 숫자 × 10 분으로 잰다."""
    m = STAMP.search(text)
    if not m:
        return "갱신 시각 없음", True
    minute = int(m[3]) if m[3].isdigit() else int(m[3][0]) * 10
    stamp = datetime.strptime(f"{m[1]} {m[2]}", "%Y-%m-%d %H") + timedelta(minutes=minute)
    return f"{m[1][5:]} {m[2]}:{m[3]}", now - stamp > STALE_AFTER


def ledger_state(git_show: Callable[[str], str], error: type[Exception], now: datetime | None = None) -> tuple[str, dict[int, str]]:
    """(머리 글자, {행번호: 지금 상태}) — error = 호출자의 GoalError."""
    spec = _spec(error)
    text = _read(spec, git_show)
    rows = _rows(text, error) if text is not None else None
    if rows is None:
        print(f"WARN 골 표 원장 상태 칸 없음({'파일' if text is None else '절'}): {spec} — «{NO_STATE}» 6칸으로 발행", file=sys.stderr)
        return NO_STATE, {}
    if len(rows) != 6:
        raise error(f"ERROR 골 표 원장 행 수 {len(rows)}≠6 ({spec} 절 `## 메인 골 6줄` 첫 표)")
    when, old = _stale(text or "", now or datetime.now())
    return f"원장:{when}{' · 상태 낡음' if old else ''}", {i: (r[1] or NO_STATE) for i, r in enumerate(rows, 1)}
