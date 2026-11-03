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
import subprocess
from pathlib import Path

import mirror_lib as lib
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
DESK_CHANNEL_ENV = "BYZ_DESK_CHANNEL"
DESK_MENTION_ENV = "BYZ_DESK_MENTION"
GATE_REPOS_ENV = "FT_APPROVAL_GATE_REPOS"  # 콜론 목록 · 기본 = 루트 + 팩 리포 (r1275 단계 4)
GATE_TARGET_ENV = "FT_APPROVAL_GATE_TARGET"  # 기본 origin/main
DEFAULT_PACK_REPO = "/Users/yoonhwan/Project/ai-feature-pack"
SHA40 = re.compile(r"(?<![0-9a-fA-F])[0-9a-f]{40}(?![0-9a-fA-F])")


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


def _git(repo: str, *args: str) -> int:
    """7초 + 재시도 1(하드 룰 12). 시간 초과·실행 실패 = rc 255(조용한 통과 0)."""
    for _ in range(2):
        try:
            return subprocess.run(["git", "-C", repo, *args], capture_output=True, timeout=7).returncode
        except (subprocess.TimeoutExpired, OSError):
            continue
    return 255


def approval_gate(text: str) -> None:
    """approve-merge 질문 글(본문에 approve-merge + 40hex sha)은 그 sha(PR head)가 origin/main 을 품을 때만 나간다 —
    질문 때 PR 이 옛 main 위면 승인 뒤 main 병합으로 head 가 바뀌어 같은 질문이 되풀이된다(r1275 단계 4 · 판정 3932).
    품지 않음 = 게시 0 «먼저 main 따라잡기» · 조회 실패 = 게시 0 «판정 불가»(조용한 통과 0) · approve-merge 낱말 없음 = 대상 밖."""
    shas = sorted(set(SHA40.findall(text))) if "approve-merge" in text else []
    if not shas:
        return
    repos = [r for r in (os.environ.get(GATE_REPOS_ENV) or f"{os.environ.get(ROOT_ENV) or DEFAULT_ROOT}:{DEFAULT_PACK_REPO}").split(":") if r]
    remote, _, branch = (os.environ.get(GATE_TARGET_ENV) or "origin/main").partition("/")
    for sha in shas:
        repo = next((r for r in repos if _git(r, "cat-file", "-e", sha + "^{commit}") == 0), None)
        if repo is None or _git(repo, "fetch", "-q", remote, branch) != 0:
            raise PostGuardError(f"게시 거부(approval_gate) — 판정 불가: {sha[:10]} 를 {'가진 리포 없음' if repo is None else remote + '/' + branch + ' 조회 실패'} · 게시 0")
        rc = _git(repo, "merge-base", "--is-ancestor", f"{remote}/{branch}", sha)
        if rc == 1:
            raise PostGuardError(f"게시 거부(approval_gate) — approve-merge 질문의 PR head {sha[:10]} 가 {remote}/{branch} 를 품지 않음 · 먼저 main 따라잡기(ft-head-sync) 뒤 새 sha 로 질문 · 게시 0")
        if rc != 0:
            raise PostGuardError(f"게시 거부(approval_gate) — 판정 불가: {sha[:10]} 조상 검사 rc={rc} · 게시 0")


def with_status_head(text: str) -> str:
    """사람 채널 글 머리에 planner 카운팅 첫 줄을 붙인다(r1089) — 이미 같은 머리줄로 시작하면 그대로(재시도 중복 0)."""
    from status_head import head  # 순환 import 회피 — status_head 가 루트 규칙을 post_guard 에서 가져온다

    line = head()
    return text if text.startswith(line) else f"{line}\n{text}"


def desk_channel() -> str:
    env = os.environ.get(DESK_CHANNEL_ENV, "").strip()
    if env:
        return env
    roster = Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT) / ".fable-team" / "seats-planner.json"
    try:
        data = json.loads(roster.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise PostGuardError(f"desk 채널 판정 불가 — planner 명부 읽기 실패: {type(e).__name__}") from e
    if not isinstance(data, dict):
        raise PostGuardError("desk 채널 판정 불가 — planner 명부 형식 손상")
    value = data.get("_slack_channel")
    channels = [value] if isinstance(value, str) else value
    if isinstance(channels, list) and channels and isinstance(channels[0], str) and channels[0].strip():
        return channels[0].strip()
    raise PostGuardError("desk 채널 판정 불가 — BYZ_DESK_CHANNEL·planner 명부 값 없음")


def desk_copy(base: str, token: str, channel: str, ts: str, text: str, head: str | None = None) -> None:
    if lib.desk_head(head if head is not None else text) is None:
        return
    destination = desk_channel()
    if channel == destination:
        return
    from mirror_desk import desk_text

    mention = os.environ.get(DESK_MENTION_ENV, "").strip() or lib.DESK_MENTION
    copy = desk_text(text, mention) + f"\n(desk-copy {channel} {ts})"
    check(copy, destination, human=True)
    post(base, token, destination, copy)


def guarded_post(base: str, token: str, channel: str, text: str, thread_ts: str | None = None, *,
                 human: bool = False, head: str | None = None) -> str:
    """사람 채널이면 카운팅 머리줄을 붙인 «뒤» 검사한다(머리줄도 내부어 검사를 지난다 · R7)."""
    is_human = human or channel in human_channels()  # 명부는 한 번만 읽는다
    if is_human:
        text = with_status_head(text)
    check(text, channel, human=is_human)
    approval_gate(text)
    ts = post(base, token, channel, text, thread_ts)
    desk_copy(base, token, channel, ts, text, head)
    return ts
