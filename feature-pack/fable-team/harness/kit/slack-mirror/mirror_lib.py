"""mirror_lib — Slack 호출·스레드 키·메시지 포맷 (byz_mbox_slack_mirror.py 용).

xClaw 라우터(xclaw-stream-router.py _slack_post)의 요청 모양을 가져오되 «실패를 삼키지 않는다»:
ok!=true·네트워크 오류는 전부 MirrorError 로 raise 한다(BYZ #0 RULE).
포맷 = 역할 파일 §1-4(사람 말 3줄) · §1-5(작업 1개 = 스레드 1개).
"""
import json
import re
import urllib.error
import urllib.parse
import urllib.request


class MirrorError(RuntimeError):
    pass


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
_ISSUE = re.compile(r"(?<![\w#])#(\d{1,4})(?!\d)")  # 5자리 mbox seq 는 제외
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


def first_sentence(text: str, cap: int = 120) -> str:
    one = " ".join(text.split())
    return re.split(r"(?<=[.!?。])\s| · ", one, maxsplit=1)[0][:cap] or "(빈 본문)"


def root_text(key: str, what: str) -> str:
    return f"{esc(key)} 시작 — {esc(what)}"


def root_marker(key: str) -> str:
    return f"{esc(key)} 시작"


def format_row(row: dict[str, object], label: str, mention: str, summary: dict[str, str | None] | None, text: str) -> str:
    """사람 말 3줄 — 1줄 무슨 일 · 2줄 오빠 할 일 · 3줄 소문자 꼬리. summary 가 None 이면 원문 첫 문장(꼬리에 표시)."""
    what = summary["what"] if summary else first_sentence(text)
    todo = summary["todo"] if summary else None
    if label == "HIL" and not todo:
        todo = "판정이 필요해요 — 전문을 확인해 주세요"
    who = f"<@{mention}> " if label == "HIL" and mention else ""
    tail = [esc(row.get("from", "?")), f"#{row.get('seq')}"]
    if row.get("body_full"):
        tail.append(f"전문 {esc(row['body_full'])}")
    if summary is None:
        tail.append("원문 그대로")
    return f"{esc(what)}\n{who}{esc(todo) if todo else '할 일 없음'}\n({' · '.join(tail)})"


def format_gap(first: int, last: int) -> str:
    n = last - first + 1
    return (f"슬랙에 못 올라간 보고가 {n}건 있어요 — 보낸 기록이 비어 있어요\n"
            f"할 일 없음 — 하네스 담당이 확인해요\n(mirror · #GAP-{first}-{last})")
