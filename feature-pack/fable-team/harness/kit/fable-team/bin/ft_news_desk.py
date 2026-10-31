#!/usr/bin/env python3
"""ft_news_desk — 뉴스 틱마다 desk 세션 화면에 붙일 «전문» 3블록을 조립하고, 바뀐 틱에만 desk 로 relay 1통 (r1055 · Issue #4004).

relay 본문 = 직전에 보낸 전문 대비 «바뀐 칸» 요약 ≤ 2KB + 전문 경로 끝줄 · 바뀐 칸 0 = 쪽지 0 · 하루 12통 상한(r1229 · Issue #5341).
블록 = ①골 표(원장) ②팀별 표(명단·카드 흐름·명부·보드 스냅샷) ③오빠 손(h 목록·답 대기 질문·오늘 착지). 이 파일 = 조립·digest·좌석·relay.
①·② 재료 = ft_news_desk_blocks.py · ③ = ft_news_desk_oppa.py(파일 상한 200줄 분리). 블록 순서는 Q1=ⓐ(오빠 승인 본보기 그대로) · 그 밖 블록 0.
digest = 머리의 «분»을 지운 본문 sha1 — 같은 내용이면 relay 0(판정 1430 «바뀐 것만» · R4).
desk 좌석 = 명부(seats-planner.json) `_desk` 의 현역 — 못 찾으면 rc≠0 «판정 불가» 1줄 · 옛 이름으로 보내기 0(R5).
env: FT_ROOT · FT_DESK_HIL · FT_DESK_DECISION · FT_DESK_TOOL_TIMEOUT · FT_MBOX · FT_DESK_SEATS
     FT_DESK_STATE(기본 <루트>/.fable-team/state/news-desk) · FT_DESK_NOW · FT_DESK_LEDGER_* · FT_CARD_FLOW(blocks 가 읽는다)
"""
import hashlib
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ft_board_env as env  # noqa: E402
from ft_news_desk_blocks import (  # noqa: E402
    CLOCK, DOING_CHARS, LOG, TABLE_SEP, _run, _timeout, goal_block, snapshot, team_block,
)
from ft_news_desk_oppa import oppa_block  # noqa: E402

MAX_RELAY = 2048   # desk 쪽지 1통 상한(바이트 · r1229 K7 — 전문 9KB 를 붙이던 것)
LINE_MAX = 400     # 바뀐 칸 1줄 상한(바이트) — 긴 골 행 하나가 요약을 다 먹지 않게
DAY_CAP = 12       # 하루 desk 쪽지 상한(통 · 날짜 파일 relay-count-YYYYMMDD.txt)


def build(root: Path, now: datetime) -> str:
    head = [f"# 뉴스 전문 — {now:%m-%d %H:%M} (뉴스 틱 자동 생성 · 손글 0)"]
    return "\n\n".join(["\n".join(head), *("\n".join(b) for b in (goal_block(root), team_block(root, snapshot(root)), oppa_block(root, now)))]) + "\n"


def digest(text: str) -> str:
    """«분»만 다르고 같은 내용이면 같은 digest(R4 · 판정 1430)."""
    return hashlib.sha1(CLOCK.sub("HH:MM", text).encode("utf-8")).hexdigest()


