"""thread_room_shape — «스레드 = 주제 대화 전용 · 방 글(승인·뉴스·알림) = post» 판정(r617).

`--ts`·`--to-slack` 답글 길과 `--thread` 거절이 같은 규칙을 쓴다. 값: env FT_SLACK_TOPIC_ONLY(쉼표 · 미설정 = `desk` · 빈 값 = 거절 끔).
"""
import os
import re
import sys

TOPIC_ENV = "FT_SLACK_TOPIC_ONLY"  # 주제 전용 이름들 · 쉼표 · 빈 값 = 거절 끔(r561)
TOPIC_DEFAULT = "desk"
ROOM_HEADS = ("[상태]", "[뉴스]", "[desk ·")  # 방 글 머리 — 승인 묶음·상태 알림·뉴스(r617)
ROOM_HINT = "주제 스레드엔 주제 대화만 — 방 글은 post --to desk"  # 답글 길 거절 안내 1줄(r617)
BANG_H = re.compile(r"!\s*bash\s+/tmp/h")  # 승인 묶음의 «! bash /tmp/h12» 꼴
APPROVAL = re.compile(r"승인[^\n]*\bh\d+\b|\bh\d+\b[^\n]*승인")  # «승인» + «h<숫자>»


def topic_only() -> set[str]:
    """주제 전용 이름들 — env 미설정 = 기본 `desk` · 빈 값 = 거절 끔(r561)."""
    raw = os.environ.get(TOPIC_ENV)
    return {x.strip() for x in (TOPIC_DEFAULT if raw is None else raw).split(",") if x.strip()}


def room_shaped(text: str) -> bool:
    """본문이 «방 글» 꼴(승인 묶음·상태 알림·뉴스)인가 — 스레드가 아니라 방(post)에 갈 글(r617).

    줄머리 «[상태]»·«[뉴스]»·«[desk ·» 또는 «! bash /tmp/h»·«승인 … h<숫자>» 가 있으면 방 글 꼴."""
    for ln in text.splitlines():
        if ln.lstrip().startswith(ROOM_HEADS):
            return True
    return bool(BANG_H.search(text) or APPROVAL.search(text))


def refuse_room_post(text: str, force: bool) -> bool:
    """답글 길(`--ts`·`--to-slack`)의 방 글 꼴 거절 — True = 거절(게시 0). `--force-thread` 면 경고 1줄 + 게시."""
    if not topic_only() or not room_shaped(text):
        return False
    if force:
        print(f"WARN 방 글 꼴 강제 전송 — {ROOM_HINT}", file=sys.stderr)
        return False
    print(f"REJECT 방 글 꼴 답글 — {ROOM_HINT}", file=sys.stderr)
    return True
