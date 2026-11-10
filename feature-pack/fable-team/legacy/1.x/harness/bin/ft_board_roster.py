"""ft-board 현역 세대 선정 (R132a · 제안서 §7-7 최종 규칙) — 현역 단정은 «근거» 가 있을 때만. 가장 큰 번호로 고르는 대체 0.

tmux 에 살아 있는 명부 행만 대상. 위에서 걸리면 끝:
 1. 명시 은퇴 표시 = 제외: 행의 `_replaced_by` 또는 `seat-resume/<이름>.json`(ft-seat-retire.sh 가 은퇴 때 씀)
 2. 포인터 = 현역 근거: 명부 키 `_<role>`(`_master`·`_arch`·`_da` …)의 값이 role 이 같은 행을 가리키면 그 행이 현역 · 같은 role 의 다른 행과
    같은 계보의 다른 세대는 제외. 가리키는 행이 stopped/stop-ready 여도 현역(멈춘 현재 좌석 — 칸은 고정 문구).
    (`_hil_route`·`_label` 처럼 값이 그 role 의 행 이름이 아니거나 키에 `_` 가 있는 것은 포인터가 아니다)
 3. 근거 없는 생존 = 확인 불가(숨김 0): 계보(`#N` 앞)별로 1개든 2개 이상이든 현역 단정 0 → 칸 «확인 불가(현역 근거 없음: …)».
    예외 1개 — 나노 계보(role=nano 또는 FT_NANO_PREFIX 접두 · 계보마다 `#0` 하나뿐인 생산 규칙)의 `#0` 단일 생존 = 현역.
    정지레디·닫힘(role stop-ready/stopped)도 포인터 밖이면 일반 행과 같이 1~3 을 탄다(무조건 현역 예외 없음).
env: FT_SEAT_RESUME_DIR(기본 ~/.claude/state/seat-resume) · FT_NANO_PREFIX
"""
import os
import re
from pathlib import Path

FIXED_ROLES = ("stop-ready", "stopped")


def lineage(name: str) -> str:
    return re.sub(r"#\d+$", "", name)


def retired_names(resume_dir: Path | None) -> set[str]:
    d = resume_dir or Path(os.environ.get("FT_SEAT_RESUME_DIR", str(Path.home() / ".claude" / "state" / "seat-resume")))
    return {f.name.removesuffix(".json") for f in d.glob("*.json")} if d.is_dir() else set()


def _pointers(seats: dict) -> dict:
    """{role: 현역 행 이름} — 값이 그 role 의 행 이름(또는 멈춘 그 자리의 stopped/stop-ready 행)인 `_<role>` 키만."""
    out = {}
    for key, val in seats.items():
        row = seats.get(val) if isinstance(val, str) else None
        if key.startswith("_") and isinstance(row, dict) and (row.get("role") == key[1:] or (row.get("role") in FIXED_ROLES and "_" not in key[1:])):
            out[key[1:]] = val
    return out


def _is_nano(name: str, row: dict) -> bool:
    prefix = os.environ.get("FT_NANO_PREFIX", "")
    return row.get("role") == "nano" or bool(prefix and name.startswith(prefix))


def select(seats: dict, alive: set, resume_dir: Path | None = None) -> tuple[list[str], dict[str, str]]:
    """(현역 이름들, {확인 불가 이름: 칸 문자열})"""
    retired, pointers = retired_names(resume_dir), _pointers(seats)
    pointed = {lineage(v) for v in pointers.values()}
    rows = {n: v for n, v in seats.items() if not n.startswith("_") and isinstance(v, dict) and n in alive}
    active, rest = [], {}
    for name, row in rows.items():
        if row.get("_replaced_by") or name in retired:
            continue  # 1
        if name in pointers.values():  # 2
            active.append(name)
        elif row.get("role") in pointers or lineage(name) in pointed:
            continue
        else:
            rest.setdefault(lineage(name), []).append(name)
    unknown = {}
    for names in rest.values():  # 3
        if len(names) == 1 and _is_nano(names[0], rows[names[0]]) and names[0].endswith("#0"):
            active.append(names[0])
            continue
        why = f"확인 불가(현역 근거 없음: 포인터·은퇴 표시 0 · 생존 {', '.join(sorted(names))})"
        unknown.update(dict.fromkeys(names, why))
    return sorted(active), unknown
