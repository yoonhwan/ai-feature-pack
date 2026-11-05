"""ft-stall-scan의 팀 헤드라인 나이 판정과 단계별 알림.

r1323 — 이름·경로·명부가 «지금 꼴» 이다(계약 K1~K9):
K1 팀 이름 = load_teams 의 team 그대로(TEAMS.md 이름) · «m.» 앞머리는 한 번만 떼어 정규화 이름 n 을 만들고 그 뒤 전부 n 을 쓴다.
K2 경로 = ft_headline_seats.folder(root, n)/HEADLINE.md(경로 규칙 사본 0) · folder None = 판정 불가 1줄.
K3 팀장 = load_teams 가 읽은 그 명부(ft_team_lib.rosters 의 doc · v65 = seats.json)의 현역 role=master — seats-<팀>.json 을 따로 열지 않는다.
K4 정지 표식(ft_card_assign_pause.team_paused) on = 대상 밖 1줄(열기 0 · 발신 0) · q = 막지 않음 + WARN 1줄 · FT_STALL_PAUSED_SKIP=0 이면 검사 0.
K5 첫 칸이 «제0목표:» 로 시작하면 그 칸 하나만 떼고 시각·구조를 본다(거버넌스 R13).
K6 시각 대조 = |mtime − 첫 줄 HH:MM| ≤ 15분이면 정상 · 넘으면 «시각 불일치» 판정 불가 · 나이는 «첫 줄 시각» 기준(자정 규칙 그대로).
K7 구조는 나이를 막지 않는다 — 15분 초과면 구조와 무관하게 경보(why 에 «꼴 틀림: 사유») · 15분 이하 + 구조 틀림 = «구조 없음» 판정 불가.
K8 구조 = RULE §1 확인 정규식(카드 대기·진행·완성(오늘) · 팀장=) + 좌석 화면 칸 하나 이상.
K9 load_teams 의 master_stop(명부 _master 행 role=stop-ready) = 대상 밖 1줄(열기 0 · 발신 0).
"""
import json
import os
import re
import time
from pathlib import Path
from typing import Any, Callable

import ft_card_assign_pause as card_pause
import ft_headline_seats as headline_seats
from ft_stall_detect import all_stop, all_stop_note  # r1371 — 전팀 정지 표식(읽기 한 곳)
from ft_team_lib import rosters as team_rosters

HEADLINE_MIN = 15.0
SECOND_STAGE_MIN = 20.0
CLOCK = re.compile(r"^\s*(\d{2}):(\d{2})(?:\s|·|$)")
STATUS = re.compile(r"(?:✻\s+\d{2}:\d{2}|작업 중|오류\s+\d{2}:\d{2})")
IDLE = re.compile(r"\+\d+석 유휴\(✻\s+\d{2}:\d{2}\)")
HEAD = re.compile(r"^카드 대기 \d+·진행 \d+·완성\(오늘\) \d+ · 팀장=")  # RULE §1 확인 명령과 같은 정규식(K8)
ZERO_GOAL = "제0목표:"  # 거버넌스 R13 — 첫 칸은 목표 문장이지 시각이 아니다(K5)
SLACK_MIN = 15  # K6 — mtime 과 첫 줄 시각이 이만큼 넘게 벌어지면 «시각 불일치»


def _cells(first: str) -> list[str]:
    """첫 줄 → 칸 목록 · 첫 칸이 «제0목표:» 면 그 한 칸만 뗀다(K5 · 2칸 이상 0)."""
    cells = [cell.strip() for cell in first.split(" · ")]
    return cells[1:] if cells and cells[0].startswith(ZERO_GOAL) else cells


def _clock(cells: list[str]) -> tuple[int, int] | None:
    match = CLOCK.match(cells[0]) if cells else None
    if not match or int(match.group(1)) > 23 or int(match.group(2)) > 59:
        return None
    return int(match.group(1)), int(match.group(2))


