#!/usr/bin/env python3
"""ft_news_desk — 뉴스 틱마다 desk 세션 화면에 붙일 «전문» 3블록을 조립하고, 바뀐 틱에만 desk 로 relay 1통 (r1055 · Issue #4004).

블록 = ①골 표(원장) ②팀별 표(명단·카드 흐름·명부·보드 스냅샷) ③오빠 손(h 목록·답 대기 질문). 이 파일 = ③ + 조립·digest·좌석·relay.
①·② 재료 = ft_news_desk_blocks.py(파일 상한 200줄 분리). 블록 순서는 Q1=ⓐ(오빠 승인 본보기 그대로) · 그 밖 블록 0.
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
    CLOCK, DOING_CHARS, LOG, _run, _timeout, _why, goal_block, snapshot, team_block,
)

def _hil(root: Path) -> list[str]:
    tool = os.environ.get("FT_DESK_HIL") or str(HERE / "ft-hil.sh")
    each = _run(["bash", tool, "--pending", "--each"], _timeout("FT_DESK_TOOL_TIMEOUT"))
    if each.returncode != 0:
        raise RuntimeError(f"ft-hil --pending rc={each.returncode} {each.stderr.strip()[:DOING_CHARS]}")
    count = len([x for x in each.stdout.splitlines() if x.strip()])
    summary = _run(["bash", tool, "--pending"], _timeout("FT_DESK_TOOL_TIMEOUT"))
    return [f"- 실행할 스크립트: {count}개 ({summary.stdout.strip() or f'미실행 h {count}개'})"]


def _questions(root: Path) -> list[str]:
    done = _run(["bash", os.environ.get("FT_DESK_DECISION") or str(HERE / "ft-decision-count.sh")], _timeout("FT_DESK_TOOL_TIMEOUT"))
    body = [x for x in done.stdout.strip().splitlines() if x.strip()]
    if done.returncode != 0 or not body:
        raise RuntimeError(f"ft-decision-count rc={done.returncode} {done.stderr.strip()[:DOING_CHARS]}")
    return [f"- 답 대기 질문: {body[-1]}"]


def oppa_block(root: Path) -> list[str]:
    out = ["## 오빠 손"]
    for part in (_hil, _questions):
        try:
            out += part(root)
        except (RuntimeError, OSError) as e:
            LOG.error("오빠 손 칸 확인 불가: %s", e)
            out.append(f"- 확인 불가({_why(e)})")
    return out

def build(root: Path, now: datetime) -> str:
    head = [f"# 뉴스 전문 — {now:%m-%d %H:%M} (뉴스 틱 자동 생성 · 손글 0)"]
    return "\n\n".join(["\n".join(head), *("\n".join(b) for b in (goal_block(root), team_block(root, snapshot(root)), oppa_block(root)))]) + "\n"


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
    try:
        seat = desk_seat(root)
    except RuntimeError as e:
        print(f"판정 불가 desk 좌석 — {e}", file=sys.stderr)
        return 1
    out = state / f"{now:%Y%m%d-%H%M}.md"
    try:
        state.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        relay(root, out, seat, f"뉴스 전문 3블록 · {now:%H:%M} · 골 표 + 팀 표 + 오빠 손 (전문 파일 첨부)")
    except (RuntimeError, OSError) as e:
        print(f"판정 불가 relay — {e}", file=sys.stderr)
        return 1
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
