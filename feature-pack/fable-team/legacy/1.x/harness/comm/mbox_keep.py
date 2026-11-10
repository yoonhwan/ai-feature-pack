# mbox 큐 넘침 시 «버리는 순서» — 사람 글 보존 (r912) · mbox_ops.send 가 부른다 · 200줄 규칙 분리.
"""★버리는 순서 = 시스템 알림 → 일반 쪽지 · 사람 글은 «버리지 않는다»★ (r912 · r3 재설계)

실측(2026-10-25 13:18~14:0x · 원장 desk#61): ft-model-swap «교대 불가» 15통이 좌석 큐 10칸을
채워 사람 글(slack-oppa)이 밀렸다 — 오빠 슬랙 3건이 ~45분 무응답.

★r3(반송 r3 · DA⑥) — «무엇이라 썼나»(본문 머리)보다 «누가 보냈나»(보낸 이)가 믿을 만하다★:
머리글은 누구나 붙인다. ft-tick 이 보내는 [HIL]·ft-news 가 보내는 [긴급] 은 «자동»인데도
머리만 보면 사람 칸을 채워 큐가 끝없이 자랐다(DA⑥ 반례 2). 그래서 분류는 «먼저 보낸 이» 다.

  HUMAN  = slack-oppa · 또는 «좌석»(byz-<팀>-<역할>-<에이전트>#N) 이 보낸 [HIL]·[긴급]
  SYSTEM = 자동 도구 보낸 이(SYSTEM_SENDERS) — 머리 유무로 두 등급(SYS_PLAIN → SYS_HEAD)
  NORMAL = 그 밖(좌석↔좌석 쪽지)
  버리는 순서 = SYS_PLAIN → SYS_HEAD → NORMAL · HUMAN 은 안 버린다(넘치면 ERROR 1줄 · 그대로).

★같은 규칙이 «세 곳»에서 큐를 자른다★ — 이 파일(comm/mbox_ops.py 경로) · kit/ft-mbox.py ·
skill/ft-mbox.py. 세 사본은 «바이트 동일» 블록이고 시험(tests/test_mbox_keep_human_mail.sh ⓘ)이
셋을 대조한다 — 한 곳만 고치면 그 경로로 사람 글이 다시 버려진다(DA⑥ 반례 1).
"""
# >>> r912 mbox_keep shared begin — 이 블록은 세 곳(harness/comm/mbox_keep.py · harness/kit/fable-team/bin/ft-mbox.py · skill/scripts/ft-mbox.py)에 바이트 동일로 박힌다(tests/test_mbox_keep_human_mail.sh ⓘ 대조). 고칠 때는 셋을 같이 고친다.
import os as _os
import re as _re
from functools import lru_cache as _lru_cache
from pathlib import Path as _Path

HUMAN_SENDERS = frozenset({"slack-oppa"})     # 사람(오빠 슬랙) 보낸 이 — 절대 안 버린다
HUMAN_HEADS = ("[HIL]", "[긴급]")              # 사람 판정 머리(보낸 이가 좌석일 때만 사람으로 본다)
# 자동 보낸 이 = 틱·경보·교대 도구(mailbox.log.jsonl 실측 상위 2026-10-25 · 좌석 이름 제외).
SYSTEM_SENDERS = frozenset({
    "ft-tick", "ft-head-lag", "ft-model-swap", "ft-api-outage", "ft-decision-count",
    "ft-stall-scan", "ft-watch-alarm", "os-goal-tick", "ft-ledger-fill", "ft-launchd-check",
    "ft-index-move", "ft-resource-watch", "ft-disk-alarm", "ft-news-ledger", "ft-secret-scan",
    "ft-broadcast",
})
NAME_LINT = "ft-name-lint.sh"                 # 좌석 이름 문법 정본 — 역할·에이전트 예약어도 이 파일 하나에서 읽는다(사본 0)
_BASE_CHARS = frozenset("abcdefghijklmnopqrstuvwxyz0123456789-")
_DIGITS = frozenset("0123456789")
SYS_PLAIN, SYS_HEAD, NORMAL, HUMAN = 0, 1, 2, 3   # 작을수록 «먼저 버린다» · HUMAN 은 안 버린다


@_lru_cache(maxsize=8)
def _grammar(lint: str) -> tuple[frozenset, frozenset]:
    """ft-name-lint.sh 의 `ROLES="…"` · `AGENTS="…"` 두 줄만 읽어 (역할, 에이전트) 로 — 목록 사본 0.
    ★스크립트를 «부르지» 않고 «읽는» 이유★: 1회 0.46초(2026-10-25 실측 · macOS bash 기동)라
    이름마다 부르면 mbox send 한 번에 수 초가 붙는다. 문법 자체는 아래 seat() 가 같은 순서로 본다.
    """
    txt = _Path(lint).read_text(encoding="utf-8")
    def val(tag: str) -> frozenset:
        m = _re.search(rf'^{tag}="([^"]*)"', txt, _re.M)
        return frozenset(m.group(1).split()) if m else frozenset()
    return val("ROLES"), val("AGENTS")


