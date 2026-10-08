"""magazine_slack — 매거진 슬랙 글: 뿌리 글 · 날짜 표식 찾기 · PDF 스레드 업로드. 실패는 전부 MirrorError.

뿌리 글 첫 줄의 `아침 매거진 YYYY-MM-DD` 가 그날 뿌리 글의 유일한 식별자다(설계 §5 · 재게시 방지의 근거).
"""
import json
import urllib.error
import urllib.request
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


def root_text(date: str, lines: list[str], link: str | None, hil_count: int, mention: str) -> str:
    out = [root_text_first_line(date)] + [esc(x) for x in lines]
    out.append(f"<{esc(link)}|매거진 본문>" if link else "본문은 스레드의 PDF 에 있어요")
    if hil_count > 0:
        out.append(f"<@{mention}> 오빠 할 일이 {hil_count}건 있어요")
    return "\n".join(out)


def failure_text(cause: str) -> str:
    """발행 실패 1줄 — 뿌리 글 표식(`아침 매거진 …`)을 쓰지 않는다(다음 실행이 뿌리 글로 오인하지 않게)."""
    return f"매거진 발행 실패 — {esc(cause)}"


def find_root(t: Target, date: str, oldest_epoch: float) -> str | None:
    """채널 history 에서 봇이 쓴 그날 뿌리 글의 ts (가장 이른 것). 없으면 None."""
    msgs = paged(t.base, t.token, "conversations.history", {"channel": t.channel, "oldest": f"{oldest_epoch:.6f}", "limit": 200})
    first = root_text_first_line(date)  # 첫 줄 «정확 일치» — 같은 봇이 쓴 미러 글(「#885 시작 — 아침 매거진 …」)을 오인하지 않는다
    hits = [m for m in msgs if m.get("bot_id") and str(m.get("text", "")).split("\n", 1)[0] == first]
    return min((str(m["ts"]) for m in hits), default=None)


def post_root(t: Target, text: str) -> str:
    return post(t.base, t.token, t.channel, text)


def _send_bytes(url: str, data: bytes) -> None:
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/pdf"})
    try:
        with urllib.request.urlopen(req, timeout=UPLOAD_TIMEOUT) as resp:
            code = resp.status
    except (urllib.error.URLError, OSError) as e:
        raise MirrorError(f"PDF 바이트 업로드 실패: {type(e).__name__}") from e
    if code != 200:
        raise MirrorError(f"PDF 바이트 업로드 HTTP {code}")


def upload_pdf(t: Target, thread_ts: str, pdf: Path, title: str) -> None:
    data = pdf.read_bytes()
    got = api_call(t.base, t.token, "files.getUploadURLExternal", {"filename": pdf.name, "length": len(data)}, get=True)
    _send_bytes(str(got["upload_url"]), data)
    api_call(t.base, t.token, "files.completeUploadExternal", {
        "files": json.dumps([{"id": got["file_id"], "title": title}]), "channel_id": t.channel, "thread_ts": thread_ts,
    }, get=True)
