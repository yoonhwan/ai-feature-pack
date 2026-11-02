# pyright: basic
"""r1290 — 팀 헤드라인 좌석 칸 초안 (ft_stall_scan 이 처리·저장을 끝낸 뒤 부른다).

칸 값 = 이번 scan 이 이미 읽은 좌석 캐시(Seats.info: jsonl 턴 경계 + 마지막 assistant 기록의 API 오류 표식)뿐이다 —
화면(capture-pane) 읽기 0 · 새 외부 호출 0 · 기록 0(파일 1개 덮어쓰기).
파일 = `.fable-team/state/<팀>-tick/HEADLINE-seats.txt`(팀 이름의 «m.» 앞머리를 뗀다 · r1289 와 같은 규칙 · 늘 1줄 · FT_HEADLINE_SEATS=0 이면 초안 0).
읽는 꼴 = parse(1줄 → {이름: 칸}) — 쓰는 꼴과 같은 모듈에 둔다(판정 3240: 읽는 쪽 TAB 꼴과 어긋나 좌석 칸이 전부 «?» 로 비었다).
"""
from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Any

CELL_MAX = 300  # 좌석 칸 합 상한 — 팀장 «하는 일»·카드 칸에 100자를 남긴다(RULE §1)
MARK = "✻"
UNDECIDED = "판정 불가(jsonl 없음)"
NANO = re.compile(r"^byz-(?P<team>[^-]+)-nano-(?P<slug>.+?)#(?P<n>\d+)$")
TEAMED = re.compile(r"^byz-[^-]+-(?P<role>[^-]+)-.+?#(?P<n>\d+)$")
TAIL = re.compile(r"^(?P<role>[^-]+)#(?P<n>\d+)$")
TOKEN = re.compile(r"^[a-z]{0,3}[0-9]+[a-z]?$")
FOLDER = re.compile(r"^[\w.-]+$")
SEP, DRAFT = " · ", re.compile(r"^\d{2}:\d{2} 초안$")  # 초안 1줄의 칸 구분 · 머리(«HH:MM 초안»)
LEAD, PAIR = re.compile(r"^팀장\((?P<cell>.*)\)$"), re.compile(r"^(?P<name>[^=()]+)=\?\((?P<cell>.*)\)$")
FOLDED = re.compile(r"^\+\d+석 유휴\(.*\)$")


def short_name(seat: str) -> str:
    """칸 이름(5): 나노 = 팀 이름 낱말을 뗀 뒤 «r1228·l101·k4» 꼴 첫 낱말 · 없으면 slug 앞 20자 · 그 밖 = «<역할>#N»."""
    match = NANO.match(seat)
    if match:
        words = [word for word in match.group("slug").split("-") if word]
        if words and words[0] == match.group("team"):
            words = words[1:]
        return (words[0] if words and TOKEN.match(words[0]) else "") or "-".join(words)[:20] or seat
    match = TEAMED.match(seat) or TAIL.match(seat)
    return f"{match.group('role')}#{match.group('n')}" if match else seat


def parse(text: str) -> tuple[dict[str, str], bool]:
    """초안 1줄(line 이 쓴 꼴) → ({이름: 칸}, 접힘 묶음 있음) · 꼴이 다르면 ({}, False)(W1·W2·W6·W7).
    칸 안에 괄호가 들어가므로(«판정 불가(jsonl 없음)») 첫 «)» 에서 끊지 않고 줄 끝까지 받는다(변이 ⑬)."""
    rows = [row for row in text.splitlines() if row.strip()]
    parts = rows[0].strip().split(SEP) if len(rows) == 1 else []
    if len(parts) < 2 or not DRAFT.match(parts[0]):
        return {}, False
    out: dict[str, str] = {}
    folded = False
    for part in parts[1:]:
        if FOLDED.match(part):
            folded = True
            continue
        lead, pair = LEAD.match(part), None
        if lead is None and (pair := PAIR.match(part)) is None:
            return {}, False
        name, value = ("팀장", lead.group("cell")) if lead else (pair.group("name").strip(), pair.group("cell"))
        if not name or not (value := value.strip()):
            return {}, False
        out[name] = value
    return out, folded


def clock(stamp: float | None, now: float) -> str:
    """epoch → «HH:MM»(로컬) · 다른 날 값은 «MM-DD HH:MM»(하루 넘은 값) · 없으면 «-»."""
    if stamp is None:
        return "-"
    at, today = time.localtime(stamp), time.localtime(now)
    return time.strftime("%m-%d %H:%M" if (at.tm_year, at.tm_yday) != (today.tm_year, today.tm_yday) else "%H:%M", at)


