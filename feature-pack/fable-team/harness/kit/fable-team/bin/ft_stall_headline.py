"""ft-stall-scan의 팀 헤드라인 나이 판정과 단계별 알림."""
import json
import os
import re
import time
from pathlib import Path
from typing import Any, Callable

HEADLINE_MIN = 15.0
SECOND_STAGE_MIN = 20.0
CLOCK = re.compile(r"^\s*(\d{2}):(\d{2})(?:\s|·|$)")
STATUS = re.compile(r"(?:✻\s+\d{2}:\d{2}|작업 중|오류\s+\d{2}:\d{2})")
IDLE = re.compile(r"\+\d+석 유휴\(✻\s+\d{2}:\d{2}\)")


def _path(root: Path, team: str) -> Path | None:
    if not team.startswith("m.") or not team[2:] or not re.fullmatch(r"[\w.-]+", team[2:]):
        return None
    return root / ".fable-team" / f"{team[2:]}-tick" / "HEADLINE.md"


def headline_age(root: Path, team: str, now: float) -> tuple[dict[str, Any] | None, str | None]:
    path = _path(root, team)
    if path is None:
        return None, None
    try:
        if not path.is_file():
            return None, "HEADLINE.md 없음" if not path.exists() else "HEADLINE.md 자리가 파일이 아님"
        stat = path.stat()
        with path.open("rb") as source:
            first = source.read(4096).decode("utf-8").splitlines()[0]
    except (OSError, UnicodeError, IndexError):
        return None, "HEADLINE.md 읽기 실패"
    match = CLOCK.match(first)
    if not match or int(match.group(1)) > 23 or int(match.group(2)) > 59:
        return None, "첫 줄 시각 없음 또는 꼴 틀림"
    cells = [cell.strip() for cell in first.split(" · ")]
    lead_cell = next((i for i, cell in enumerate(cells) if cell.startswith("팀장=")), None)
    if lead_cell is None or not any(STATUS.search(cell) for cell in cells[lead_cell:]):
        return None, "구조 없음"
    for cell in cells[lead_cell:]:
        if "=" not in cell:
            continue
        value = cell.split("=", 1)[1]
        if not STATUS.search(value) and not IDLE.search(value):
            return None, "구조 없음"
    stamp = time.localtime(stat.st_mtime)
    if (stamp.tm_hour, stamp.tm_min) != (int(match.group(1)), int(match.group(2))):
        return None, "시각 불일치"
    age = (now - stat.st_mtime) / 60
    if age < 0:
        return None, "미래 시각"
    return {"kind": "h", "team": team, "seat": "", "age": age,
            "date": time.strftime("%Y%m%d", stamp), "clock": f"{int(match.group(1)):02d}:{int(match.group(2)):02d}",
            "why": f"헤드라인 멈춤 · {first[:100]}"}, None


def team_masters(root: Path, team: str) -> list[str] | None:
    try:
        rows = json.loads((root / ".fable-team" / f"seats-{team}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return [seat for seat, row in rows.items() if not seat.startswith("_") and isinstance(row, dict)
            and row.get("role") == "master" and not row.get("_closed") and not row.get("_replaced_by")]


def find(root: Path, teams: list[dict[str, Any]], now: float, policy_stop: str | None = None) -> tuple[list[dict[str, Any]], int, list[str]]:
    found: list[dict[str, Any]] = []
    unknown = 0
    notes: list[str] = []
    if os.environ.get("FT_STALL_HEADLINE", "1") == "0":
        return found, unknown, notes
    if policy_stop:
        for team in teams:
            label = str(team.get("team") or "")
            if not label.startswith("m."):
                continue
            if policy_stop.startswith("ERROR"):
                unknown += 1
                notes.append(f"h? {label} 정책 정지 판정 불가 — {policy_stop}")
            else:
                notes.append(f"h? {label} 대상 밖(정책 정지)")
        return found, unknown, notes
    for team in teams:
        label = str(team.get("team") or "")
        if not label.startswith("m."):
            continue
        masters = team_masters(root, label)
        if masters is None:
            unknown += 1
            notes.append(f"h? {label} 헤드라인 판정 불가 — 명부 읽기 실패")
            continue
        if not masters:
            notes.append(f"h? {label} 대상 밖 — 현역 팀장 없음")
            continue
        item, error = headline_age(root, label, now)
        if error:
            unknown += 1
            notes.append(f"h? {label} 헤드라인 판정 불가 — {error}")
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
                    send: Callable[[str, str], tuple[int, bool]]) -> list[str]:
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