def _lint_file() -> str:
    """이 사본 옆의 ft-name-lint.sh — comm/(../bin) · kit/bin/(같은 폴더) · skill/scripts/(../../harness/bin).
    없으면 "" → seat() 가 «좌석 아님» 으로 본다(사람 칸을 넓히면 큐가 끝없이 자란다 · DA⑥ 반례 1).
    """
    if env := _os.environ.get("FT_NAME_LINT"):
        return env
    base = _Path(__file__).resolve().parent
    for d in (base, *list(base.parents)[:3]):
        for c in (d / NAME_LINT, d / "bin" / NAME_LINT, d / "harness" / "bin" / NAME_LINT):
            if c.is_file():
                return str(c)
    return ""


LINT = _lint_file()


def seat(name: str) -> bool:
    """좌석 이름인가 — ft-name-lint.sh 문법 그대로(<프로젝트>-<팀>-<역할>[-꼬리]#N · 길이 ≤60 · 소문자·숫자·'-' · 빈 토큰 0).

    ★r4 재설계★ 옛 정규식(`byz-…#N`)은 `byz-tool#0` 처럼 «역할·에이전트 칸»이 없는 이름도 좌석으로
    읽어 [HIL] 25통을 전부 사람 칸에 넣었다(DA⑥ 반례 1). 역할 예약어 11 · 에이전트 5 는 손으로 적지
    않고 ft-name-lint.sh 에서 읽는다 — 꼬리 규칙도 그 스크립트와 같다: nano = 카드 slug(필수),
    그 밖의 역할 = 에이전트 하나(claude|codex|opencode|cmd|pi).
    """
    base, sep, gen = name.partition("#")
    if not sep or "#" in base or len(name) > 60 or not gen or not set(gen) <= _DIGITS:
        return False                              # 계보 번호 없음/둘/비정수 · 길이 60 초과
    toks = base.split("-")
    if len(toks) < 4 or not all(toks) or not set(base) <= _BASE_CHARS:
        return False                              # 토큰 부족(프로젝트·팀·역할·꼬리) · 빈 토큰 · 허용 밖 문자
    try:
        roles, agents = _grammar(LINT) if LINT else (frozenset(), frozenset())
    except (OSError, ValueError):
        return False                              # 정본을 못 읽으면 «좌석 아님»(안전한 쪽)
    role, tail = toks[2], "-".join(toks[3:])
    return role in roles and (bool(tail) if role == "nano" else tail in agents)


def kind(r):
    """행 하나의 등급 — 버리는 순서는 이 값의 «오름차순»(SYS_PLAIN → SYS_HEAD → NORMAL), HUMAN 은 제외."""
    frm = str(r.get("from") or "")
    head = str(r.get("body") or "").lstrip().startswith(HUMAN_HEADS)
    if frm in HUMAN_SENDERS:
        return HUMAN                      # 보낸 이가 사람 — 머리와 무관
    if frm in SYSTEM_SENDERS:
        return SYS_HEAD if head else SYS_PLAIN   # 자동 도구는 머리가 있어도 «자동»(사람 칸 0)
    if head and seat(frm):
        return HUMAN                      # 좌석이 올린 [HIL]·[긴급] = 사람 판정 대상
    return NORMAL


def trim(rows, keep_n):
    """한 수신자의 행(seq 오름차순) → (keep, dropped, oldest, overflow).

    keep_n 을 넘으면 SYS_PLAIN → SYS_HEAD → NORMAL 순서로, 같은 등급 안에서는 오래된 것부터
    버린다. 사람 글만 남아 상한을 넘기면 ★버리기 0★ + overflow > 0 으로 돌려준다(부르는 쪽이
    ERROR 1줄을 찍는다 — 조용히 넘기지 않는다).
    oldest = 버린 것 중 가장 오래된 seq(없으면 None) · overflow = 사람 글 때문에 남긴 초과분.
    """
    over = len(rows) - keep_n
    if over <= 0:
        return rows, 0, None, 0
    order = sorted(rows, key=lambda r: (kind(r), r["seq"]))   # 자동(머리없음) 먼저 · 같은 등급은 오래된 것부터
    drop = {r["seq"] for r in order[:over] if kind(r) != HUMAN}
    keep = [r for r in rows if r["seq"] not in drop]
    return keep, len(drop), (min(drop) if drop else None), len(keep) - keep_n
# <<< r912 mbox_keep shared end
