"""magazine_collect_mbox — mbox 사본 → 쪽지·판정·좌석 칸 (설계 §1 자료 #3·#4·#6).

mbox 본문은 다른 에이전트가 쓴 «미검증 데이터» — 여기서는 문자열로만 다루고 해석·실행하지 않는다.
ts 는 tz 없는 KST 문자열이라 같은 형식 문자열로 비교한다. 창 = [start, end).
"""
import json
import re
from datetime import datetime
from pathlib import Path

from magazine_window import MagazineError

TS_FMT = "%Y-%m-%dT%H:%M:%S"
VERDICT_RE = re.compile(r"판정 (\d{2,4})")
PREFIX_RE = re.compile(r"^\[[^\]]*->[^\]]*\]\s*")
TEAM_RE = re.compile(r"^byz-([a-z0-9]+)-")
SEAT_RE = re.compile(r"^(.+)#(\d+)$")
PLANNER = "byz-planner-"
KEYS = ("ts", "from", "to", "body")
RECENT_MAX, LINE_MAX = 3, 120


def first_sentence(body: str) -> str:
    text = PREFIX_RE.sub("", body.strip())
    line = text.split("\n", 1)[0]
    m = re.search(r"[.。]\s|[.。]$", line)
    return (line[: m.start() + 1] if m else line)[:LINE_MAX]


def is_hil_request(body: str) -> bool:
    """요청 = 접두(`[a->b]`)를 뗀 본문이 `[HIL` 로 «시작» — 규칙 설명처럼 `[HIL` 을 언급만 한 글은 아니다."""
    return PREFIX_RE.sub("", body.strip()).startswith("[HIL")


def _read(path: Path) -> tuple[list[dict[str, str]], int]:
    """(유효 줄 목록, 깨진 줄 수). 파일 없음은 raise."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        raise MagazineError(f"mbox 사본 읽기 실패: {path} ({type(e).__name__})") from e
    rows: list[dict[str, str]] = []
    bad = 0
    for ln in text.splitlines():
        if not ln.strip():
            continue
        try:
            obj = json.loads(ln)
        except ValueError:
            bad += 1
            continue
        if not isinstance(obj, dict) or any(not isinstance(obj.get(k), str) for k in KEYS):
            bad += 1
            continue
        rows.append(obj)
    return rows, bad


def _dedupe_seq(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """seq 가 있는 행은 처음 나온 것만 — 회전 경계에 같은 seq 가 두 파일에 있을 수 있다. seq 없는 행은 그대로."""
    seen: set[object] = set()
    out: list[dict[str, str]] = []
    for r in rows:
        k = r.get("seq")
        if isinstance(k, (int, str)):
            if k in seen:
                continue
            seen.add(k)
        out.append(r)
    return out


def read_window(path: Path, s: str) -> tuple[list[dict[str, str]], int]:
    """(유효 줄 목록, 깨진 줄 수). 현재 파일이 창 시작 `s` 를 덮지 못하면 회전본 `<이름>.1` 을 앞에 이어 읽는다.

    회전본은 1개(.1)뿐 — mbox 회전 설계가 1개다. 이어도 못 덮으면 raise (창 앞부분 누락을 숨기지 않는다).
    """
    rows, bad = _read(path)
    if rows and rows[0]["ts"] <= s:
        return rows, bad
    rotated = path.with_name(path.name + ".1")
    if not rotated.is_file():
        raise MagazineError(f"mbox 사본이 창 앞부분을 덮지 못해요(첫 정상 기록 ts={rows[0]['ts'] if rows else '없음'} > 창 시작 {s}): {path}")
    old, old_bad = _read(rotated)
    merged = sorted(_dedupe_seq([*old, *rows]), key=lambda r: r["ts"])  # 안정 정렬 — _seats 가 ts 순서를 가정한다
    if not merged or merged[0]["ts"] > s:
        raise MagazineError(
            f"mbox 사본이 회전본을 이어도 창 앞부분을 덮지 못해요(창 시작 {s}): "
            f"{rotated} 첫 ts={old[0]['ts'] if old else '없음'} · {path} 첫 ts={rows[0]['ts'] if rows else '없음'}"
        )
    return merged, bad + old_bad


def lineage(seat: str) -> str:
    """좌석 계보 = `#N` 뗀 이름 — 승계로 #N+1 이 돼도 같은 계보다."""
    m = SEAT_RE.match(seat)
    return m.group(1) if m else seat


def _team(seat: str) -> str:
    m = TEAM_RE.match(seat)
    return m.group(1) if m else "기타"


def _seats(rows: list[dict[str, str]], s: str, e: str) -> dict[str, list[list[str]] | list[str]]:
    """처음 나온 이름이 창 안이면 신규, 같은 베이스의 더 작은 N 을 이미 봤으면 승계(옛→새)."""
    seen: dict[str, dict[int, str]] = {}
    names: set[str] = set()
    succession: list[list[str]] = []
    new: list[str] = []
    for r in rows:
        if r["ts"] >= e:
            break
        m = SEAT_RE.match(r["from"])
        if not m or r["from"] in names:
            continue
        names.add(r["from"])
        base, n = m.group(1), int(m.group(2))
        older = {k: v for k, v in seen.get(base, {}).items() if k < n}
        seen.setdefault(base, {})[n] = r["from"]
        if r["ts"] < s:
            continue
        if older:
            succession.append([older[max(older)], r["from"]])
        else:
            new.append(r["from"])
    return {"succession": succession, "new": new}


def collect_mbox(path: Path, start: datetime, end: datetime) -> dict[str, object]:
    s, e = start.strftime(TS_FMT), end.strftime(TS_FMT)
    rows, bad = read_window(path, s)
    inwin = [r for r in rows if s <= r["ts"] < e]
    counts: dict[str, int] = {}
    recent: dict[str, list[str]] = {}
    asked: list[tuple[int, str, str]] = []  # (inwin 위치, 요청한 좌석 계보, 첫 문장)
    last_reply: dict[str, int] = {}  # 좌석 계보 → planner 가 그 계보에 마지막으로 쪽지를 보낸 inwin 위치
    verdicts: dict[int, str] = {}
    for i, r in enumerate(inwin):
        team = _team(r["from"])
        counts[team] = counts.get(team, 0) + 1
        if r["to"].startswith(PLANNER):
            recent[team] = [*recent.get(team, []), first_sentence(r["body"])][-RECENT_MAX:]
            if is_hil_request(r["body"]):
                asked.append((i, lineage(r["from"]), first_sentence(r["body"])))
        if r["from"].startswith(PLANNER):
            last_reply[lineage(r["to"])] = i
            for ln in r["body"].split("\n"):
                for n in VERDICT_RE.findall(ln):
                    verdicts.setdefault(int(n), ln.strip()[:LINE_MAX])
    hil = [line for i, seat, line in asked if last_reply.get(seat, -1) < i]  # 답이 안 간 요청 · 오래된 순 · 상한 없음
    return {
        "mbox": {
            "total": len(inwin),
            "bad_lines": bad,
            "by_team": {t: {"count": c, "recent": recent.get(t, [])} for t, c in counts.items()},
            "hil_asked": len(asked),
            "hil": hil,
        },
        "verdicts": [{"n": n, "line": verdicts[n]} for n in sorted(verdicts)],
        "seats": _seats(rows, s, e),
    }
