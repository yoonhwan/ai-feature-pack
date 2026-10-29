#!/usr/bin/env python3
"""파일 기반 세션 메시지 큐 (fable-team). LIFO·per-to ring·fcntl.flock·consume-on-read·to==me grep.
v6-realtime-live mbox.py 계승 + 팩 추가분: FT_MBOX_DIR 경로 주입·세션명 allowlist·READ 출력·from 필터.

★2026-08-25 — 우편함이 «셋으로 갈라져» 메시지가 유실되던 것을 고친다★
이전: 데이터 경로가 «cwd 기준»이라, 같은 스크립트를 불러도 부른 사람의 cwd 에 따라 다른
우편함을 썼다 — 보낸 쪽과 받는 쪽이 서로 다른 파일을 보는 사고가 실제로 났다.
지금: ★send 는 «정본» 하나에만 쓰고, recv/peek 는 «정본+레거시»를 전부 읽는다(union)★.
union 을 두는 이유 — 경로를 «순간에» 바꾸면 바꾸기 직전 큐잉된 메시지가 옛 파일에 남아
★아무도 안 읽는다★. 레거시가 전부 0행이 되면 그때 걷어낸다(그 판단은 별도).
"""

import sys
import os
import re
import json
import time
import fcntl
import hashlib
import shutil
import glob
import subprocess


def _role_key(name):
    """★우편함 키 = 역할 이름(r1116 · 판정 2777)★ — 세션 번호 «#N» 은 표시만(comm/mbox_conf.role_key 와 같은 규칙)."""
    return re.sub(r"#\d+$", "", name or "")

MAX_PER_TO = int(os.environ.get("FT_MBOX_RING") or 10)
# 세션명 allowlist — 세션명이 doorbell 명령 문자열에 삽입되므로 하드 거부(명령 삽입 원천 차단).
NAME_RE = re.compile(r"^[A-Za-z0-9._#-]+$")

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

# ── 발신 규율 물리 가드 (COMM-GUIDE §1.5) ──────────────────────────────
# 홍수는 사용자 입력을 막고, ring(MAX_PER_TO) 상한을 넘긴 메시지를 조용히 유실시킨다.
# ★2026-09-05 — 길이는 «발신 차단»이 아니라 «수신 절단» 기준이다★
#   상한으로 send 를 실패시켰더니 사람이 배운 것은 relay 가 아니라 `--force` 였다:
#   실측(2026-09-05) 정본 큐 51건 중 ★16건(31%)이 700자 초과★인데 relay 형식은 ★0건★.
#   차단은 규율을 «가르치지 못했고», 대신 «막히면 --force» 라는 우회를 가르쳤다.
#   ⇒ ①send 는 길이로 막지 않는다 ②700자를 넘으면 전문을 파일에 «먼저» 박는다
#     ③recv 가 잘라 읽고 전문 경로를 함께 준다.
#   받는 쪽 컨텍스트는 그대로 보호되고(태우는 것은 «읽는 쪽»이다), 보내는 쪽은 아무것도
#   잃지 않는다. relay 는 여전히 최선이다 — 사람이 쓴 요약은 기계 절단이 못 만든다.
MAX_BODY = int(os.environ.get("FT_MBOX_MAX_BODY") or 700)  # 본문 «절단» 기준(3~5줄)
FANOUT_WIN = int(os.environ.get("FT_MBOX_FANOUT_WINDOW") or 600)  # 동일 본문 다중 좌석 판정 창(초)
RATE_N = int(os.environ.get("FT_MBOX_RATE_N") or 5)  # from당 발신 건수
RATE_WIN = int(os.environ.get("FT_MBOX_RATE_WINDOW") or 60)  # 그 창(초)
# ★2026-09-02 재발신 쿨다운★ — 큐잉은 «가져가기» 방식이므로 pending 동안 재발신 금지.
# N초 경과 후 1회 허용(재발신이 기록을 갱신하므로 자연히 «1회씩»). 그 전엔 pane 캡처로 확인.
RESEND_COOL = int(os.environ.get("FT_MBOX_RESEND_COOLDOWN") or 300)
RECV_LIMIT = int(os.environ.get("FT_MBOX_RECV_LIMIT") or 5)  # recv 기본 표시 건수
RELAY_DIR = os.environ.get("FT_MBOX_RELAY_DIR") or "/tmp/mbox"  # 긴 본문의 정본 자리
# ★2026-09-06 — 전문 파일은 «시간»으로 자른다★
#   bodies/<seq>.txt 는 행이 recv 로 소비돼도 남는다. 그래야 하는 이유가 있다 —
#   그 경로는 보고서·인계 문서에 «인용»되어 3~4일 뒤에 열린다(실측). 소비 시점에
#   지우면 그 인용이 죽는다. ⇒ ★«소비 여부»가 아니라 «시간»이 기준이다★.
#   14일 근거: 좌석 수명 실측 median 2.6일 · p90/max 4.2일 → p90 의 3배 여유.
#   비용은 건당 4KB(gitignore 아래)라 여유를 크게 잡는 편이 싸다.
BODIES_TTL_DAYS = int(os.environ.get("FT_MBOX_BODIES_TTL_DAYS") or 14)
BODIES_PRUNE_EVERY = 3600  # 청소 주기(초) — 매 send 마다 listdir 하지 않는다.
# ★보낸 행의 «추가 전용» 사본 (r488 · 출처 = 루트 mbox_conf.py:40-41 그대로)★
#   mailbox.jsonl 은 consume-on-read 라 recv 하면 행이 사라진다. 이 사본이 없으면 소비된 쪽지의
#   레코드가 어디에도 없어 가드(ft_da_hold_gate)·보드·미러가 «쪽지 없음»으로 판정한다.
#   한도 초과 시 `.1`~`.<SENT_LOG_KEEP>` 로 «밀어» 보관한다(r553) — 한 벌만 남기면 바쁜 날 보관이
#   약 10시간이라 매거진 24시간 창을 못 덮는다. 파일 하나의 크기는 그대로다(무한 증가 0).
SENT_LOG = "mailbox.log.jsonl"
SENT_LOG_MAX_BYTES = int(os.environ.get("FT_MBOX_LOG_MAX_BYTES") or 5 * 1024 * 1024)
SENT_LOG_KEEP = max(1, int(os.environ.get("FT_MBOX_LOG_KEEP") or 3))