def desk_seat(root: Path) -> str:
    """명부 `_desk` 의 현역 좌석 — 없음·닫힘·대체 = RuntimeError(R5: 옛 이름으로 보내지 않는다)."""
    path = Path(os.environ.get("FT_DESK_SEATS") or root / ".fable-team" / "seats-planner.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        seat = data["_desk"]
        row = data[seat]
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise RuntimeError(f"명부에서 desk 좌석을 못 찾았다({path.name}): {e}") from e
    if not isinstance(row, dict) or row.get("_closed") or row.get("_replaced_by"):
        raise RuntimeError(f"명부 desk 좌석 {seat} 이 현역이 아니다(닫힘·대체)")
    return seat


def changed(prev: str, text: str) -> list[str]:
    """직전에 보낸 전문에 없던 줄 = 바뀐 칸 «[절] 줄»(분 무시 · 머리·빈 줄 제외 · r1229 K7)."""
    old = {CLOCK.sub("HH:MM", ln) for ln in prev.splitlines()}
    out, sec = [], ""
    for ln in text.splitlines():
        if ln.startswith("## "):
            sec = ln[3:].strip()
        if ln.strip() and not ln.startswith("# ") and not TABLE_SEP.match(ln.strip()) and CLOCK.sub("HH:MM", ln) not in old:
            out.append(f"[{sec}] {ln.strip()}")
    return out


def _cut(s: str, n: int) -> str:
    return s.encode("utf-8")[:n].decode("utf-8", "ignore")


def brief(rows: list[str], now: datetime, full: Path) -> str:
    """desk 쪽지 본문 = 바뀐 칸 요약 + 전문 경로 끝줄 · 합계 ≤ MAX_RELAY 바이트(r1229 R4)."""
    head, tail = f"뉴스 바뀐 칸 {len(rows)}개 · {now:%H:%M}", f"전문: {full}"
    body, used = [head], len(head.encode()) + len(tail.encode()) + 2 + 64   # 64 = «외 N칸» 자리
    for i, row in enumerate(rows):
        line = _cut(row, LINE_MAX)
        if used + len(line.encode()) + 1 > MAX_RELAY:
            body.append(f"… 외 {len(rows) - i}칸(전문 참조)")
            break
        body.append(line)
        used += len(line.encode()) + 1
    return "\n".join([*body, tail]) + "\n"


def _count_path(state: Path, now: datetime) -> Path:
    return state / f"relay-count-{now:%Y%m%d}.txt"


def _sent_today(state: Path, now: datetime) -> int:
    try:
        return int(_count_path(state, now).read_text(encoding="utf-8").strip() or 0)
    except (OSError, ValueError):
        return 0


def relay(root: Path, path: Path, seat: str, summary: str) -> None:
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    done = _run(["bash", mbox, "relay", seat, "ft-news-desk", str(path), summary], _timeout("FT_DESK_TOOL_TIMEOUT") * 2)
    if done.returncode != 0:
        raise RuntimeError(f"desk relay 실패 rc={done.returncode} {(done.stderr or done.stdout).strip()[:DOING_CHARS]}")


def tick() -> int:
    root = env.ft_root()
    state = Path(os.environ.get("FT_DESK_STATE") or root / ".fable-team" / "state" / "news-desk")
    now = datetime.strptime(os.environ["FT_DESK_NOW"], "%Y-%m-%d %H:%M") if os.environ.get("FT_DESK_NOW") else datetime.now()
    text = build(root, now)
    dg = digest(text)
    last = state / "digest.sha"
    if last.is_file() and last.read_text(encoding="utf-8").strip() == dg:
        LOG.info("바뀐 것 없음 — desk relay 0")
        return 0
    sent = state / "last-sent.txt"
    rows = changed(sent.read_text(encoding="utf-8") if sent.is_file() else "", text)
    if not rows:
        LOG.info("바뀐 칸 0 — desk relay 0")
        return 0
    out = state / f"{now:%Y%m%d-%H%M}.md"
    if (n := _sent_today(state, now)) >= DAY_CAP:
        LOG.info("오늘 desk 쪽지 %d통 = 상한 — relay 0 · 전문만 남김", n)
        state.mkdir(parents=True, exist_ok=True)
        top, _, rest = text.partition("\n")
        out.write_text(f"{top}\n> 오늘 desk 쪽지 상한 {DAY_CAP}통 도달 — 쪽지 0 · 이 전문만 남김\n{rest}", encoding="utf-8")
        return 0
    try:
        seat = desk_seat(root)
    except RuntimeError as e:
        print(f"판정 불가 desk 좌석 — {e}", file=sys.stderr)
        return 1
    note = state / f"{now:%Y%m%d-%H%M}.brief.txt"
    try:
        state.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        note.write_text(brief(rows, now, out), encoding="utf-8")
        relay(root, note, seat, f"뉴스 바뀐 칸 {len(rows)}개 · {now:%H:%M} (요약 ≤2KB · 끝줄 = 전문 경로)")
    except (RuntimeError, OSError) as e:
        print(f"판정 불가 relay — {e}", file=sys.stderr)
        return 1
    _count_path(state, now).write_text(f"{n + 1}\n", encoding="utf-8")
    sent.write_text(text, encoding="utf-8")
    last.write_text(dg + "\n", encoding="utf-8")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["render"]:
        root = env.ft_root()
        now = datetime.strptime(os.environ["FT_DESK_NOW"], "%Y-%m-%d %H:%M") if os.environ.get("FT_DESK_NOW") else datetime.now()
        print(build(root, now), end="")
        return 0
    if argv[:1] not in ([], ["run"]):
        print("usage: ft_news_desk.py [run|render]", file=sys.stderr)
        return 2
    return tick()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