def _structure(cells: list[str]) -> str | None:
    """시각 칸 뒤 «머리 전부» + 화면 칸(K8) — 화면 칸은 «팀장=» 칸까지 본다(좌석 0 팀은 팀장 칸에 적는다 · 동결 13-r3 · arch#209 반송 1/3).
    팀장 칸 밖에 좌석 칸이 있으면 그 칸들도 전부 STATUS|IDLE 이어야 한다."""
    rest = cells[1:]
    if not HEAD.match(" · ".join(rest)):
        return "머리(카드 대기·진행·완성(오늘) · 팀장=)"
    lead = next((i for i, cell in enumerate(rest) if cell.startswith("팀장=")), None)
    tail = rest[lead:] if lead is not None else rest
    if any(IDLE.search(cell) for cell in tail):
        return None
    seats = [cell for cell in tail if "=" in cell]
    if not seats or any(not STATUS.search(cell.split("=", 1)[1]) for cell in seats):
        return "좌석 화면 칸"
    return None


def _read_first(root: Path, team: str) -> tuple[str | None, float, str | None]:
    """경로(K2) → (첫 줄, mtime, 판정 불가 사유)."""
    folder = headline_seats.folder(root, team)
    if folder is None:
        return None, 0.0, "팀 이름 꼴 틀림"
    path = folder / "HEADLINE.md"
    try:
        if not path.is_file():
            return None, 0.0, "HEADLINE.md 없음" if not path.exists() else "HEADLINE.md 자리가 파일이 아님"
        with path.open("rb") as source:
            first = source.read(4096).decode("utf-8").splitlines()[0]
        return first, path.stat().st_mtime, None
    except (OSError, UnicodeError, IndexError):
        return None, 0.0, "HEADLINE.md 읽기 실패"


def headline_age(root: Path, team: str, now: float) -> tuple[dict[str, Any] | None, str | None]:
    """팀 1개 → (경보 항목, 판정 불가 사유) · 15분 초과면 구조와 무관하게 항목(K7)."""
    first, stamp_mtime, error = _read_first(root, team)
    if error or first is None:
        return None, error or "HEADLINE.md 읽기 실패"
    cells = _cells(first)
    clock = _clock(cells)
    if clock is None:
        return None, "첫 줄 시각 없음 또는 꼴 틀림"
    stamp = time.localtime(stamp_mtime)
    delta = (clock[0] * 60 + clock[1] - (stamp.tm_hour * 60 + stamp.tm_min) + 720) % 1440 - 720  # 자정 넘김
    if abs(delta) > SLACK_MIN:
        return None, "시각 불일치"
    age = (now - (stamp_mtime + delta * 60)) / 60  # 나이 = «첫 줄 시각» 기준(K6)
    if age < 0:
        return None, "미래 시각"
    shape = _structure(cells)
    if shape and age <= HEADLINE_MIN:
        return None, "구조 없음"
    why = f"헤드라인 멈춤 · {str(first)[:100]}" + (f" · 꼴 틀림: {shape}" if shape else "")
    return {"kind": "h", "team": team, "seat": "", "age": age,
            "date": time.strftime("%Y%m%d", stamp), "clock": f"{clock[0]:02d}:{clock[1]:02d}", "why": why}, None


def roster_docs(root: Path) -> dict[str, Any]:
    """load_teams 가 읽는 그 명부(ft_team_lib.rosters) → {팀 이름: 명부 본문} · 정규화 이름도 같은 본문(K1·K3)."""
    docs: dict[str, Any] = {}
    for roster in team_rosters(root):
        name, doc = str(roster.get("team") or ""), roster.get("doc")
        if name and isinstance(doc, dict):
            docs.setdefault(name, doc)
            docs.setdefault(name.removeprefix("m."), doc)
    return docs


def team_masters(doc: Any) -> list[str] | None:
    """명부 본문 → 현역 role=master 좌석들 · 명부가 없으면 None(판정 불가 · 조용한 0 금지)."""
    if not isinstance(doc, dict):
        return None
    return [seat for seat, row in doc.items() if not seat.startswith("_") and isinstance(row, dict)
            and row.get("role") == "master" and not row.get("_closed") and not row.get("_replaced_by")]


