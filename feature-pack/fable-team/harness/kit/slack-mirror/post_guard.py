"""post_guard — 슬랙 게시 «전» 비밀·내부어 패턴 검사 (R205 · 설계 DESIGN-planner-human-facing-roles §5).

1묶음(비밀: 토큰·키·DSN·비번)은 모든 게시에, 2묶음(내부 어휘: 좌석 이름·경로·비용·판정 번호)은 «사람 채널» 게시에만 건다
(#byz-planner 기계 발행은 판정 번호를 쓴다). 걸리면 게시 0 + raise(묶음·패턴 이름만 — 글 원문은 어디에도 내지 않는다).
사람 채널 = 환경변수 BYZ_HUMAN_CHANNELS(쉼표 목록 — 후속 카드가 #byz-talk 채널 ID 를 넣는다) · `reply` 는 항상 사람 채널로 본다.
"""
import os
import re

from mirror_lib import MirrorError, post

SECRETS = {
    "slack-token": r"xox[abp]-",
    "aws-key": r"AKIA[0-9A-Z]{12,}",
    "private-key": r"-----BEGIN",
    "sk-key": r"sk-[A-Za-z0-9]{16,}",
    "password": r"(?i)password=",
    "postgres-dsn": r"postgres(ql)?://",
    "redis-dsn": r"redis://",
}
INTERNAL = {
    "seat-name": r"byz-[a-z]+-[a-z]+-(claude|codex)#[0-9]+",
    "abs-path": r"/Users/",
    "worktree-path": r"\.worktrees/",
    "cost": r"\$[0-9]",
    "verdict-number": r"판정 [0-9]+",
}
HUMAN_CHANNELS_ENV = "BYZ_HUMAN_CHANNELS"


class PostGuardError(MirrorError):
    pass


def human_channels() -> set[str]:
    return {c.strip() for c in os.environ.get(HUMAN_CHANNELS_ENV, "").split(",") if c.strip()}


def _hits(text: str, group: dict[str, str]) -> list[str]:
    return [name for name, pat in group.items() if re.search(pat, text)]


def check(text: str, channel: str, *, human: bool = False) -> None:
    """걸리면 PostGuardError. human=True 이거나 channel 이 사람 채널이면 2묶음도 건다."""
    found = [f"묶음1:{n}" for n in _hits(text, SECRETS)]
    if human or channel in human_channels():
        found += [f"묶음2:{n}" for n in _hits(text, INTERNAL)]
    if found:
        raise PostGuardError(f"게시 거부(post_guard) — {', '.join(found)} · 게시 0")


def guarded_post(base: str, token: str, channel: str, text: str, thread_ts: str | None = None, *, human: bool = False) -> str:
    check(text, channel, human=human)
    return post(base, token, channel, text, thread_ts)
