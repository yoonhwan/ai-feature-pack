"""post_guard — 슬랙 게시 «전» 비밀·내부어 패턴 검사 (R205 · 설계 DESIGN-planner-human-facing-roles §5).

1묶음(비밀: 토큰·키·DSN·비번)은 모든 게시에, 2묶음(내부 어휘: 좌석 이름·경로·비용·판정 번호)은 «사람 채널» 게시에만 건다
(#byz-planner 기계 발행은 판정 번호를 쓴다). 걸리면 게시 0 + raise(묶음·패턴 이름만 — 글 원문은 어디에도 내지 않는다).
사람 채널 = ⓐ 루트 `.fable-team/seats-*.json` 전부의 `_slack_channel`(문자열 또는 목록 · 단일 출처) ∪ ⓑ 환경변수 BYZ_HUMAN_CHANNELS(쉼표 목록 · 보조)
· `reply` 는 항상 사람 채널로 본다. 루트 = env FT_ROOT, 없으면 DEFAULT_ROOT. 명부 폴더 없음·JSON 깨짐 = raise(조용히 «사람 채널 아님» 0 · R231a 교정 2).
"""
from __future__ import annotations  # mini python 3.9.6 — `str | None` 주석을 문자열로 미뤄 import TypeError 를 막는다

import json
import logging
import os
import re
from pathlib import Path

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
ROOT_ENV = "FT_ROOT"
DEFAULT_ROOT = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"  # ~/.hermes/scripts 에서 불려도 명부에 닿는 고정 기본값


class PostGuardError(MirrorError):
    pass


def _channels_of(f: Path, data: object) -> set[str]:
    """명부 1개의 `_slack_channel` — 키 없음 = 빈 집합(정상) · 있으면 비어 있지 않은 문자열 또는 그것만 담은 비어 있지 않은 목록, 그 밖 = 손상."""
    if not isinstance(data, dict):
        raise PostGuardError(f"사람 채널 판정 불가 — 명부 최상위가 객체 아님: {f.name} · 게시 0")
    if "_slack_channel" not in data:
        return set()
    val = data["_slack_channel"]
    items = [val] if isinstance(val, str) else val
    if not isinstance(items, list) or not items or not all(isinstance(c, str) and c.strip() for c in items):
        raise PostGuardError(f"사람 채널 판정 불가 — _slack_channel 형식 손상: {f.name} · 게시 0")
    return {c.strip() for c in items}


def _roster_channels() -> set[str]:
    fdir = Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT) / ".fable-team"
    if not fdir.is_dir():
        raise PostGuardError(f"사람 채널 판정 불가 — 명부 폴더 없음: {fdir} · 게시 0")
    found: set[str] = set()
    for f in sorted(fdir.glob("seats-*.json")):
        try:
            found |= _channels_of(f, json.loads(f.read_text(encoding="utf-8")))
        except (OSError, ValueError) as e:
            raise PostGuardError(f"사람 채널 판정 불가 — 명부 읽기 실패: {f.name} ({type(e).__name__}) · 게시 0") from e
    if not found:
        logging.getLogger(__name__).info("post_guard: _slack_channel 가진 명부 0개 — env %s 만 사용", HUMAN_CHANNELS_ENV)
    return found


def human_channels() -> set[str]:
    env = {c.strip() for c in os.environ.get(HUMAN_CHANNELS_ENV, "").split(",") if c.strip()}
    return _roster_channels() | env


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