def cell(info: dict[str, Any] | None, now: float) -> str:
    """좌석 캐시 1개 → 칸: 작업 중 · 로그아웃 · 오류 · ✻ · 판정 불가.
    오류 = 마지막 턴의 마지막 assistant 기록이 API 오류(last_turn.err) — 정상 턴이 그 뒤에 끝났으면 오류가 아니다."""
    if not info or not info.get("path"):
        return UNDECIDED  # jsonl 없는 좌석(codex·pi) = 턴 경계를 못 읽는다(알려진 한계)
    state = str(info.get("state") or "")
    if state in ("WORKING", "PENDING"):
        return "작업 중"
    if state == "LOGGEDOUT":
        return f"로그아웃 {clock(info.get('end'), now)}"
    if state == "IDLE":
        if info.get("err"):
            return f"오류 {clock(info.get('err'), now)}"
        return UNDECIDED if info.get("end") is None else f"{MARK} {clock(info.get('end'), now)}"
    return UNDECIDED


def _rank(text: str) -> int:
    """칸 정렬 순위 = 작업 중 → 오류 → 로그아웃 → 판정 불가 → ✻(늦은 순)."""
    return 0 if text == "작업 중" else 1 if text.startswith("오류 ") else 2 if text.startswith("로그아웃 ") else 3 if text == UNDECIDED else 4


def _fit(cells_list: list[str], limit: int) -> list[str]:
    """좌석 칸 합이 상한을 넘으면 ✻ 칸을 오래된 것부터 «+N석 유휴(✻ 가장 늦은 HH:MM)» 하나로 접는다."""
    items = list(cells_list)
    if len(" · ".join(items)) <= limit:
        return items
    idle = [index for index, text in enumerate(items) if f"({MARK} " in text]
    for count in range(2, len(idle) + 1):  # 접는 칸 수(오래된 쪽부터)
        start = idle[len(idle) - count]
        found = re.search(r"\(" + MARK + r" (.+)\)$", items[start])
        trial = items[:start] + [f"+{count}석 유휴({MARK} {found.group(1) if found else '-'})"]
        if len(" · ".join(trial)) <= limit:
            return trial
    return items


def cells(team: dict[str, Any], seats: Any, now: float, live: set[str] | None = None, limit: int = CELL_MAX) -> list[str]:
    """팀 1개 → 칸 목록(팀장 먼저 · 좌석 = «<이름>=?(<칸>)» · tmux 에 없는 명부 현역 = «세션 없음»)."""
    master = str(team.get("master") or "")
    rows: list[tuple[str, str, float | None]] = []
    for seat in [master] + sorted(str(s) for s in (team.get("seats") or ()) if s != master):
        if live is not None and seat not in live:
            rows.append((seat, "세션 없음", None))
            continue
        info = seats.info(seat) or {}
        rows.append((seat, cell(info, now), info.get("end")))
    rows[1:] = sorted(rows[1:], key=lambda row: (_rank(row[1]), -(row[2] or 0.0) if _rank(row[1]) == 4 else 0.0, row[0]))
    lead = f"팀장({rows[0][1] if rows else UNDECIDED})"
    return [lead] + _fit([f"{short_name(seat)}=?({text})" for seat, text, _ in rows[1:]], max(1, limit - len(lead) - 3))


def line(team: dict[str, Any], seats: Any, now: float, live: set[str] | None = None, limit: int = CELL_MAX) -> str:
    """팀 1개 → 초안 1줄 «HH:MM 초안 · 팀장(<칸>) · <이름>=?(<칸>) · …»."""
    return f"{clock(now, now)} 초안 · " + " · ".join(cells(team, seats, now, live, limit))


def folder(root: Path, team: str) -> Path | None:
    """팀 이름 → `.fable-team/state/<팀>-tick` («m.» 앞머리를 뗀다 · 이름이 이상하면 None)."""
    name = str(team or "").removeprefix("m.")
    return root / ".fable-team" / "state" / f"{name}-tick" if name and FOLDER.match(name) else None


def write(folder_path: Path, text: str) -> int | None:
    """같은 폴더 임시 파일 → os.replace(덮어쓰기 · 늘 1줄 · 일반 파일) · 실패 = errno(호출 쪽이 «초안 쓰기 실패» 1줄)."""
    try:
        folder_path.mkdir(parents=True, exist_ok=True)
        temporary = folder_path / ".HEADLINE-seats.tmp"
        _ = temporary.write_text(text + "\n", encoding="utf-8")
        os.replace(temporary, folder_path / "HEADLINE-seats.txt")
    except OSError as error:
        return error.errno
    return None


def draft(root: Path, teams: list[dict[str, Any]], seats: Any, live: set[str], now: float, limit: int = CELL_MAX) -> list[str]:
    """팀마다 초안 1줄을 덮어쓴다 → 실패한 팀의 «초안 쓰기 실패 <팀> <errno>» 1줄들(그 팀만 · 다른 팀 계속 · 판정·발신 영향 0)."""
    if os.environ.get("FT_HEADLINE_SEATS", "1") == "0":
        return []
    notes: list[str] = []
    for team in teams:
        name = str(team.get("team") or "")
        folder_path = folder(root, name)
        if team.get("diag") != "OK" or not team.get("master") or folder_path is None:
            continue  # 명부 _master 빈 팀·깨진 명부 = 초안 0(대상 밖)
        errno = write(folder_path, line(team, seats, now, live, limit))
        if errno is not None:
            notes.append(f"초안 쓰기 실패 {name} {errno}")
    return notes