def _outside(root: Path, name: str, team: dict[str, Any]) -> tuple[list[str], str | None]:
    """K4·K9 — (남길 경고줄들, 막는 1줄|None). 막으면 HEADLINE 열기 0 · 발신 0."""
    block, warn = _pause_note(root, name)
    warnings = [warn] if warn else []
    if block:
        return warnings, block
    if team.get("master_stop"):  # K9 — 팀장이 정지 레디면 대상 밖
        return warnings, f"h? {name} 대상 밖 — 팀장 정지 레디"
    return warnings, None


def _pause_note(root: Path, team: str) -> tuple[str | None, str]:
    """정지 표식(K4) → (막는 줄|None, WARN 줄|''). on = 대상 밖 · q = 막지 않음 + WARN · none = 통과."""
    if os.environ.get("FT_STALL_PAUSED_SKIP", "1") == "0":
        return None, ""
    try:
        state, why, _at, _verdict = card_pause.team_paused(root, team)
    except Exception as error:  # noqa: BLE001 — 판정 불가도 막지 않는다(하드 룰 20)
        state, why = "q", f"판정 불가 {error.__class__.__name__}"
    if state == "on":
        return f"h? {team} 대상 밖(정지 표식)", ""
    return (None, f"WARN {team} 정지 표식 판정 불가 — 경보 보냄({why})") if state == "q" else (None, "")


def find(root: Path, teams: list[dict[str, Any]], now: float, policy_stop: str | None = None) -> tuple[list[dict[str, Any]], int, list[str]]:
    found: list[dict[str, Any]] = []
    unknown = 0
    notes: list[str] = []
    if os.environ.get("FT_STALL_HEADLINE", "1") == "0":
        return found, unknown, notes
    names = [(name, team) for team in teams if (name := str(team.get("team") or "").removeprefix("m."))]  # K1 정규화 1회
    if policy_stop:
        for name, _team in names:
            if policy_stop.startswith("ERROR"):
                unknown += 1
                notes.append(f"h? {name} 정책 정지 판정 불가 — {policy_stop}")
            else:
                notes.append(f"h? {name} 대상 밖(정책 정지)")
        return found, unknown, notes
    docs = roster_docs(root)
    for name, team in names:
        warn, block = _outside(root, name, team)
        notes.extend(warn)
        if block:  # K4·K9 — 대상 밖 1줄 · u 0
            notes.append(block)
            continue
        masters = team_masters(docs.get(name))
        if masters is None:
            unknown += 1
            notes.append(f"h? {name} 헤드라인 판정 불가 — 명부 읽기 실패")
            continue
        if not masters:
            notes.append(f"h? {name} 대상 밖 — 현역 팀장 없음")
            continue
        item, error = headline_age(root, name, now)
        if error:
            unknown += 1
            notes.append(f"h? {name} 헤드라인 판정 불가 — {error}")
        elif item and item["age"] > HEADLINE_MIN:
            item["masters"] = masters
            item["seat"] = str(team.get("master") or masters[0])
            found.append(item)
    return found, unknown, notes


