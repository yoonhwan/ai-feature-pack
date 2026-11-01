#!/usr/bin/env python3
# pyright: basic
"""ft_card_assign_pause.py — 배정 감시(ft_card_assign_watch.py)의 팀 정지 표식·사람 보류 1회 표 (r1291 · Issue #5901 · 판정 3059·3104 선택지 A).
팀 정지 표식 = <루트>/.fable-team/state/<팀>-tick/PAUSED 일반 파일 1줄 «판정 <N> · <YYYY-MM-DDTHH:MM[:SS]> · <사유 10자+>» · 쓰기 = team_pause · 지우기 = team_resume(planner [재개]) · 손으로 지워도 같다.
team_paused(R, team) → (on|none|q, 설명, 표식 시각, 판정 N) · 꼴 틀림·읽기 실패·폴더 = q(판정 불가 · 조용한 «정지 중» 0 · 하드 룰 20).
held_once(R, stem, reason, since) = 첫 경보가 QUEUED 로 나간 «사람» 카드인가(card-assign/held-once.json · 키 stem·사유·since) · held_add 는 발신 성공 뒤에만 · held_prune 은 닫힌 카드·사유 바뀐 키를 지운다.
seen = card-assign/paused-seen.json(정지를 본 팀) · notice = card-assign/paused-notice.json(24시간 넘은 정지 알림 · 날짜 키 · 옛 날짜 키 지움)."""
import json
import os
import re
import time
from pathlib import Path

from ft_directive_watch import Undecided

DAY_S = 24 * 3600
FORM = re.compile(r"판정 (\d+) · (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?) · (.{10,})")
TEAM = re.compile(r"[\w.-]+")


def sdir(R: Path) -> Path:
    return R / ".fable-team/state/card-assign"


def parse_iso(s: str) -> float | None:
    for f in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            return time.mktime(time.strptime(s, f))
        except ValueError:
            pass
    return None


def jload(f: Path) -> dict:
    try:
        j = json.loads(f.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except ValueError as e:
        raise Undecided(f"{f.name} 손상 {e.__class__.__name__}")
    if not isinstance(j, dict):
        raise Undecided(f"{f.name} 꼴 아님")
    return j


def jsave(f: Path, j: dict) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_name(f".{f.name}.tmp-{os.getpid()}")
    tmp.write_text(json.dumps(j, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(f)


def team_paused(R: Path, team: str) -> tuple[str, str, float, str]:
    if not TEAM.fullmatch(team):
        return "q", f"팀 이름 꼴 아님({team[:20]})", 0.0, ""
    f = R / ".fable-team/state" / f"{team}-tick" / "PAUSED"
    if not os.path.lexists(f):
        return "none", "", 0.0, ""
    if not f.is_file() or f.is_symlink():
        return "q", "표식 자리가 일반 파일 아님", 0.0, ""
    try:
        text = f.read_text(encoding="utf-8").strip()
    except (OSError, ValueError) as e:
        return "q", f"표식 읽기 실패 {e.__class__.__name__}", 0.0, ""
    m = FORM.fullmatch(text)
    t = parse_iso(m.group(2)) if m else None
    if not m or t is None:
        return "q", "표식 꼴 아님(판정 <N> · <시각> · <사유 10자+>)", 0.0, ""
    return "on", m.group(3), t, m.group(1)


def team_pause(R: Path, team: str, verdict: str, reason: str, now: float) -> int:
    if not TEAM.fullmatch(team) or not verdict.isdigit() or len(reason.strip()) < 10:
        print(f"REJECT team-pause — <팀> --verdict <판정 번호> --reason <사유 10자+> 필수 (받은 값: {team} {verdict} {len(reason.strip())}자)")
        return 2
    f = R / ".fable-team/state" / f"{team}-tick" / "PAUSED"
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_name(f".PAUSED.tmp-{os.getpid()}")
    tmp.write_text(f"판정 {verdict} · {time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(now))} · {' '.join(reason.split())}\n", encoding="utf-8")
    tmp.replace(f)
    print(f"정지 표식 {f}")
    return 0


def team_resume(R: Path, team: str) -> int:
    if not TEAM.fullmatch(team):
        print(f"REJECT team-resume — 팀 이름 꼴 아님({team[:20]})")
        return 2
    (R / ".fable-team/state" / f"{team}-tick" / "PAUSED").unlink(missing_ok=True)
    print(f"정지 표식 지움 {team}")
    return 0


def hkey(stem: str, reason: str, since: float) -> str:
    return f"{stem}\t{reason}\t{int(since)}"


def held_once(held: dict, stem: str, reason: str, since: float) -> bool:
    return hkey(stem, reason, since) in held


def held_add(R: Path, stem: str, reason: str, since: float) -> None:
    f = sdir(R) / "held-once.json"
    jsave(f, {**jload(f), hkey(stem, reason, since): 1})


def held_prune(held: dict, ledger: dict, gone: set) -> dict:
    """열린 «사람» 카드의 현재 (사유·since) 와 같은 키만 남긴다 — 닫힌 카드·사유 바뀜 = 지움."""
    def live(k: str) -> bool:
        stem, reason, since = k.split("\t")
        L = ledger.get(stem) or {}
        return stem not in gone and L.get("state") == "waiting" and L.get("reason") == reason and int(float(L.get("since") or 0)) == int(since)
    return {k: v for k, v in held.items() if live(k)}


def notice(R: Path, now: float, long: list[tuple[str, str]], send) -> list[str]:
    """24시간 넘은 정지 — 팀당 하루 1통 · send(text) → True 면 QUEUED(그때만 기록) · 옛 날짜 키는 지운다."""
    f, day, log = sdir(R) / "paused-notice.json", time.strftime("%Y-%m-%d", time.localtime(now)), []
    if not long:
        return log
    sent ={day: list(jload(f).get(day) or [])}
    for team, verdict in long:
        if team in sent[day]:
            continue
        if send(f"[정지 24시간] {team} 판정 {verdict} — 재개(team-resume) 또는 team-pause 다시 걸기"):
            sent[day].append(team)
            log.append(f"정지 24시간 1통 → planner · {team}")
        else:
            log.append(f"정지 24시간 발신 실패 · {team} · 다음 틱 다시")
    jsave(f, sent)
    return log
