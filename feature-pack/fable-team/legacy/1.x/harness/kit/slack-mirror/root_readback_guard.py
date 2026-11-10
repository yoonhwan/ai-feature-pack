"""root_readback_guard — 슬랙 뿌리 글 «되읽기 가드» (r1004 · 예외 없는 판 · r852 가지 판을 줄여 씀).

게시 «직후» 같은 글을 다시 읽어 사람이 읽는 틀을 어겼으면 지운다 — 슬랙은 표를 그리지 못하고, «…» 로 잘린 글은 읽을 수 없다.
위반 3꼴(예외 0 — 골 표·각주 표도 위반이다) =
  ① 표 줄(파이프 2개 이상 · 슬랙 링크 `<주소|글자>` 안 파이프는 셈 0) 또는 구분 줄 `--- | ---`
  ② «…» 3개 이상(1~2개는 사람이 쓴 정상 글에도 있다)
  ③ 첫 줄이 결론 문장이 아님(목록 표지 `-`·`*`·`•`·`1.` · `##` 이하 제목 · 표 줄 · 빈 글 · 앞 빈 줄)
부르는 쪽 계약: check(text) = 판정만(정상이면 None · «첫 줄» 은 원문 첫 줄 그대로) · readback(post) = 게시 직후 되읽기 → 위반이면 그 글을 지우고 ReadbackError 를 raise 한다(부르는 쪽 발행 rc1) · fail(event, why) = 되읽기 자체를 못 한 자리(글 번호 0)도 같은 실패 길(쪽지 1통 + raise).
  ERROR 로그는 부르는 쪽 «한 곳»에서 1줄만 남긴다(가드는 로그 0 — 사건당 ERROR 2줄 금지).
  planner [긴급] 쪽지는 사건 키 하나당 1통 — 오류 종류(조회·삭제·위반) 무관 · 표식을 O_CREAT|O_EXCL 로 원자 생성(동시 처리도 1통) · 전송 실패면 표식 되돌림.
env: FT_ROOT(명부·쪽지함·표식 뿌리 · 없으면 고정 기본값) · FT_READBACK_MBOX · FT_READBACK_STATE · FT_READBACK_TO · FT_READBACK_GUARD=0 = 끔(되돌림)
"""
import json
import logging
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from mirror_lib import MirrorError, api_call

LOG = logging.getLogger("root_readback_guard")
SENDER = "root-readback-guard"
ELLIPSIS = "…"
ELLIPSIS_MAX = 3  # «…» 3개 이상 = 잘린 글
SEPARATOR = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$")  # `--- | ---` · `|---|:--:|` · 바깥 파이프 없음
LIST_MARK = re.compile(r"^\s*(?:[-*+•]\s|\d+[.)]\s)")
HEAD_MARK = re.compile(r"^\s*(?:#{1,6}\s*$|#{2,6}\s)")  # 글자 없는 제목 표지 · `##` 이하 제목 = 결론이 아니다(`# 뉴스 — …` 제품 머리 줄은 결론 자리)
LINK = re.compile(r"<[^<>|]*\|[^<>]*>")  # 슬랙 링크 `<주소|글자>` — 안쪽 파이프는 표로 세지 않는다
DEFAULT_ROOT = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"  # ~/.hermes/scripts 에서 불려도 명부에 닿는 고정 기본값(post_guard 와 같은 값)


class ReadbackError(MirrorError):
    """틀 위반(지움) · 되읽기 실패 · 삭제 실패 — 부르는 쪽이 자기 발행 실패 경로로 받는다."""


@dataclass(frozen=True)
class Post:
    """게시된 글 하나 — 되읽기·지우기에 필요한 값 + 사건 키(쪽지 1통 기준)."""

    base: str
    token: str
    channel: str
    ts: str
    event: str


def _table_row(line: str) -> bool:
    return LINK.sub("", line).count("|") >= 2 or bool(SEPARATOR.match(line))


def check(text: str) -> str | None:
    """사람이 읽을 수 없는 이유 — 정상이면 None. «첫 줄» = 원본 첫 줄 그대로(앞 빈 줄을 건너뛰지 않는다)."""
    lines = text.splitlines()
    if not lines or not lines[0].strip():
        return "첫 줄이 결론 문장이 아님"  # 빈 글·앞 빈 줄 — 첫 줄이 결론이 아니다
    bad: list[str] = []
    if rows := sum(1 for ln in lines if _table_row(ln)):
        bad.append(f"표 줄 {rows}개")
    if (dots := sum(ln.count(ELLIPSIS) for ln in lines)) >= ELLIPSIS_MAX:
        bad.append(f"«…» {dots}개")
    first = lines[0]
    if LIST_MARK.match(first) or HEAD_MARK.match(first) or _table_row(first):
        bad.append("첫 줄이 결론 문장이 아님")
    return ", ".join(bad) or None