def planner_desk(root: Path) -> str | None:
    try:
        seats = json.loads((root / ".fable-team/seats-planner.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    for seat, row in seats.items():
        if not seat.startswith("_") and isinstance(row, dict) and row.get("role") == "desk" and not row.get("_closed") and not row.get("_replaced_by"):
            return seat
    return None


def has_receipt(comm: Path, to: str, key: str) -> tuple[bool | None, str | None]:
    paths = (comm / "mailbox.log.jsonl", comm / "mailbox.log.jsonl.1")
    found_file = False
    for path in paths:
        if not path.exists():
            continue
        found_file = True
        try:
            with path.open("rb") as source:
                source.seek(0, os.SEEK_END)
                source.seek(max(0, source.tell() - 262144))
                lines = source.read().splitlines()
        except OSError as error:
            return None, f"발신 로그 읽기 실패({error.__class__.__name__})"
        for line in lines:
            try:
                row = json.loads(line)
            except (UnicodeError, ValueError):
                continue
            if row.get("from") == "ft-stall-scan" and row.get("to") == to and key in str(row.get("body") or ""):
                return True, None
    if not found_file:
        return None, "발신 로그 없음"
    return False, None


def send_with_receipt(comm: Path, to: str, key: str,
                      send: Callable[[str, str], tuple[int, bool]]) -> tuple[bool, str | None]:
    body = f"key={key}"
    rc, timed_out = send(to, body)
    if rc == 0:
        return True, None
    if not timed_out:
        return False, f"발신 실패 rc={rc}"
    present, error = has_receipt(comm, to, key)
    if error:
        return False, error
    if present:
        return True, None
    rc, timed_out = send(to, body)
    if rc == 0:
        return True, None
    if timed_out:
        present, error = has_receipt(comm, to, key)
        if error:
            return False, error
        if present:
            return True, None
    return False, f"발신 재시도 실패 rc={rc}"


def _latest_live_master(masters: list[str], live: dict[str, int]) -> str | None:
    alive = [seat for seat in masters if seat in live]
    return max(alive, key=lambda seat: (int(re.search(r"#(\d+)$", seat).group(1)) if re.search(r"#(\d+)$", seat) else -1, seat), default=None)


def headline_alerts(root: Path, comm: Path, found: list[dict[str, Any]], live: dict[str, int], now: float,
                    send: Callable[[str, str], tuple[int, bool]], stop: tuple[str, float | None] | None = None) -> list[str]:
    """r1371 — stop = (all_stop 상태, since 초) · None 이면 여기서 1회 읽는다 · on 이면 h 발신 0 + 보류 노트 1줄(상태 기록 0)."""
    mark, since = (stop[0], stop[1]) if stop else all_stop(root)[:2]
    path = root / ".fable-team/state/stall-headline.json"
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(state, dict):
            state = {}
    except (OSError, ValueError):
        state = {}
    planner: str | None = None
    log: list[str] = []
    for item in found:
        if item.get("kind") != "h":
            continue
        team = item["team"]
        if mark == "on":  # r1371 — 전팀 정지: 발신 0 + 노트 1줄 · 1·2단계 상태 기록 0(off 뒤 같은 사건이 그대로 살아난다)
            log.append(all_stop_note("h", team, since))
            continue
        h1 = f"h1:{team}:{item['date']}:{item['clock']}"
        h2 = f"h2:{team}:{item['date']}:{item['clock']}"
        if h2 in state:
            continue
        first = state.get(h1) if isinstance(state.get(h1), dict) else None
        if first and now - float(first.get("sent_at") or now) < SECOND_STAGE_MIN * 60:
            continue
        master = _latest_live_master(item["masters"], live)
        if first and now - float(first.get("sent_at") or now) >= SECOND_STAGE_MIN * 60:
            if planner is None:
                planner = planner_desk(root)
            to, key = planner, h2
        elif master:
            to, key = master, h1
        else:
            if planner is None:
                planner = planner_desk(root)
            to, key = planner, h2
        if not to:
            log.append(f"h? {team} planner desk 판정 불가 — 활성 role=desk 없음")
            continue
        level = "1단계" if key == h1 else "2단계"
        body = f"[헤드라인 멈춤] {team} {level} · {item['age']:.0f}분 · {item['why']} · key={key}"
        sent, error = send_with_receipt(comm, to, key, lambda _to, _body: send(to, body))
        if not sent:
            log.append(f"h? {team} 발신 판정 불가 — {error}")
            continue
        state[key] = {"sent_at": now}
        try:
            _ = path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
        except OSError:
            log.append(f"h? {team} 상태 기록 실패 — 적재 확인됨 · 다음 실행에서 로그 확인")
    return log