def _repo_root(start):
    """★정본 자리를 «유도»한다 — 하드코딩 금지★.

    이 파일 위쪽의 `.fable-team` 을 찾고, 그 부모가 `.worktrees/<x>` 면 리포 루트는 두 단계
    위다. ★워크트리 «안»이 아니라 «밖»을 정본으로 잡는 이유★: 워크트리는 정리되면 사라지고,
    그날 그 안의 우편함을 쓰던 세션이 전부 끊긴다.
    """
    d = os.path.abspath(start)
    while d != os.path.dirname(d):
        if os.path.basename(d) == ".fable-team":
            parent = os.path.dirname(d)
            # ★워크트리 이름이 «한 단계»라는 보장이 없다★ (2026-09-03 실측)
            #   브랜치명에 슬래시가 있으면 `.worktrees/feat/loom-pack-layer` 처럼 두 단계가
            #   된다(BYZ 에 실존). 조부모만 보고 판정하면 그 경우 `.worktrees` 를 못 만나
            #   ★자기 워크트리 «안»을 정본으로 잡아 조용히 별도 우편함을 판다★ — 에러가
            #   안 나고 send/recv 는 성공하므로, 그 좌석만 아무에게도 안 닿는다.
            #   그래서 깊이를 가정하지 않고 «`.worktrees` 조상을 만날 때까지» 올라간다.
            a = parent
            while a != os.path.dirname(a):
                if os.path.basename(a) == ".worktrees":
                    return os.path.dirname(a)
                a = os.path.dirname(a)
            return parent
        d = os.path.dirname(d)
    return None  # ★F4: .fable-team 조상이 없으면 정본을 «유도할 수 없다» — 조용히 만들지 않는다.


def _cwd_common_comm():
    """③ cwd 의 git 공용 루트 `<루트>/.fable-team/comm` — ★«이미 실재» 할 때만★ (r403 · 2026-10-19).

    라이브 bin(`~/.claude/fable-team/live/<v>/bin`)엔 `.fable-team` 조상이 없어 ② 가 늘 None 이다
    (cwd 무관 NO_MAILBOX_ROOT · master 109989 실측). 그래서 «부른 곳의 리포 루트» 를 본다 —
    워크트리여도 `--git-common-dir` 의 부모는 리포 루트라 워크트리 «안» 을 정본으로 잡지 않는다.
    ★실재 조건이라 우편함을 새로 파지 않는다(F4)★. 반환 = (루트|None, comm|None).
    """
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=7,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, None
    if r.returncode != 0 or not r.stdout.strip():
        return None, None
    root = os.path.dirname(r.stdout.strip())
    comm = os.path.join(root, ".fable-team", "comm")
    return root, (comm if os.path.isdir(comm) else None)


_ROOT = _repo_root(os.path.dirname(os.path.abspath(__file__)))
# ★루트 순서 (r403 · sh `_mbox_dir` 와 같은 걸음)★: ①명시 FT_MBOX_DIR ②스크립트 조상 `.fable-team`
#   ③cwd git 공용 루트의 `.fable-team/comm` «실재» ④NO_MAILBOX_ROOT rc2.
# ★명시가 추론을 이긴다★ — env 로 준 FT_MBOX_DIR 은 그대로 존중한다(이전엔 래퍼가 덮어썼다).
# ★F4: 어느 단계도 못 찾으면 fail-loud — 스크립트 디렉토리 «안»에 우편함을 만들지 않는다.
CANON = os.environ.get("FT_MBOX_DIR") or (
    os.path.join(_ROOT, ".fable-team", "comm") if _ROOT else None
)
if CANON:
    os.makedirs(CANON, exist_ok=True)  # 생성은 ①② 만 — ③ 은 실재 조건이다.
else:
    _GIT_ROOT, CANON = _cwd_common_comm()
    if not CANON:
        sys.stderr.write(
            "NO_MAILBOX_ROOT: .fable-team 조상 없음 — FT_MBOX_DIR 를 지정하라\n"
            "cwd 공용 루트 %s 에도 comm 없음\n" % (_GIT_ROOT or "(git 리포 아님)")
        )
        sys.exit(2)
    _ROOT = _GIT_ROOT


