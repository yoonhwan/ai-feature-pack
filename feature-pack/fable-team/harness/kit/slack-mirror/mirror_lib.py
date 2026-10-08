"""mirror_lib — Slack 호출·스레드 키·메시지 포맷 (byz_mbox_slack_mirror.py 용).

xClaw 라우터(xclaw-stream-router.py _slack_post)의 요청 모양을 가져오되 «실패를 삼키지 않는다»:
ok!=true·네트워크 오류는 전부 MirrorError 로 raise 한다(BYZ #0 RULE).
포맷 = 역할 파일 §1-4(사람 말 3줄) · §1-5(작업 1개 = 스레드 1개).
"""
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import mirror_share as ms


class MirrorError(RuntimeError):
    pass


def read_token(path: Path) -> str:
    try:
        for ln in path.read_text(encoding="utf-8").splitlines():
            if ln.startswith("YOONHWAN_BOT_TOKEN=") and ln.split("=", 1)[1].strip():
                return ln.split("=", 1)[1].strip()
    except OSError as e:
        raise MirrorError(f"토큰 파일 읽기 실패: {path} ({type(e).__name__})") from e
    raise MirrorError(f"토큰 파일에 YOONHWAN_BOT_TOKEN 없음: {path}")


def save_state(path: Path, st: dict[str, object]) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def esc(value: object) -> str:
    """mrkdwn 중화 — mailbox 본문은 다른 에이전트가 쓴 미검증 입력이다(<!channel>·<@U..> 무력화)."""
    return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def api_call(base: str, token: str, method: str, params: dict[str, object], *, get: bool = False) -> dict[str, object]:
    headers = {"Authorization": f"Bearer {token}"}
    if get:
        req = urllib.request.Request(f"{base}/{method}?{urllib.parse.urlencode(params)}", headers=headers)
    else:
        headers["Content-Type"] = "application/json; charset=utf-8"
        req = urllib.request.Request(f"{base}/{method}", data=json.dumps(params).encode("utf-8"), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise MirrorError(f"{method} 호출 실패: {type(e).__name__}") from e
    if not body.get("ok"):
        raise MirrorError(f"{method} ok=false: {body.get('error')}")
    return body


MAX_PAGES = 20


def paged(base: str, token: str, method: str, params: dict[str, object]) -> list[dict[str, object]]:
    """next_cursor 를 끝까지 따라간다 — 상한을 넘으면 조용히 자르지 않고 raise."""
    out: list[dict[str, object]] = []
    cursor = ""
    for _ in range(MAX_PAGES):
        body = api_call(base, token, method, {**params, **({"cursor": cursor} if cursor else {})}, get=True)
        msgs = body.get("messages", [])
        out += [m for m in msgs if isinstance(m, dict)] if isinstance(msgs, list) else []
        meta = body.get("response_metadata")
        cursor = str(meta.get("next_cursor") or "") if isinstance(meta, dict) else ""
        if not cursor:
            return out
    raise MirrorError(f"{method} 가 {MAX_PAGES}쪽을 넘었어요 — 읽기 창을 줄여야 해요")


def post(base: str, token: str, channel: str, text: str, thread_ts: str | None = None) -> str:
    params: dict[str, object] = {"channel": channel, "text": text}
    if thread_ts:
        params["thread_ts"] = thread_ts
    return str(api_call(base, token, "chat.postMessage", params)["ts"])


def _msgs(body: dict[str, object]) -> list[tuple[str, str]]:
    raw = body.get("messages", [])
    return [(str(m.get("ts", "")), str(m.get("text", ""))) for m in raw] if isinstance(raw, list) else []


def channel_roots(base: str, token: str, channel: str, limit: int = 100) -> list[tuple[str, str]]:
    return _msgs(api_call(base, token, "conversations.history", {"channel": channel, "limit": limit}, get=True))


def thread_texts(base: str, token: str, channel: str, thread_ts: str, limit: int = 100) -> list[str]:
    body = api_call(base, token, "conversations.replies", {"channel": channel, "ts": thread_ts, "limit": limit}, get=True)
    return [t for _, t in _msgs(body)]


def has_marker(texts: list[str], marker: str) -> bool:
    pat = re.compile(re.escape(marker) + r"(?!\d)")
    return any(pat.search(t) for t in texts)


_PREFIX = re.compile(r"^\s*\[[^\]]*->[^\]]*\]\s*")
_TAG = re.compile(r"^\s*\[(HIL|BLOCK)\]\s*", re.IGNORECASE)
# Issue 키 = «명시된 것»만: 「Issue/이슈/PR #N」 또는 본문 맨 앞 「#N」·「[#N]」. 좌석명 #N(승계 #0->#1)·5자리 mbox seq·#0 은 키가 아니다.
_ISSUE = re.compile(r"(?:\b(?:Issue|issue|이슈|PR|pr)\s*#|^\s*\[?#)([1-9]\d{0,3})(?!\d)")
_FULL = re.compile(r"상세\(전문\):\s*(\S+)")
FULL_ROOTS = ("/tmp/mbox/", "/private/tmp/mbox/")
FULL_CAP = 3500
OTHER_KEY = "기타"


def classify(body: str) -> tuple[str, str]:
    """(라벨, 태그 뗀 본문) — 라벨은 보고|HIL|BLOCK."""
    text = _PREFIX.sub("", body, count=1)
    m = _TAG.match(text)
    return (m.group(1).upper(), text[m.end():]) if m else ("보고", text)


def thread_key(row: dict[str, object], text: str) -> str:
    """작업 1개 = 스레드 1개: Issue 번호 > 좌석 계보 > 기타."""
    m = _ISSUE.search(text)
    if m:
        return f"#{m.group(1)}"
    seat = re.sub(r"#\d+$", "", str(row.get("from", "")).strip())
    return seat or OTHER_KEY


def read_full(row: dict[str, object]) -> str | None:
    """relay·긴 보고의 전문 파일(mbox 가 /tmp/mbox 에 보관) — 읽을 수 없으면 None(요약만 간다)."""
    m = _FULL.search(str(row.get("body", "")))
    path = str(row.get("body_full") or (m.group(1) if m else ""))
    if not path.startswith(FULL_ROOTS):
        return None
    try:
        return Path(path).read_text(encoding="utf-8")
    except OSError:
        return None


def format_full(full: str) -> str:
    """스레드에 남길 전문 — 인용 블록(원문 보존: 답장 요구 검사 예외). 길면 앞부분 + 잘림 표시(전문 경로는 꼬리에 있다)."""
    body = full.strip()
    cut = len(body) > FULL_CAP
    lines = esc(body[:FULL_CAP]).split("\n")
    return "\n".join(["", "전문(원문 그대로 · 이 스레드는 답을 받지 않습니다)"] + ["> " + ln for ln in lines] + (["> … (이하 생략)"] if cut else []))


_GH_URL = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull)/\d+(?:#issue(?:comment)?-?\w+)?")


def issue_url(repo: str, key: str) -> str | None:
    """키 「#N」 → Issue URL (PR 번호여도 /issues/N 이 /pull/N 으로 이동한다). 키가 번호가 아니면 None."""
    m = re.fullmatch(r"#(\d+)", key)
    return f"https://github.com/{repo}/issues/{m.group(1)}" if repo and m else None


def links(texts: list[str], fallback: str | None) -> list[str]:
    """본문에서 GitHub Issue/PR/코멘트 URL(앵커 포함)을 모은다. 없으면 fallback(Issue URL)."""
    found: list[str] = []
    for t in texts:
        found += [u for u in _GH_URL.findall(t) if u not in found]
    return found[:3] or ([fallback] if fallback else [])


def first_sentence(text: str, cap: int = 120) -> str:
    one = " ".join(text.split())
    return re.split(r"(?<=[.!?。])\s| · ", one, maxsplit=1)[0][:cap] or "(빈 본문)"


def root_text(key: str, what: str, url: str | None = None) -> str:
    return ms.tag("작업상황", f"{esc(key)} 시작 — {esc(ms.share_guard(what) or ms.OMITTED)}") + (f"\n{esc(url)}" if url else "")


def root_marker(key: str) -> str:
    return f"{esc(key)} 시작"


def format_row(row: dict[str, object], label: str, mention: str, summary: dict[str, str | None] | None, text: str, *, block: str,
               full: str | None = None, urls: list[str] | None = None, options_text: str | None = None,
               kind: str | None = None, seats: str | None = None, plain: bool = False) -> str:
    """사람 말 — 1줄 [머리표] 무슨 일 · 2줄 정할 것 · (HIL) 결정 자리 줄(멘션은 여기만) · (요약 실패 시 「원문 그대로」 1줄) · 이어가기 블록 2줄(꼬리 · resume_block)."""
    what, todo, fixed = ms.share_lines(summary["what"] if summary else first_sentence(text), summary["todo"] if summary else None, text, label)
    what, fixed = (first_sentence(text), False) if plain and summary is None else (what, fixed)  # plain = 원문이 사실인 글(GitHub 제목) — 요약 실패 경로는 검사 제외
    who = f"<@{mention}> " if label == "HIL" and mention else ""
    place = f"\n{who}{ms.decision_line(str(row.get('from') or ''), seats)}" if label == "HIL" else ""
    first = ms.tag(kind or ("이슈보고" if label in ("HIL", "BLOCK") else "작업상황"), esc(what) + (f" {ms.CORRECTED}" if fixed else ""))
    head = f"{first}\n{esc(todo) if todo else '할 일 없음'}{place}" + ("\n(원문 그대로)" if summary is None else "") + f"\n{block}"
    head = head + (f"\n{options_text}" if options_text else "")
    head = head + ("\n링크: " + " ".join(esc(u) for u in urls) if urls else "")
    return head + format_full(full) if full else head
