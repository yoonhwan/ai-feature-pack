#!/usr/bin/env python3
"""ft_seat_turn.py — 좌석 jsonl «턴 경계» 판정기 하나(r504). `ft-seat-status.sh turn` 의 heredoc 판정 본문을 그대로 옮겼다(동작 변경 0).

판정(BOOT 18 · Seatbelt 1.1): Claude Code jsonl 은 턴이 끝날 때 system/turn_duration 을 찍는다.
  STATE = 마지막 turn_duration 뒤에 user/assistant 있으면 WORKING · 없으면 IDLE · 뒤에 queue-operation enqueue 만 있으면 PENDING
          · 창(최대 tail_bytes)에 turn_duration 이 없어도 user/assistant 가 있으면 WORKING · 둘 다 없으면 UNKNOWN
  REPORTED = 그 턴의 assistant tool_use 입력에 `mbox.sh send <master>` 문자열 실재(yes/no) · master 미상이면 '-'
쓰는 곳: 셸 도구(`ft-seat-status.sh turn`) = CLI · 뉴스 HTML·지도 = turns() — 좌석 → 최신 jsonl 을 한 번에(find_jsonls) 찾고 같은 프로세스에서 꼬리만 읽는다
(좌석별 하위 프로세스 0 · 부하 15~56 에서 좌석당 셸 1회가 상한을 넘겨 «확인 불가» 가 되던 꼴).

  python3 ft_seat_turn.py <jsonl>     → 탭 5칸 STATE TURN_END_ISO DURATION_MS REPORTED READ_BYTES
  env: FT_SEAT_TAIL_BYTES(기본 1MB) · FT_SEAT_TAIL_START(기본 64KB) · MASTER(기본 '') · NEED_ENDS(1 = 상태 전용 · 2 = REPORTED 까지 · 기본 1)
"""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_api_outage_util import find_jsonls  # noqa: E402

TAIL_BYTES, TAIL_START = 1 << 20, 1 << 16
Row = tuple[str, str, str, str, int]


def _records(data: bytes) -> list[dict]:
    recs = []
    for line in data.split(b"\n"):
        if not line.strip():
            continue
        try:
            recs.append(json.loads(line))
        except ValueError:  # 손상 행은 건너뛴다 (마지막 미완 행 포함)
            continue
    return recs


def _window(path: str, cap: int, start: int, need_ends: int, status_only: bool) -> tuple[list[dict], list[int], int, bool]:
    """끝 start 부터 — 턴 끝 레코드 need_ends 개를 찾을 때까지 앞쪽으로 2배씩(최대 cap). 앞서 읽은 꼬리는 다시 읽지 않는다.
    (레코드, 끝 위치들, 읽은 바이트, 상태 전용 조기 WORKING 여부)."""
    win, raw, got = min(start, cap), b"", 0
    size = os.path.getsize(path)
    while True:
        want = min(win, size)
        with open(path, "rb") as fh:
            fh.seek(size - want)
            raw = fh.read(want - got) + raw
        got = want
        data = raw.split(b"\n", 1)[1] if size > want and b"\n" in raw else (b"" if size > want else raw)  # 잘린 첫 줄 버림
        recs = _records(data)
        ends = [i for i, r in enumerate(recs) if r.get("type") == "system" and r.get("subtype") == "turn_duration"]
        if len(ends) >= need_ends or want >= size or want >= cap:
            return recs, ends, got, False
        # 상태 전용: 끝 레코드가 창 밖이어도 창 안에 user/assistant 가 있으면 «그 끝 뒤» 기록 = 열린 턴 WORKING (턴 끝 시각은 불요)
        if status_only and not ends and any(r.get("type") in ("user", "assistant") for r in recs):
            return recs, ends, got, True
        win = min(win * 2, cap)


def _reported(recs: list[dict], prev: int, last: int, master: str) -> str:
    if not master:
        return "-"
    needle = "mbox.sh send " + master
    for r in recs[prev + 1:last]:
        content = (r.get("message") or {}).get("content") if r.get("type") == "assistant" else None
        if isinstance(content, list) and any(isinstance(b, dict) and b.get("type") == "tool_use"
                                             and needle in json.dumps(b.get("input", {}), ensure_ascii=False) for b in content):
            return "yes"
    return "no"


def turn_of_file(path: str, tail_bytes: int = TAIL_BYTES, tail_start: int = TAIL_START, master: str = "", status_only: bool = True) -> Row:
    """(STATE, TURN_END_ISO, DURATION_MS, REPORTED, READ_BYTES) — 칸 값은 셸 출력 글자 그대로('-' 포함)."""
    recs, ends, got, early = _window(path, tail_bytes, tail_start, 1 if status_only else 2, status_only)
    if early:
        return "WORKING", "-", "-", "-", got
    if not ends:  # 끝 레코드 0개 — 창 안에 user/assistant 가 있으면 «마지막 끝 뒤의 기록» = 열린 턴(긴 턴·첫 턴 · 두 모드 공통)
        return ("WORKING" if any(r.get("type") in ("user", "assistant") for r in recs) else "UNKNOWN"), "-", "-", "-", got
    last, prev = ends[-1], (ends[-2] if len(ends) > 1 else -1)
    end, state, pending = recs[last], "IDLE", False
    for r in recs[last + 1:]:
        t = r.get("type")
        if t in ("user", "assistant"):
            state = "WORKING"
            break
        if t == "queue-operation":
            pending = r.get("operation") == "enqueue"
    if state == "IDLE" and pending:
        state = "PENDING"
    return state, str(end.get("timestamp", "-")), str(end.get("durationMs", "-")), _reported(recs, prev, last, master), got


def turns(seats: list[str], tmux: str, projects: Path) -> dict[str, tuple[str, str]]:
    """좌석들 → (STATE, 사유) — find_jsonls 1회 + 좌석마다 꼬리 읽기(상태 전용) · 못 찾음 = («?», «jsonl 없음») · 읽기 실패 = («?», «읽기 실패»).
    «?» 는 «확인 불가» 다 — 쉬는 것으로 보지 않는다(r490)."""
    found = find_jsonls(list(seats), tmux, projects)
    out: dict[str, tuple[str, str]] = {}
    for s in seats:
        if s not in found:
            out[s] = ("?", "jsonl 없음")
            continue
        try:
            out[s] = (turn_of_file(found[s])[0], "")
        except OSError:  # 찾은 뒤 지워진 파일 등
            out[s] = ("?", "읽기 실패")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    e = os.environ
    row = turn_of_file(argv[0], int(e.get("FT_SEAT_TAIL_BYTES", TAIL_BYTES)), int(e.get("FT_SEAT_TAIL_START", TAIL_START)),
                       e.get("MASTER", ""), e.get("NEED_ENDS", "1") == "1")
    print("%s\t%s\t%s\t%s\t%d" % row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
