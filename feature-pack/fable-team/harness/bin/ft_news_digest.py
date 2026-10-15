"""ft_news_digest — 뉴스가 Slack 에 발행되면 planner 좌석에도 «완전 요약» 6줄 1통 (R217 · 오빠 판정 1825). 쓰는 쪽은 ft_news_ledger.py.

재료 = 발행 때 이미 손에 있는 값(원장 차이 · 판 블록 · 상태 절)과 «이번 발행 호출이 돌려준» 영수증(ts·channel·permalink — 발행 도구 stdout) 뿐 — 새 LLM 0 · 파일 인계 0. 쪽지 6줄 ≤ 700B:
머리(링크 · 120자 넘으면 ts·채널) · 결정 건수 · 한 일 · 하는 일 · 할 일 · 팀 상태. 같은 ts 로 두 번 보내지 않는다(news-digest/sent.ts). 실패 = 예외(호출부가 ERROR 로그 · 발행 rc 불변).
env: FT_NEWS_DIGEST(0 = 끔) · FT_NEWS_MBOX(기본 FT_MBOX → <루트>/.fable-team/comm/mbox.sh) · FT_DECISION_COUNT(R214 건수 도구 · 기본 <루트>/.fable-team/bin/ft-decision-count.sh)
"""
import json
import logging
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

from ft_news_ledger_text import Block
from ft_news_post import Receipt

LOG =logging.getLogger("ft_news_ledger")
MAX_LINE, MAX_BYTES, COUNT_TIMEOUT_S = 120, 700, 2
TEAM = re.compile(r"^• (.+?) — 일함 (\d+) · 정지 (.*?) / ")


def _cut(s: str, n: int = MAX_LINE) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"


def _lines(blocks: list[Block], prefix: str) -> list[str]:
    return [ln.removeprefix("• ") for t, ls in blocks if t.startswith(prefix) for ln in ls]


def decision_line(root: Path) -> str:
    tool = Path(os.environ.get("FT_DECISION_COUNT") or root / ".fable-team" / "bin" / "ft-decision-count.sh")
    if not tool.is_file():
        return "(건수 도구 미설치 — R214)"
    try:
        done = subprocess.run(["bash", str(tool)], capture_output=True, text=True, timeout=COUNT_TIMEOUT_S, check=False)
    except subprocess.TimeoutExpired:
        return "(건수 실패 rc=timeout)"
    out = done.stdout.strip().splitlines()
    return out[0] if done.returncode == 0 and out else f"(건수 실패 rc={done.returncode})"


def done_line(diff: list[tuple[str, str]]) -> str:
    hits = [text for kind, text in diff if kind != "빠짐" and "완료" in (text.rsplit("→", 1)[-1] if kind == "바뀜" else text)]
    return "한 일: " + (" · ".join(hits[:3]) if hits else "원장 변화 0" if not diff else "완료로 바뀐 줄 0")


def doing_line(blocks: list[Block]) -> str:
    return "하는 일: " + (" · ".join([ln for ln in _lines(blocks, "*팀 작업*") if "진행" in ln][:3]) or "진행 줄 0")


def todo_line(blocks: list[Block]) -> str:
    return "할 일: " + (" · ".join(_lines(blocks, "*오빠 할 일*")[:2]) or "오빠 할 일 0")


def team_line(status: tuple[Block, str] | None) -> str:
    if status is None:
        return "팀 상태: (상태 절 없음)"
    rows = [m for ln in status[0][1] if (m := TEAM.match(ln))]
    stalled = [m[1] for m in rows if m[3] != "없음"]
    return f"팀 상태: 쉬는 팀 {sum(1 for m in rows if m[2] == '0')} · 정지 팀 {', '.join(stalled) or '없음'}"


def _already_sent(f: Path, ts: str) -> bool:
    return f.exists() and f.read_text(encoding="utf-8").strip() == ts


def _body(head: str, rest: list[str]) -> str:
    for n in range(MAX_LINE, 19, -10):  # 700B 를 넘으면 줄 길이를 줄여 6줄을 지킨다
        text = "\n".join([head, *(_cut(ln, n) for ln in rest)])
        if len(text.encode("utf-8")) <= MAX_BYTES:
            return text
    raise ValueError(f"요약 쪽지가 줄 길이 20 에서도 {MAX_BYTES}B 를 넘는다")


def _head(now: datetime, rec: Receipt, posts: int) -> str:
    """링크가 120자를 넘으면 «ts=<ts> ch=<C…>» 로 대체 — 링크를 자르지 않는다."""
    tail = f" (판 {posts}개)" if posts > 1 else ""
    head = f"[뉴스 요약 {now:%H:%M}] {rec['permalink'] or 'ts=%s ch=%s' % (rec['ts'], rec['channel'])}{tail}"
    return head if len(head) <= MAX_LINE else f"[뉴스 요약 {now:%H:%M}] ts={rec['ts']} ch={rec['channel']}{tail}"


def send(root: Path, state: Path, now: datetime, diff: list[tuple[str, str]], blocks: list[Block], status: tuple[Block, str] | None, posts: int, rec: Receipt) -> bool:
    """planner 에 요약 1통 — 보냈으면 True · 같은 ts 면 False · 수신자·mbox 실패는 raise. rec = 이번 발행 호출의 마지막 새 글 영수증."""
    sent = state.parent / "news-digest" / "sent.ts"
    if _already_sent(sent, str(rec["ts"])):
        return False
    to = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_hil_route"]
    body = _body(_head(now, rec, posts), [decision_line(root), done_line(diff), doing_line(blocks), todo_line(blocks), team_line(status)])
    mbox = os.environ.get("FT_NEWS_MBOX") or os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    if (rc := subprocess.run(["bash", mbox, "send", to, "ft-news-digest", body], capture_output=True, check=False).returncode) != 0:
        raise RuntimeError(f"mbox send rc={rc} to={to}")
    sent.parent.mkdir(parents=True, exist_ok=True)
    sent.write_text(f"{rec['ts']}\n", encoding="utf-8")
    return True


def maybe_send(root: Path, state: Path, now: datetime, diff: list[tuple[str, str]], blocks: list[Block], status: tuple[Block, str] | None, parts: int, posts: list[Receipt | None]) -> None:
    """발행 rc 0 직후 호출 — 쪽지 실패가 발행을 되돌리지 않는다(ERROR 로그 · 그 판 몫 요약은 버리고 다음 발행에 합치지 않음).

    posts = 이번 호출의 영수증 목록: 비었으면(전부 같은 내용) 쪽지 0 · None 이 섞이면(stdout 해석 실패) ERROR 1줄 + 쪽지 0."""
    if os.environ.get("FT_NEWS_DIGEST") == "0" or not posts:
        return
    recs = [p for p in posts if p is not None]
    if len(recs) != len(posts):
        LOG.error("요약 재료 없음 — 발행은 성공 (발행 도구 stdout 의 «발행 완료 ts=… channel=… permalink=…» 줄을 못 읽음)")
        return
    try:
        send(root, state, now, diff, blocks, status, parts, recs[-1])
    except (RuntimeError, OSError, ValueError, KeyError) as e:
        LOG.error("planner 요약 쪽지 실패(이 판 요약 버림): %s", e)