def _legacy_dirs():
    """레거시 우편함 — ★기본은 «없음»★ (2026-09-14 · 하네스 업그레이드 §4-1 · 오빠 결정 Q2).

    ★왜 union 을 걷었나 (실측 2026-09-14)★
      · 워크트리 `.fable-team` 이 루트로 가는 «심링크»인 곳(v65-input-admission·proof-store)이
        glob 에 잡혀 ★같은 inode 를 3번 읽었다★ — 좌석마다 recv 가 같은 메시지를 `(legacy)`
        꼬리로 세 번 찍었고(#13038·#13041·#13046), 모든 좌석의 recv 컨텍스트가 3배였다.
      · 남은 레거시 파일은 c-level(1행, 09-09)·v6-realtime-live 워크트리(77행, 전부 08-24 이전,
        수신 좌석 26종 «전부 사망»)·나머지 0행 — 살아 있는 좌석 앞으로 온 행은 0 이었다.
      · 트랙이 다른 우편함(c-level·loom)이 v65 좌석 recv 에 섞일 이유도 없다.
    ★되돌리는 문은 남긴다★ — `FT_MBOX_LEGACY=1` 이면 예전 union(중복은 realpath 로 제거)을 돈다.
      옛 파일에 뭔가 남았다고 의심될 때 «한 번» 켜서 보고 끄는 용도다. 기본값으로 켜 두지 않는다.
    """
    if not _ROOT or os.environ.get("FT_MBOX_LEGACY") != "1":
        return []
    out, seen, wt = [], {os.path.realpath(CANON)}, os.path.join(_ROOT, ".worktrees")
    if os.path.isdir(wt):
        for depth in (1, 2, 3):
            pat = os.path.join(wt, *(["*"] * depth), ".fable-team", "comm")
            for d in sorted(glob.glob(pat)):
                rp = os.path.realpath(d)
                # ★realpath 로 가른다★ — abspath 는 심링크를 못 본다. 같은 파일을 두 번 읽지 않는다.
                if os.path.isdir(d) and rp not in seen:
                    seen.add(rp)
                    out.append(d)
    return out


def _mbox(d):
    return os.path.join(d, "mailbox.jsonl")


def _bodies_dir(d):
    return os.path.join(d, "bodies")


def _stash_body(d, seq, body):
    """★전문을 «큐에 넣기 전»에 우편함 안에 박는다★ (2026-09-05).

    ★/tmp 를 쓰지 않는다★ — `/tmp/mbox` 는 relay 스냅샷 자리라 섞이면 둘 다 못 믿게 되고,
    /tmp 는 재부팅에 비워진다. 여기(우편함 디렉터리)는 gitignore 아래이고 ★우편함과 수명이
    같다★ — 행이 살아 있는 한 전문도 살아 있다.

    ★실패하면 None 을 돌려준다★ — 그러면 recv 가 «자르지 않는다»(_clip 참조).
    되찾을 수 없는 절단은 받는 쪽에서의 유실이고, 그건 이 개정이 없애려던 병 그 자체다.
    """
    try:
        bd = _bodies_dir(d)
        os.makedirs(bd, exist_ok=True)
        p = os.path.join(bd, "%d.txt" % seq)
        with open(p, "w", encoding="utf-8") as f:
            f.write(body)
        return p
    except OSError:
        return None


def _clip(r):
    """★수신측 절단★ (2026-09-05) — MAX_BODY 를 넘으면 잘라 주고 전문 경로를 붙인다.

    ★RECV_LIMIT(표시 «건수» 5)과 다른 축이다★ — 저건 «몇 건을 보여줄까», 이건 «한 건을
    얼마나 보여줄까». 둘을 섞으면 «5건 넘게 왔는데 안 보인다»와 «본문이 잘렸다»가
    같은 증상으로 보인다.

    ★전문을 «되찾을 수 있을 때만» 자른다★ — body_full 이 없거나(구버전이 큐잉한 행)
    파일이 사라졌으면 통째로 출력한다.
    """
    body = r.get("body", "")
    if len(body) <= MAX_BODY:
        return body, None
    full = r.get("body_full")
    if not full or not os.path.exists(full):
        return body, None
    return body[:MAX_BODY], "전문: %s (%d자)" % (full, len(body))