def read_back(post: Post) -> str:
    """게시된 그 글의 본문 — conversations.history 1회(7초 상한 + 재시도 1 = api_call 기본). 못 읽으면 MirrorError."""
    body = api_call(post.base, post.token, "conversations.history", {"channel": post.channel, "oldest": post.ts, "latest": post.ts, "inclusive": "true", "limit": 1}, get=True)
    for m in body.get("messages", []):
        if str(m.get("ts")) == post.ts:
            return str(m.get("text", ""))
    raise MirrorError(f"되읽기 실패 — 그 글({post.ts})이 조회 결과에 없음")


def _root() -> Path:
    return Path(os.environ.get("FT_ROOT") or DEFAULT_ROOT)


def _recipient() -> str:
    """planner 현역 — seats.json 의 `_hil_route` → `_master`(ft-magazine-check.sh 와 같은 값)."""
    if to := os.environ.get("FT_READBACK_TO"):
        return to
    data = json.loads((_root() / ".fable-team" / "seats.json").read_text(encoding="utf-8"))
    return str(data.get("_hil_route") or data.get("_master") or "")


def alarm(event: str, text: str) -> None:
    """planner [긴급] 1통 — 사건 키 하나당 1통(오류 종류 무관). 표식은 «보내기 전»에 원자 생성하고, 전송 실패면 지워서 다음 발행이 다시 시도한다."""
    state = Path(os.environ.get("FT_READBACK_STATE") or _root() / ".fable-team" / "state" / "root-readback")
    state.mkdir(parents=True, exist_ok=True)
    mark = state / (re.sub(r"[^A-Za-z0-9_.-]", "_", event) + ".sent")
    try:
        fd = os.open(mark, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        return  # 같은 사건 — 두 번째부터는 조용히 넘어간다
    os.write(fd, (text + "\n").encode("utf-8"))
    os.close(fd)
    try:
        to = _recipient()
    except (OSError, ValueError) as e:
        LOG.warning("쪽지 수신 좌석 확인 실패: %s — 쪽지 0", e)
        mark.unlink(missing_ok=True)
        return
    if not to:
        LOG.warning("쪽지 수신 좌석 없음(_hil_route/_master) — 쪽지 0")
        mark.unlink(missing_ok=True)
        return
    mbox = Path(os.environ.get("FT_READBACK_MBOX") or _root() / ".fable-team" / "comm" / "mbox.sh")
    done = subprocess.run(["bash", str(mbox), "send", to, SENDER, f"[긴급] {text}", "--urgent"], capture_output=True, text=True, timeout=21, check=False)
    if done.returncode != 0:
        LOG.warning("planner 쪽지 실패 rc=%s — 표식 지움(다음 발행에 다시)", done.returncode)
        mark.unlink(missing_ok=True)


def fail(event: str, why: str) -> ReadbackError:
    """되읽기 자싸를 못 한 자리(글 번호 0 등) — planner 쪽지 1통 + 부르는 쪽이 받을 오류(ERROR 1줄은 부르는 쪽)."""
    alarm(event, why)
    return ReadbackError(why)


def readback(post: Post) -> None:
    """게시 직후 되읽기 — 틀 위반이면 그 글을 지우고 raise(post.event = 사건 키 · ERROR 1줄은 부르는 쪽)."""
    if os.environ.get("FT_READBACK_GUARD") == "0":
        return
    try:
        text = read_back(post)
    except MirrorError as e:  # 게시는 됐는데 되읽기 실패: 삭제 0 · 조용한 통과 0
        alarm(post.event, f"뿌리 글 되읽기 실패 ts={post.ts} — 삭제 0 · 확인 필요({e})")
        raise ReadbackError(f"뿌리 글 되읽기 실패 ts={post.ts}: {e} — 삭제 0 · 확인 필요") from e
    if not (why := check(text)):
        return
    try:
        api_call(post.base, post.token, "chat.delete", {"channel": post.channel, "ts": post.ts})
    except MirrorError as e:  # 위반인데 삭제 실패: 글 남음 · 사람 처리
        alarm(post.event, f"뿌리 글 틀 위반({why}) 인데 삭제 실패 ts={post.ts} — 글 남음 · 사람 처리")
        raise ReadbackError(f"뿌리 글 틀 위반({why}) 인데 삭제 실패 ts={post.ts}: {e} — 글 남음") from e
    alarm(post.event, f"뿌리 글 틀 위반({why}) — 지웠어요 ts={post.ts} · 발행 실패")
    raise ReadbackError(f"뿌리 글 틀 위반({why}) — 지움 ts={post.ts} · 발행 실패")
