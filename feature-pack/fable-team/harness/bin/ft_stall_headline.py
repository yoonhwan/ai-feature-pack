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
    if "·" not in first or not first.split("·", 1)[1].strip():
        return None, "화면 칸 없음"
    stamp = time.localtime(stat.st_mtime)
    if (stamp.tm_hour, stamp.tm_min) != (int(match.group(1)), int(match.group(2))):
        return None, "시각 불일치"
    age = (now - stat.st_mtime) / 60
    if age < 0:
        return None, "미래 시각"
    return {"kind": "h", "team": team, "seat": "", "age": age,
            "signature": f"{time.strftime('%Y-%m-%d', stamp)}:{first}",
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
    if policy_stop and not policy_stop.startswith("ERROR"):
        return found, unknown, notes
    for team in teams:
        label = str(team.get("team") or "")
        if not label.startswith("m."):
            continue
        if policy_stop:
            unknown += 1
            notes.append(f"h? {label} 헤드라인 판정 불가 — 정책 정지 판정 실패")
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
        elif item and item["age"] >= HEADLINE_MIN:
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


def headline_alerts(root: Path, found: list[dict[str, Any]], live: dict[str, int], now: float,
                    send: Callable[[str, str], int]) -> list[str]:
    path = root / ".fable-team/state/stall-scan.headline.json"
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
        team, sig = item["team"], item["signature"]
        old = state.get(team) if isinstance(state.get(team), dict) else {}
        if old.get("signature") != sig:
            old = {}
        stage = int(old.get("stage") or 0)
        if stage >= 2:
            continue
        if stage == 1 and item["age"] < SECOND_STAGE_MIN:
            continue
        if stage == 0 and item["age"] < HEADLINE_MIN:
            continue
        live_masters = [seat for seat in item["masters"] if seat in live]
        if stage == 0 and live_masters:
            targets, next_stage = item["masters"], 1
        else:
            if planner is None:
                planner = planner_desk(root)
            targets, next_stage = ([planner] if planner else []), 2
        if not targets:
            log.append(f"h? {team} planner desk 판정 불가 — 활성 role=desk 없음")
            continue
        level = "1단계" if next_stage == 1 else "2단계"
        body = f"[헤드라인 멈춤] {team} {level} · {item['age']:.0f}분 · {item['why']}"
        failures = [(to, send(to, body)) for to in targets]
        failed = next(((to, rc) for to, rc in failures if rc != 0), None)
        if failed:
            to, rc = failed
            log.append(f"act=h ERROR 발신 실패 rc={rc} to={to} team={team} — 다음 scan 재시도")
            continue
        state[team] = {"signature": sig, "stage": next_stage}
        log.append(f"act=h to={','.join(targets)} team={team} stage={next_stage} age={item['age']:.0f}")
    if log or state:
        _ = path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    return log
