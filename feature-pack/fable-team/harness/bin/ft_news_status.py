"""ft_news_status — 뉴스에 붙이는 «팀·세션 상태 + 해야 할 일» 절 (R209 · 판정 1795·1430·496). 쓰는 쪽은 ft_news_ledger.py.

재료 = board 스냅샷 JSON 한 장(`.fable-team/state/board/<날짜>/HHMMSS-*.json` · ft-board-publish 가 5분마다 만든다) 읽기만 — 뉴스 안에서
`ft-board.py collect/teams/render` 를 돌리지 않는다(실측 40~60 s · 7초 룰). 스냅샷 0장·해석 실패 = raise(#0 RULE).
스냅샷이 주기 2배보다 오래되면 절 맨 위에 «(세션 상태 스냅샷 HH:MM · 갱신 안 됨)» 한 줄 + stderr ERROR.
digest = 정지 분(分)을 뺀 본문의 sha1 — 분이 흐르는 것만으로 «바뀜» 이 되지 않게(판정 1430 «바뀐 것만»).
env: FT_ROOT · FT_NEWS_STATUS_INTERVAL(초 · 기본 1800 · 0 = 절·주기·경보 전부 끔 = 옛 동작)
"""
import hashlib
import json
import logging
import os
import re
from datetime import datetime, timedelta
from pathlib import Path

from ft_news_ledger_text import Block

LOG = logging.getLogger("ft_news_ledger")
SNAP = re.compile(r"^(\d{6})-[0-9a-f]+\.json$")
WAIT = re.compile(r"추정: (\S+) 에 마지막 발신 .*?기록상 (이후 \S+ 회신 없음|회신 있음)")
TITLE = "*팀·세션 상태 + 해야 할 일*"
MAX_CARDS, TITLE_CHARS = 3, 40
ERROR_CHARS = 80  # error 팀 사유는 한 줄 80자까지만 — 뉴스 줄이 사유문에 먹히지 않게
DEFAULT_INTERVAL_S = 1800


def interval_s() -> int:
    return int(os.environ.get("FT_NEWS_STATUS_INTERVAL", DEFAULT_INTERVAL_S))


def latest_snapshot(root: Path) -> tuple[Path, datetime]:
    base = root / ".fable-team" / "state" / "board"
    for day in sorted((d for d in base.glob("????-??-??") if d.is_dir()), reverse=True):
        if snaps := sorted(p for p in day.iterdir() if SNAP.match(p.name)):
            return snaps[-1], datetime.strptime(f"{day.name} {SNAP.match(snaps[-1].name)[1]}", "%Y-%m-%d %H%M%S")
    raise RuntimeError(f"board 스냅샷 0장({base}) — 상태 절을 만들 수 없다(대체 0)")


def _who(name: str) -> str:
    short = name.removeprefix("byz-")
    parts = short.split("-")
    return f"{parts[1]}({short})" if len(parts) > 1 else short


def _waiting(seat: dict) -> str:
    m = WAIT.search(seat.get("wait") or "")
    return f"{_who(m[1])} 회신" if m and "회신 없음" in m[2] else "없음"


def _stalls(team: dict, minutes: bool) -> str:
    out, unknown = [], 0
    for mins, seat, _hhmm, _why in team.get("stalled", []):
        if not mins.endswith("분"):
            unknown += 1
            continue
        out.append(f"{_who(seat)}: {mins + ' · ' if minutes else ''}기다리는 것 = {_waiting(team['seats'].get(seat, {}))}")
    out += [f"확인 불가 {unknown}석"] if unknown else []
    return "; ".join(out) or "없음"


def _title(raw: str) -> str:
    return raw.split(" — ", 1)[-1].strip()[:TITLE_CHARS]


def _todo(team: dict) -> str:
    cards = sorted(team.get("progress", {}).values(), key=lambda c: not c.get("seats"))
    titles = [_title(c["title"]) for c in cards[:MAX_CARDS]]
    nxt = f"다음 대기: {_title(team['queue'][0]['title'])}" if team.get("queue") else "다음 대기: 없음"
    return " · ".join([*(titles or ["진행 카드 없음"]), nxt])


def _team_line(team: dict, minutes: bool) -> str:
    """한 팀 한 줄 — 그 팀만 수집 실패했으면 사유 한 줄(team_or_error 꼴).

    error 팀에서 `t['seats']` 를 읽으면 KeyError 로 절 전체가 «원천 없음» 이 된다(r649).
    """
    if team.get("error"):  # 그 팀만 못 읽음 — 다른 팀 줄은 불변
        return f"• {team['label']} — 못 읽음: {str(team['error'])[:ERROR_CHARS]}"
    worked = sum(1 for s in team["seats"].values() if s.get("working"))
    stalls, todo = _stalls(team, minutes), _todo(team)
    return f"• {team['label']} — 일함 {worked} · 정지 {stalls} / 해야 할 일: {todo}"


def _lines(data: dict, minutes: bool) -> list[str]:
    return [_team_line(t, minutes) for t in data["teams"]]


def status_block(root: Path, now: datetime) -> tuple[Block, str]:
    """(절 블록, digest). 스냅샷 없음·깨짐 = raise."""
    path, taken = latest_snapshot(root)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        lines, plain = _lines(data, True), _lines(data, False)
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        raise RuntimeError(f"board 스냅샷 해석 실패 {path.name}: {e!r}") from e
    head: list[str] = []
    if now - taken > timedelta(seconds=2 * interval_s()):
        head = [f"(세션 상태 스냅샷 {taken:%H:%M} · 갱신 안 됨)"]
        plain = [*head, *plain]
        LOG.error("세션 상태 스냅샷이 오래됐다: %s (%s) — 뉴스 절에 «갱신 안 됨» 표시", path.name, taken)
    return (TITLE, [*head, *lines]), hashlib.sha1("\n".join(plain).encode("utf-8")).hexdigest()


def status_or_none(root: Path, now: datetime):
    """status_block 실패 = None(ERROR 로그 — 원장 뉴스는 막지 않는다) · interval 0 = 끔."""
    if interval_s() <= 0:
        return None
    try:
        return status_block(root, now)
    except (RuntimeError, OSError) as e:
        LOG.error("상태 절 실패: %s", e)
        return None


def last_status(state: Path) -> tuple[str, datetime] | None:
    f = state / "status.sha"
    if not f.exists():
        return None
    digest, day, hhmm = f.read_text(encoding="utf-8").split()
    return digest, datetime.strptime(f"{day} {hhmm}", "%Y-%m-%d %H:%M")


def mark_status(state: Path, digest: str, now: datetime) -> None:
    (state / "status.sha").write_text(f"{digest} {now:%Y-%m-%d %H:%M}\n", encoding="utf-8")
