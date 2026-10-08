"""magazine_slack — 매거진 슬랙 글: 뿌리 글 · 날짜 표식 찾기 · PDF 스레드 업로드. 실패는 전부 MirrorError.

뿌리 글 첫 줄의 `아침 매거진 YYYY-MM-DD` 가 그날 뿌리 글의 유일한 식별자다(설계 §5 · 재게시 방지의 근거).
"""
import json
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from mirror_lib import MirrorError, api_call, esc, paged, post

SLACK_BASE = "https://slack.com/api"
UPLOAD_TIMEOUT = 30


@dataclass(frozen=True)
class Target:
    base: str
    token: str
    channel: str
    mention: str


def marker(date: str) -> str:
    return f"아침 매거진 {date}"


def root_text_first_line(date: str) -> str:
    return f"*{marker(date)}*"


def eli5_warning_line(cause: str) -> str:
    """쉬운 판(HTML) 실패 1줄 — 원인 첫 줄만. 슬랙에 싣는 쪽(root_text·reply_text)이 esc 로 중화한다(미검증 문장 <@U..>·<!channel>)."""
    first = (str(cause).strip().splitlines() or [""])[0][:200]
    return f"쉬운 판(HTML) 못 만들었어요 — {first}"


def root_text(date: str, lines: list[str], link: str | None, hil_count: int, mention: str, warn: str | None = None) -> str:
    out = [root_text_first_line(date)] + [esc(x) for x in lines]
    where = "PDF(풀 디테일)" if warn else "PDF(풀 디테일)·HTML(쉬운 판)"  # 쉬운 판이 없는 날(warn)은 HTML 을 안내하지 않는다
    out.append(f"<{esc(link)}|매거진 본문>" if link else f"본문은 스레드의 {where}에 있어요")
    if hil_count > 0:
        out.append(f"<@{mention}> 오빠 할 일이 {hil_count}건 있어요")
    if warn:
        out.append(esc(warn))
    return "\n".join(out)


def failure_text(cause: str) -> str:
    """발행 실패 1줄 — 뿌리 글 표식(`아침 매거진 …`)을 쓰지 않는다(다음 실행이 뿌리 글로 오인하지 않게)."""
    return f"매거진 발행 실패 — {esc(cause)}"


def find_first_line(t: Target, first_line: str, oldest_epoch: float) -> str | None:
    """채널 history 에서 봇이 쓴 글 중 첫 줄이 «정확히» first_line 인 것의 ts (가장 이른 것). 없으면 None."""
    msgs = paged(t.base, t.token, "conversations.history", {"channel": t.channel, "oldest": f"{oldest_epoch:.6f}", "limit": 200})
    hits = [m for m in msgs if m.get("bot_id") and str(m.get("text", "")).split("\n", 1)[0] == first_line]
    return min((str(m["ts"]) for m in hits), default=None)


def find_root(t: Target, date: str, oldest_epoch: float) -> str | None:
    """그날 뿌리 글의 ts. 첫 줄 «정확 일치» — 같은 봇이 쓴 미러 글(「#885 시작 — 아침 매거진 …」)을 오인하지 않는다."""
    return find_first_line(t, root_text_first_line(date), oldest_epoch)


def post_root(t: Target, text: str) -> str:
    return post(t.base, t.token, t.channel, text)


def _send_bytes(url: str, data: bytes, content_type: str = "application/pdf") -> None:
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": content_type})
    kind = "PDF" if content_type == "application/pdf" else "파일"
    try:
        with urllib.request.urlopen(req, timeout=UPLOAD_TIMEOUT) as resp:
            code = resp.status
    except (urllib.error.URLError, OSError) as e:
        raise MirrorError(f"{kind} 바이트 업로드 실패: {type(e).__name__}") from e
    if code != 200:
        raise MirrorError(f"{kind} 바이트 업로드 HTTP {code}")


def post_reply(t: Target, root_ts: str, text: str) -> str:
    return post(t.base, t.token, t.channel, text, thread_ts=root_ts)


def thread_bot_messages(t: Target, root_ts: str) -> list[dict[str, object]]:
    """스레드의 봇 글 전부(뿌리 글 포함) — 조회 오류·쪽 수 초과는 raise(«없음» 으로 삼키지 않는다)."""
    msgs = paged(t.base, t.token, "conversations.replies", {"channel": t.channel, "ts": root_ts, "limit": 200})
    return [m for m in msgs if m.get("bot_id")]


def find_reply_first_line(t: Target, root_ts: str, first_line: str) -> str | None:
    """스레드 답글 중 봇이 쓴 글의 첫 줄이 «정확히» first_line 인 것의 ts (가장 이른 것)."""
    hits = [m for m in thread_bot_messages(t, root_ts) if str(m["ts"]) != root_ts and str(m.get("text", "")).split("\n", 1)[0] == first_line]
    return min((str(m["ts"]) for m in hits), default=None)


def has_file_title(t: Target, root_ts: str, title: str) -> bool:
    """스레드 봇 글에 붙은 파일 중 제목이 «정확히» title 인 것이 있나 — 첨부 멱등의 원격 표식."""
    for m in thread_bot_messages(t, root_ts):
        files = m.get("files")
        if isinstance(files, list) and any(isinstance(f, dict) and f.get("title") == title for f in files):
            return True
    return False


def upload_file(
    t: Target, thread_ts: str, path: Path, title: str, content_type: str,
    on_file_id: Callable[[str], None] | None = None, on_not_shared: Callable[[], None] | None = None,
) -> None:
    """on_file_id: file_id 를 받은 «직후·바이트 전송 전» 호출 — 시도 기록용. 이 콜백이 raise 하면 원격 전송 0.
    on_not_shared: «공유가 확실히 안 된» 실패(바이트 전송 실패 · complete 가 ok=false 로 거절)에서만 호출 — 응답 유실 같은
    결과 불명 실패(전송 오류·시간 초과)에는 부르지 않는다(그 경우 시도 기록이 «불명» 으로 남는다)."""
    data = path.read_bytes()
    got = api_call(t.base, t.token, "files.getUploadURLExternal", {"filename": path.name, "length": len(data)}, get=True)
    if on_file_id:
        on_file_id(str(got["file_id"]))
    try:
        _send_bytes(str(got["upload_url"]), data, content_type)
        api_call(t.base, t.token, "files.completeUploadExternal", {
            "files": json.dumps([{"id": got["file_id"], "title": title}]), "channel_id": t.channel, "thread_ts": thread_ts,
        }, get=True)
    except MirrorError as e:
        if on_not_shared and (" ok=false" in str(e) or "바이트 업로드" in str(e)):  # mirror_lib.api_call / _send_bytes 의 확정 실패 문구
            on_not_shared()
        raise

