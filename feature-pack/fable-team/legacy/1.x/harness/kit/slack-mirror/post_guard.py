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
FENCE, TABLE_RULE = re.compile(r"```.*?(?:```|\Z)", re.S), re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$")  # r1927
HUMAN_CHANNELS_ENV = "BYZ_HUMAN_CHANNELS"
ROOT_ENV = "FT_ROOT"
DEFAULT_ROOT = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"  # ~/.hermes/scripts 에서 불려도 명부에 닿는 고정 기본값
DESK_CHANNEL_ENV = "BYZ_DESK_CHANNEL"
DESK_MENTION_ENV = "BYZ_DESK_MENTION"
GATE_REPOS_ENV = "FT_APPROVAL_GATE_REPOS"  # 콜론 목록 · 기본 = 루트 + 팩 리포 (r1275 단계 4)
GATE_TARGET_ENV = "FT_APPROVAL_GATE_TARGET"  # 기본 origin/main
DEFAULT_PACK_REPO = "/Users/yoonhwan/Project/ai-feature-pack"
SHA40 = re.compile(r"(?<![0-9a-fA-F])[0-9a-f]{40}(?![0-9a-fA-F])")
MERGE_WORD, ASK, PR_REF = re.compile(r"머지|병합|merge", re.I), re.compile(r"할까요|\?"), re.compile(r"(PR|Issue|이슈)?\s*#([0-9]+)", re.I)  # r1710 머지 질문
URL = re.compile(r"\S+://\S+")  # r1710 보정 1 — 링크 안 물음표는 묻는 꼴이 아니다


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


def has_table(text: str) -> bool:
    """r1927 마크다운 표 = 파이프 2개 이상 줄 다음 구분선 줄 · 코드 블록(```) 안 = 제외."""
    lines = FENCE.sub("", text).splitlines()
    return any(a.count("|") >= 2 and TABLE_RULE.match(b) for a, b in zip(lines, lines[1:]))


PATH_ALLOW = frozenset({"abs-path", "worktree-path"})  # 면제할 수 있는 2묶음 칸은 이 둘뿐 — 비밀(묶음1)·나머지 2묶음 면제 길 0 (r1275 단계 5)
PATH_ASK = re.compile(r"풀\s*패스|절대\s*경로|폴더\s*주소|파일\s*경로|경로\s*(알려|줘|좀|보내)|full\s*path", re.I)


def path_allow(asked_text: object) -> frozenset[str]:
    """오빠 글 원문에 경로 요청 낱말이 있을 때만 경로 두 칸 면제 · 원문 없음·비었음·문자열 아님 = 면제 0(조용한 통과 0)."""
    return PATH_ALLOW if isinstance(asked_text, str) and PATH_ASK.search(asked_text) else frozenset()


def check(text: str, channel: str, *, human: bool = False, allow: frozenset[str] = frozenset()) -> None:
    """걸리면 PostGuardError. human=True 이거나 channel 이 사람 채널이면 2묶음도 건다. allow ⊄ PATH_ALLOW 면 ValueError."""
    if not set(allow) <= PATH_ALLOW:
        raise ValueError(f"post_guard allow 는 {sorted(PATH_ALLOW)} 의 부분집합만: {sorted(set(allow) - PATH_ALLOW)}")
    found = [f"묶음1:{n}" for n in _hits(text, SECRETS)]
    if human or channel in human_channels():
        found += [f"묶음2:{n}" for n in _hits(text, {k: v for k, v in INTERNAL.items() if k not in allow})]
        found += ["묶음2:마크다운 표"] if has_table(text) else []
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


def approval_gate(text: str, human: bool = False) -> None:
    """approve-merge 질문 글(본문에 approve-merge + 40hex sha)은 그 sha(PR head)가 origin/main 을 품을 때만 나간다 —
    질문 때 PR 이 옛 main 위면 승인 뒤 main 병합으로 head 가 바뀌어 같은 질문이 되풀이된다(r1275 단계 4 · 판정 3932).
    품지 않음 = 게시 0 «먼저 main 따라잡기» · 조회 실패 = 게시 0 «판정 불가»(조용한 통과 0) · approve-merge 낱말 없음 = 대상 밖.
    r1710: 사람 채널 «머지 질문»(머지 낱말 ∧ 묻는 꼴 ∧ PR 번호)은 PR 마다 40hex 가 있어야 나가고, 그 sha 도 같은 조상 검사를 탄다(승인 검사가 질문 글의 sha 를 본다)."""
    shas = sorted(set(SHA40.findall(text)))
    refs = PR_REF.findall(text) if human and MERGE_WORD.search(text) and ASK.search(URL.sub("", text)) else []
    prs = {n for p, n in refs if not p or p.upper() == "PR"}  # «PR #N» 과 맨 «#N» 을 합쳐 센다(Issue·이슈 #N 은 안 셈 · 보정 2 R1)
    if len(shas) < len(prs):
        raise PostGuardError(f"게시 거부(approval_gate) — 머지 질문에 PR head sha(40자)가 없음 · 질문 글에 sha 를 넣어 다시(PR {len(prs)}건 · sha {len(shas)}개) · 게시 0")
    if not shas or not (prs or "approve-merge" in text):
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


def desk_copy(base: str, token: str, channel: str, ts: str, text: str, head: str | None = None,
              allow: frozenset[str] = frozenset()) -> None:
    if lib.desk_head(head if head is not None else text) is None:
        return
    destination = desk_channel()
    if channel == destination:
        return
    from mirror_desk import desk_text

    mention = os.environ.get(DESK_MENTION_ENV, "").strip() or lib.DESK_MENTION
    copy = desk_text(text, mention) + f"\n(desk-copy {channel} {ts})"
    check(copy, destination, human=True, allow=allow)
    post(base, token, destination, copy)


def guarded_post(base: str, token: str, channel: str, text: str, thread_ts: str | None = None, *,
                 human: bool = False, head: str | None = None, allow: frozenset[str] = frozenset()) -> str:
    """사람 채널이면 카운팅 머리줄을 붙인 «뒤» 검사한다(머리줄도 내부어 검사를 지난다 · R7). allow = 경로 두 칸 면제(기본 빈 집합 = 지금과 같음)."""
    is_human = human or channel in human_channels()  # 명부는 한 번만 읽는다
    if is_human:
        text = with_status_head(text)
    check(text, channel, human=is_human, allow=allow)
    approval_gate(text, is_human)
    ts = post(base, token, channel, text, thread_ts)
    desk_copy(base, token, channel, ts, text, head, allow)
    return ts