def _prune_bodies(d):
    """★TTL 지난 전문 파일을 지운다★ (2026-09-06) — 보존 BODIES_TTL_DAYS 일.

    ★«소비 여부»가 아니라 «시간»으로 자른다★ — 근거는 BODIES_TTL_DAYS 주석.

    설계 제약 셋 — 전부 «청소가 통신을 해치지 않게» 하려는 것이다:
      ①★send 를 막지 않는다★ — 전체를 삼킨다(except Exception: pass).
        청소 실패는 통신 실패보다 훨씬 가볍다. 여기서 예외가 새면 그 send 가 죽는다.
      ②★1시간에 한 번만 돈다★ — `<d>/.bodies-pruned` 스탬프 mtime 으로 억제.
        안 그러면 매 send 가 bodies 전체를 listdir 해 파일 수에 비례해 느려진다.
        ★스탬프를 «청소 전»에 찍는다★ — 중간에 죽어도 다음 send 가 곧바로 재시도해
        같은 비용을 다시 물지 않는다.
      ③★잠금 «밖»에서 부른다★ — _locked 안에서 listdir 하면 잠금 보유 시간이 파일
        수에 비례해 늘고, 그동안 다른 좌석의 send 가 통째로 막힌다.
    """
    try:
        bd = _bodies_dir(d)
        if not os.path.isdir(bd):
            return
        now = time.time()
        stamp = os.path.join(d, ".bodies-pruned")
        try:
            if now - os.path.getmtime(stamp) < BODIES_PRUNE_EVERY:
                return
        except OSError:
            pass  # 스탬프 없음/못 읽음 = 아직 안 돌았다 → 이번에 돈다.
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(str(int(now)))
        cutoff = now - BODIES_TTL_DAYS * 86400
        for name in os.listdir(bd):
            if not name.endswith(".txt"):
                continue
            p = os.path.join(bd, name)
            try:
                if os.path.getmtime(p) < cutoff:
                    os.remove(p)
            except OSError:
                pass  # 한 건이 안 지워져도 나머지는 계속 지운다.
    except Exception:
        pass


# ★seq 는 «파일에 남은 행» 이 아니라 «카운터» 에서 받는다★ (2026-09-03)
#   recv 가 읽은 행을 파일에서 지우므로, max(rows)+1 은 큰 번호가 소비되면 «되감긴다».
#   되감긴 번호는 에러 없이 다른 메시지를 가리켜 조용히 틀린다(격리 실측 30건 중 7건 중복).
_SEQCTR = os.path.join(CANON, ".mbox-seq")
# 부트스트랩 하한. 전수 실측(2026-09-03) 우편함·아카이브 6곳의 max 가 1556 이었다.
# ★1601★ — v6 계보와 번호 공간을 어긋나게 두지 않으려는 하한(첫 seq=1602).
SEQ_FLOOR = int(os.environ.get("FT_MBOX_SEQ_FLOOR") or 1601)


def _next_seq(rows):
    """★high-water mark 를 한 칸 올려 돌려준다★ — 호출자가 이미 mailbox.lock 을 쥐고 있다.

    ★새 잠금을 걸지 않는다★: flock 은 블로킹이라 물고 죽은 프로세스가 send 를 멈춘다.
    같은 잠금 안에서 하므로 원자성은 기존 잠금이 준다.

    ★`rows` 의 max 도 함께 본다★ — 카운터를 모르는 «구버전 사본» 이 같은 우편함에
    큰 번호를 남겼을 때 그것을 덮어쓰지 않기 위해서다. 단 이것이 공존을 안전하게
    만들지는 «않는다» — 구버전은 이 카운터를 안 읽으므로 여전히 되감는다.
    ⇒ ★사본 전부를 동시에 갈아야 한다★. 하나라도 남으면 오염이 계속된다.
    """
    try:
        with open(_SEQCTR, encoding="utf-8") as f:
            hwm = int(f.read().strip())
    except FileNotFoundError:
        hwm = SEQ_FLOOR
    except (ValueError, OSError) as e:
        # ★삼키지 않는다★ — 여기서 파일 max 로 폴백하면 고치려던 그 병으로 되돌아간다.
        raise RuntimeError("mbox seq counter unreadable: %s (%s)" % (_SEQCTR, e))
    seq = max(hwm, max((r.get("seq", 0) for r in rows), default=0)) + 1
    # ★원자적 교체★ — 쓰다 죽어도 반쪽 숫자가 남지 않는다(반쪽은 위 ValueError 로 간다).
    tmp = _SEQCTR + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(str(seq))
    os.replace(tmp, _SEQCTR)
    return seq


def _check_name(n):
    if not n or not NAME_RE.match(n):
        sys.stderr.write("BAD_SESSION_NAME %s\n" % n)
        sys.exit(1)


def _load(d):
    rows, p = [], _mbox(d)
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                try:
                    rows.append(json.loads(ln))
                except Exception:
                    pass
    return rows


def _save(d, rows):
    rows.sort(key=lambda r: r["seq"])
    with open(_mbox(d), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def _locked(d, fn):
    lf = open(os.path.join(d, "mailbox.lock"), "w")
    fcntl.flock(lf, fcntl.LOCK_EX)
    try:
        return fn()
    finally:
        fcntl.flock(lf, fcntl.LOCK_UN)
        lf.close()


def _rotate_sent_log(p):
    """`.<KEEP-1>`→`.<KEEP>` … `.1`→`.2` 로 밀어 보관하고 빈 `.1` 자리를 만든다(있는 것만).

    가장 오래된 벌(`.<KEEP>`)은 덮여 사라진다 — 그 밖으로 밀린 것만 잃는다(루트 모듈판과 같은 꼴).
    """
    for n in range(SENT_LOG_KEEP - 1, 0, -1):
        src = "%s.%d" % (p, n)
        if os.path.exists(src):
            os.replace(src, "%s.%d" % (p, n + 1))


def _log_sent(d, row):
    """보낸 행을 추가 전용 사본에 1줄 쓴다(r488 · r553 밀어 보관).

    실패해도 send 는 산다 — 단 «조용히» 삼키지 않고 stderr WARN 으로 드러낸다. 우편함 잠금 안에서 부른다.
    """
    p = os.path.join(d, SENT_LOG)
    try:
        if os.path.exists(p) and os.path.getsize(p) > SENT_LOG_MAX_BYTES:
            _rotate_sent_log(p)
            os.replace(p, p + ".1")
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError as e:
        sys.stderr.write("WARN %s 사본 기록 실패(%s) — 이 행은 recv 뒤 레코드가 남지 않는다. 큐에는 정상 적재됨.\n"
                         % (SENT_LOG, type(e).__name__))


_GUARD = os.path.join(CANON, ".mbox-guard.json")


def _guard_log():
    try:
        with open(_GUARD, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def _body_hash(body):
    # ★F2: 전문 해시 — 앞 200자만 보면 같은 템플릿 헤더로 시작하는 다른 보고가 오탐된다.
    return hashlib.md5(body.encode("utf-8")).hexdigest()


def _guard_record(to, frm, body):
    now = time.time()
    log = [r for r in _guard_log() if now - r.get("t", 0) < max(FANOUT_WIN, RATE_WIN)]
    log.append({"t": now, "f": frm, "to": to, "h": _body_hash(body)})
    with open(_GUARD, "w", encoding="utf-8") as f:
        json.dump(log[-200:], f)


def _is_tool_sender(frm):
    """도구 발신자 = `ft-` 접두 + `#N` 없음(예 `ft-head-lag`) — 팀당 1통 fan-out 이 일이라 FANOUT·RATE 면제(R380). `--dispatch` 면제(doorbell 강제)와 별개."""
    return frm.startswith("ft-") and "#" not in frm


def _guard_verdict(to, frm, body, dispatch=False):
    """통과면 None, 아니면 (reason, hint). 판정만 하고 기록은 _guard_record 가 한다."""
    if not body.strip():
        return ("EMPTY_BODY", "빈 메시지는 받는 쪽을 깨우기만 하고 아무것도 전하지 않는다.")
    # ★F5: 발주(--dispatch)는 EMPTY_BODY만 판정 — RESEND·FANOUT·RATE 면제(좌석마다 동일 본문 연속 주입).
    if dispatch:
        return None
    # ★길이로 막지 않는다★ (2026-09-05, BODY_TOO_LONG 제거) — 근거는 MAX_BODY 주석.
    #   긴 본문은 send 가 전문을 파일에 박고 recv 가 잘라 읽는다. 상한이 가르친 것은
    #   relay 가 아니라 --force 였고, 우회를 가르치는 가드는 규율이 아니라 소음이다.
    now = time.time()
    log = _guard_log()
    h = _body_hash(body)
    # ★F1: 발신 기록 시각이 아니라 «실제 큐»에 같은 본문이 pending 인지로 판정 — 소비됐으면 통과.
    dup = next(
        (
            r
            for r in _load(CANON)
            if r.get("from") == frm and _role_key(r.get("to")) == _role_key(to) and _body_hash(r.get("body", "")) == h
        ),
        None,
    )
    last = max(
        (r.get("t", 0) for r in log if r.get("f") == frm and _role_key(r.get("to")) == _role_key(to) and r.get("h") == h),
        default=0,
    )
    if dup and last and now - last < RESEND_COOL:
        return (
            "RESEND_COOLDOWN from=%s to=%s seq=%s %ds<%ds"
            % (frm, to, dup.get("seq"), int(now - last), RESEND_COOL),
            "같은 본문이 큐에 pending(seq=%s) — 받는 쪽이 «가져갈» 때까지 기다린다. "
            "pending 동안 재발신 금지. 수신 여부가 궁금하면 pane 캡처로 확인하고, "
            "%ds 경과 후 1회만 재발신한다(소비되거나 시간이 지나면 자동 통과)."
            % (dup.get("seq"), RESEND_COOL),
        )
    tool, skipped = _is_tool_sender(frm), []
    others = sorted(
        {
            _role_key(r["to"])
            for r in log
            if r.get("f") == frm
            and r.get("h") == h
            and _role_key(r.get("to")) != _role_key(to)
            and now - r.get("t", 0) < FANOUT_WIN
        }
    )
    if others and tool:
        others, skipped = [], skipped + ["fanout"]
    if others:
        return (
            "FANOUT from=%s already_sent_to=%s" % (frm, ",".join(others)),
            "같은 본문을 여러 좌석에 뿌리지 않는다 — 필요한 한 좌석만. "
            "공지가 필요하면 파일에 쓰고 경로만 알린다.",
        )
    recent = sum(1 for r in log if r.get("f") == frm and now - r.get("t", 0) < RATE_WIN)
    if recent >= RATE_N and tool:
        skipped.append("rate")
    elif recent >= RATE_N:
        return (
            "RATE_LIMIT from=%s %d sends/%ds" % (frm, recent, RATE_WIN),
            "연속 발신 상한. 받는 쪽이 읽고 답할 시간을 준다.",
        )
    if skipped:
        sys.stderr.write("TOOL_SENDER from=%s exempt=%s\n" % (frm, ",".join(skipped)))
    return None


def _desk_verdict(to, frm, body, attach=""):
    """desk 판정기(ft_desk_route_gate.py) 호출 — 통과면 None, 막으면 (reason, hint).
    ★판정 자리 = python send 층 하나★(r660 · DA⑥ r1 ⓒ) — 셸·python 직접·relay 전부 여기를 지난다. 판정기 고장 = REJECT(fail-closed).
    유일한 예외 = 판정기 «파일 없음»(설치 순서)일 때 이름에 -desk- 가 걸린 쪽지만 막는 것."""
    gate = os.environ.get("FT_DESK_GATE") or os.path.join(os.path.dirname(os.path.realpath(__file__)), "ft_desk_route_gate.py")
    hint = "desk 는 planner 에게만 보내고, desk 에는 planner 가 보냅니다(planner 안내서 27줄) — 그 밖 길은 planner 를 거치세요."
    if not os.path.isfile(gate):
        if "-desk-" in to or "-desk-" in frm:
            return ("DESK_ROUTE_GATE_MISSING 판정기 없음(%s) — 설치 순서 · desk 쪽지 통과 0" % gate, hint)
        sys.stderr.write("WARN desk 경로 판정기 없음(%s) — 설치 순서 · desk 무관 쪽지 통과\n" % gate)
        return None
    os.makedirs(RELAY_DIR, exist_ok=True)
    stamp = "%d-%d" % (os.getpid(), int(time.time() * 1000) % 100000)
    bf = os.path.join(RELAY_DIR, ".desk-route-%s.txt" % stamp)
    af = os.path.join(RELAY_DIR, ".desk-route-%s-attach.txt" % stamp) if attach else ""
    try:
        with open(bf, "w", encoding="utf-8") as f:
            f.write(body)
        cmd = [sys.executable, gate, "--to", to, "--from", frm, "--body-file", bf,
               "--seats-dir", os.path.dirname(CANON), "--comm", CANON]
        if af:
            with open(af, "w", encoding="utf-8") as f:
                f.write(attach)
            cmd += ["--attach", af]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    finally:
        for x in (bf, af):
            if x:
                try:
                    os.unlink(x)
                except OSError:
                    pass
    for line in (r.stderr or "").splitlines():
        if line.startswith("WARN "):
            sys.stderr.write(line + "\n")
    if r.returncode == 0:
        return None
    rej = next((ln for ln in (r.stdout or "").splitlines() if ln.startswith("REJECT ")), "")
    if rej:
        return ("DESK_ROUTE " + rej[7:].strip(), hint)
    return ("DESK_ROUTE_GATE_ERROR rc=%d %s" % (r.returncode, (r.stderr or "").strip()[:120]), hint)


def send(to, frm, body, force=False, dispatch=False, desk_attach=""):
    _check_name(to)
    _check_name(frm)
    # ★desk 창구 고정(r660 · 판정 1125)★ — 규칙은 「판정기 하나」(ft_desk_route_gate.py)다. 우편함 길(comm/mbox.sh)도 같은 파일을 부른다(두 벌 금지 · 카드 ⓖ).
    #   ★--force 로 안 풀린다★ — desk 방향은 재전송 규율이 아니라 길 자체의 문제다. 잠금 밖에서 판정(큐 무관).
    try:
        desk = _desk_verdict(to, frm, body, desk_attach)
    except Exception as e:      # ★판정기 고장 = 통과가 아니다★(DA⑥ r1 ⓒ fail-closed · 두 길 같은 결론)
        desk = ("DESK_ROUTE_GATE_ERROR %s — desk 경로 판정 실패" % type(e).__name__,
                "desk 는 planner 에게만 보내고, desk 에는 planner 가 보냅니다(planner 안내서 27줄).")

    def op():
        if desk:
            return ("__BLOCKED__", desk)
        rows = _load(CANON)
        # ★F6: 가드 판정을 잠금 «안»에서(load 직후) — 밖이면 동시 send 가 서로의 큐를 못 봐 둘 다 통과.
        # ★게이트가 고장나면 통과시킨다(fail-open)★ — 가드 버그로 통신이 끊기는 쪽이 더 크다.
        try:
            verdict = None if force else _guard_verdict(to, frm, body, dispatch)
        except Exception:
            verdict = None
        if verdict:
            return ("__BLOCKED__", verdict)  # 잠금 안에서 exit 금지 — 해제 후 처리.
        seq = _next_seq(rows)
        row = {
            "seq": seq,
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "to": to,
            "from": frm,
            "body": body,
        }
        # ★전문 보관은 «큐에 넣기 전»★ — 행은 큐에 있는데 전문은 없는 순간을 만들지 않는다.
        #   그 순간이 있으면 그 사이에 도착한 recv 가 «되찾을 수 없는 절단»을 하게 된다.
        if len(body) > MAX_BODY:
            full = _stash_body(CANON, seq, body)
            if full:
                row["body_full"] = full
        rows.append(row)
        byto = {}
        for r in rows:
            byto.setdefault(_role_key(r["to"]), []).append(r)
        keep, dropped, overflow = [], 0, 0
        for t, rs in byto.items():
            rs.sort(key=lambda r: r["seq"])
            # ★밀려난 건수를 «센다»★ — ring 은 조용히 버린다. 안 세면 «보낸 사람은 QUEUED 를
            # 봤는데 받는 사람은 영영 못 보는» 유실이 무증상으로 쌓인다.
            # ★버리는 순서 = 시스템 알림 → 일반 · 사람 글은 안 버린다★ (r912 · 위 공유 블록).
            k, d, _oldest, ov = trim(rs, MAX_PER_TO)
            keep.extend(k)
            if t == _role_key(to):
                dropped, overflow = d, ov
        _save(CANON, keep)
        _log_sent(CANON, row)  # r488 — 같은 잠금 안 · relay 는 send 를 타므로 여기 한 곳
        # ★가드 기록을 «이미 잡고 있는» 우편함 잠금 안에서 한다★ — 밖에서 하면 동시 send 가
        # 읽고-고쳐-쓰기로 겹쳐 기록이 유실되고(실측 20건 중 일부), 가드가 «덜 잡는» 쪽으로 샌다.
        # 잠금을 새로 «거는» 것은 오히려 나쁘다 — flock 은 블로킹이라 물고 죽은 프로세스가
        # send 를 멈춘다. 기록 몇 건 잃는 것보다 큰 실패다. 여기는 획득이 늘지 않는다.
        try:
            _guard_record(to, frm, body)
        except Exception:
            pass
        return seq, sum(1 for r in keep if _role_key(r["to"]) == _role_key(to)), dropped, overflow

    res = _locked(CANON, op)
    if res[0] == "__BLOCKED__":
        reason, hint = res[1]
        # ★마지막 줄에 이유를 «다시» 싣는다★ (2026-09-04 실측)
        #   사람은 stderr 를 tail 로 받는다. 이유가 첫 줄에만 있으면 `tail -1` 은
        #   "--force 를 붙인다" 만 보여주고, RESEND_COOLDOWN 처럼 hint 가 여러 줄인 가드는
        #   ★`tail -3` 으로도 이유가 밀려나 안 잡힌다★. 그러면 받는 사람은 «왜 막혔는지
        #   모른 채» 본문만 줄여 재발송한다 — 실제로 오늘 그 일이 났고, 당사자는 어느
        #   가드였는지 사후에도 확정하지 못했다.
        #   잘리는 쪽을 우리가 정할 수 없으므로 ★양 끝에 둔다★.
        sys.stderr.write(
            "BLOCKED %s\n%s\n→ BLOCKED %s%s\n"
            % (reason, hint, reason,
               " · desk 경로는 --force 로 안 풀린다" if reason.startswith("DESK_ROUTE") else " · 정말 필요하면 --force")
        )
        sys.exit(3)
    seq, pend, dropped, overflow = res
    # ★«어느 파일에 몇 바이트» 를 찍는다★ — QUEUED 를 «도착»으로도 «온전»으로도 읽지 않게.
    print(
        f"QUEUED seq={seq} to={to} pending={pend} "
        f"file={_mbox(CANON)} bytes={len(body.encode('utf-8'))}"
    )
    if dropped:
        sys.stderr.write(
            "DROPPED %d to=%s (ring=%d 포화 · 시스템 알림 먼저 · 사람 글 보존) — 이 좌석이 %d건을 안 읽고 쌓아뒀다.\n"
            "버려진 %d건은 «영구 유실»이다. 좌석 상태를 보고, 급하면 pane 으로 직접 보낸다.\n"
            % (dropped, to, MAX_PER_TO, pend, dropped)
        )
    if overflow:
        # ★사람 글은 안 버린다★ — 상한을 넘긴 채로 두고 «그 사실»을 알린다(조용한 초과 0 · r912).
        sys.stderr.write(
            "ERROR 사람 글로 큐 넘침 — to=%s pending=%d (ring=%d) · 버리기 0 · 받는 좌석 확인\n"
            % (to, pend, MAX_PER_TO)
        )
    # ★청소는 «QUEUED 를 찍은 뒤», «잠금 밖»에서★ — 이 호출이 실패하거나 느려도
    #   메시지는 이미 큐에 들어갔고 발신자는 이미 결과를 받았다. relay 는 send 를
    #   타므로 여기 한 곳이면 두 경로가 모두 덮인다.
    _prune_bodies(CANON)


def relay(to, frm, path, summary, force=False):
    """긴 본문의 «정본 절차» — 원문은 파일, 큐엔 사람이 쓴 요약 + 경로만.

    ★원본을 «가리키지» 않고 «복사»한다★ — 보낸 뒤 원본이 바뀌거나 지워지면
    받는 쪽이 읽는 글이 보낸 글과 달라진다. 스냅샷이라야 인용이 성립한다.
    ★요약은 자동 생성하지 않는다★ — 무엇이 중요한지는 보내는 사람만 안다.
    자동 요약을 끼우면 받는 쪽은 결국 원문 전체를 열게 되고, 아낀 게 없어진다.
    """
    _check_name(to)
    _check_name(frm)
    if not os.path.isfile(path):
        sys.stderr.write("NO_SUCH_FILE %s\n" % path)
        sys.exit(1)
    if not summary.strip():
        sys.stderr.write("EMPTY_SUMMARY 요약 3~5줄은 보내는 사람이 쓴다.\n")
        sys.exit(1)
    os.makedirs(RELAY_DIR, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._#-]", "_", os.path.basename(path))
    base = os.path.join(RELAY_DIR, "%s-%s-to-%s-" % (time.strftime("%Y%m%dT%H%M%S"), frm, to))
    # ★같은 이름이면 «덮어쓰지 않고» 새 자리를 만든다★ — 초 단위 타임스탬프라 같은 초에 같은
    # from→to 로 같은 파일명을 보내면 앞 스냅샷이 파괴돼, 먼저 보낸 포인터가 «나중 내용»을
    # 가리킨다. 스냅샷이 안 남으면 relay 는 경로만 보내는 것과 다를 게 없다.
    dest, n = base + safe, 1
    while os.path.exists(dest):
        n += 1
        dest = "%s%d-%s" % (base, n, safe)
    shutil.copyfile(path, dest)
    # 판정 재료에 «전문» 을 넣는다(r660 · DA⑥ r1 ⓑ③) — 요약 1줄에 여러 줄 전문을 붙여 h 결과 예외를 통과하는 길 0.
    try:
        with open(dest, encoding="utf-8", errors="replace") as f:
            _full = f.read()
    except OSError:
        _full = ""
    # ★F3: relay 도 재발신 탈출구를 send 로 전달 — 힌트대로 --force 를 붙이면 실제로 풀리게.
    send(
        to,
        frm,
        "%s\n상세(전문): %s (%d B)" % (summary.strip(), dest, os.path.getsize(dest)),
        force=force,
        desk_attach=_full,
    )


def _rows_for(d, me, frm):
    return [r for r in _load(d) if _role_key(r.get("to")) == _role_key(me) and (frm is None or r.get("from") == frm)]


def _consume(d, seqs):
    def op():
        rows = _load(d)
        keep = [r for r in rows if r.get("seq") not in seqs]
        if len(keep) != len(rows):
            _save(d, keep)

    _locked(d, op)


def recv(me, frm=None, limit=None):
    _check_name(me)
    if frm is not None:
        _check_name(frm)
    dirs = [CANON] + _legacy_dirs()
    got = []
    for d in dirs:
        got.extend((d, r) for r in _locked(d, lambda d=d: _rows_for(d, me, frm)))
    got.sort(key=lambda x: x[1]["seq"], reverse=True)  # LIFO
    # ★표시한 것만 소비한다★ — 표시 상한을 두면서 전량 소비하면 나머지가 조용히 사라진다.
    held = []
    if limit is not None and len(got) > limit:
        got, held = got[:limit], got[limit:]
    # ★어느 파일들을 봤는지 찍는다★ — 안 찍으면 union 이 실제로 도는지 아무도 모른다.
    print(f"SCANNED {len(dirs)} mailbox(es): " + " ".join(_mbox(d) for d in dirs))
    if not got:
        print("READ none")
        return
    byd = {}
    for d, r in got:
        byd.setdefault(os.path.abspath(d), (d, set()))[1].add(r["seq"])
    for d, seqs in byd.values():
        _consume(d, seqs)
    for d, r in got:
        tag = "" if os.path.abspath(d) == os.path.abspath(CANON) else " (legacy)"
        shown, note = _clip(r)
        print(f"READ [{r['from']}->{me}] #{r['seq']}{tag} — {shown}")
        if note:
            print(note)
    if held:
        print(f"HELD {len(held)} more — 큐에 남겨둠. 전체는 `recv {me} --all`")
        for _, r in held:
            print(f"  · #{r['seq']} [{r['from']}] {r['body'][:70].replace(chr(10), ' ')}…")


def peek(me):
    _check_name(me)
    dirs = [CANON] + _legacy_dirs()
    mine = []
    for d in dirs:
        mine.extend(r for r in _locked(d, lambda d=d: _load(d)) if _role_key(r.get("to")) == _role_key(me))
    mine.sort(key=lambda r: r["seq"], reverse=True)
    head = f"pending={len(mine)}"
    if mine:
        head += f" latest_seq={mine[0]['seq']} from={mine[0]['from']}"
    print(f"{head} scanned={len(dirs)}")


if __name__ == "__main__":
    a = sys.argv[1:]
    force = "--force" in a
    dispatch = "--dispatch" in a
    show_all = "--all" in a
    a = [x for x in a if x not in ("--force", "--all", "--dispatch")]
    if not a:
        sys.exit(
            "usage: mbox {send <to> <from> <body> [--force]"
            "|relay <to> <from> <file> <summary>"
            "|recv <me> [<from>] [--all]|peek <me>}"
        )
    c = a[0]
    if c == "send":
        send(a[1], a[2], " ".join(a[3:]), force, dispatch)
    elif c == "relay":
        relay(a[1], a[2], a[3], " ".join(a[4:]), force)
    elif c == "recv":
        recv(a[1], a[2] if len(a) > 2 else None, None if show_all else RECV_LIMIT)
    elif c == "peek":
        peek(a[1])
    else:
        sys.exit("unknown cmd")
