#!/usr/bin/env python3
"""ft_doc_exempt_paths.py — ft_doc_exempt.py 의 «경로 조각» 판정 한 곳 (R741 · 카드 r741-doc-exempt-team-subfolders)

왜 나눴나: ft_doc_exempt.py 가 이미 311줄(BYZ 상한 200 초과) — 제외 폴더 목록과 조각 검사를 이 모듈로 옮겨
          본 판정기 줄 수를 늘리지 않는다(카드 §구현 범위 0). 판정 규칙은 여전히 «한 곳»(이 파일)이다.
R741 범위 확대: 팀 폴더 «직속» .md → «팀 폴더 아래 하위 폴더» .md. 단 아래는 예외가 아니다:
  EXCLUDE_DIRS = indices(카드 폴더) · inbox(역할 좌석의 일) · keys(키 원장) · baselines(press 기준선 표)
    — 하네스 «도구가 판정 입력» 으로 읽는 폴더. 문서 PR 로 바꾸면 ft-index-move · ft-role-spawn ·
      key_change_ledger · ft-press-baseline-check 게이트를 건너뛰는 길이 된다(카드 ⓒ · DA⑥ r1 처방 2).
    팀 이름 뒤 «어느 깊이» 에 있어도 거절.
  EXCLUDE_NAMES = 키트 코드가 이름으로 부르는 .md 토큰 전부(DA⑥ r1 처방 3) — 손으로 고른 목록은 계속 샌다
    (FLAGS.md · BTS.md 가 그렇게 빠졌다). 모든 깊이의 «파일 이름» 에 적용하고, 빠지면 가드 시험이 빨강이다
    (tests/test_doc_exempt_guard_r741.sh — 목록 재생성 = `bash tests/test_doc_exempt_guard_r741.sh --emit`).
  점으로 시작하는 조각(.omc 등 숨김 폴더·파일) · 빈 조각 · `.` · `..` · NFKC 로 바뀌는 호환 문자(긴 s ſ 등) = 거절.
  팀 «하위 폴더» = **새 파일 추가(A) 만** 면제 — 수정·삭제·이름바꾸기(M/D/R)는 직속만(오빠 결정 2026-10-22 · 선택지 1).
    이유: 이미 카드나 master 명령 인자가 가리키는 판정 파일(evidence/DA-*.md 같은)은 이름이 코드에 없어 목록으로 못 막는다.
  비교 키 = NFKC + casefold(key) — 대소문자·호환 문자(ſ→s · ﬁ→fi) 우회를 같은 값으로 접는다(DA⑥ r1 처방 1).
  CANON(정본·승인근거 이름 접두) = «마지막 조각» 에 key 비교 · "LEDGER" 접두 포함(R741).
"""

import re
import unicodedata

TEAMS_PREFIX = "design/teams/"
TEAM_RX = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
# 도구가 «판정 입력» 으로 읽는 팀 하위 폴더 — 문서 면제 아님(카드 ⓒ · DA⑥ r1 처방 2: baselines 추가). 비교는 key().
EXCLUDE_DIRS = ("indices", "inbox", "keys", "baselines")
# 키트가 «이름으로» 부르는 .md (kit/fable-team/bin · kit/hooks · kit/fable-team/templates/hooks · kit/slack-mirror · harness/bin
#   의 `[A-Za-z0-9_-]+\.md` 토큰 전부 · key() 로 접은 값). 새 도구가 .md 이름을 부르면 가드 시험이 빨강 → 여기 갱신.
EXCLUDE_NAMES = (
    "-yyyymmdd.md", "4-and-816-20261007.md", "4-fable.md", "a.md",
    "autonomy-goal-a6-20261018.md", "autonomy-queue.md", "baseline-template.md", "body.md",
    "branch-candidates.md", "breach.md", "brief.md", "bts.md",
    "case-polish-ko-not-applied-baseline-gap-20261006.md", "cause-idle-teams-and-stale-goal-table-20261021.md", "checkpoint.md", "claude.md",
    "closeout-policy.md", "comm-guide-boot.md", "comm-guide.md", "context-management.md",
    "da-r30-handover-20261008.md", "day.md", "design-834-baseline-gate-arch165.md", "design-r231-desk-slack-files-20261015.md",
    "design-r30-succession-window-handover-20261008.md", "design-r49-question-board-20261008.md", "design-slack-inbound-820.md", "design-slack-mirror.md",
    "detail.md", "directive-v65-wall.md", "draft-harness-upgrade-v65.md", "dumb-time-ledger.md",
    "e2e_testing.md", "fingerprint.md", "flag-decisions.md", "flags.md",
    "ft_role.md", "goal-20260912-clear-list.md", "goal-archastra-lst-on-off-completion.md", "goal-harness.md",
    "goal-issues.md", "goal-ledger-v65.md", "goal-planner.md", "goal-team.md",
    "guide-magazine-20261016.md", "guide-planner.md", "guide-team.md", "harness-map.md",
    "hashlib.md", "hil-ledger.md", "id.md", "index.md",
    "issue-transitions.md", "keep.md", "key-change.md", "label.md",
    "landing-ledger.md", "ledger-keys.md", "list-v65-lst-completion-merged.md", "machines.md",
    "made.md", "main-team-governance.md", "marker.md", "merge-queue.md",
    "models.md", "nano-ledger-pm1-temp-sessions.md", "news-tree.md", "ops-verdicts-20261006.md",
    "orch-check.md", "orchestration.md", "plan-oppa-ledger.md", "plan-v65-sm65-experiment-completion-handoff.md",
    "progress.md", "prompt.md", "proposal_template.md", "pubrev.md",
    "queue-reask-morning.md", "r558-desk-slack-reply-goes-to-oppa-post-thread.md", "readme.md", "request-ledger.md",
    "retune-1832-20261015.md", "rules-ammo-and-distill-20260826.md", "runlog-pm1-v65-timeline.md", "seatbelt-readme.md",
    "seatbelt.md", "sheet-notes.md", "sheet.md", "single_set_testing.md",
    "skill.md", "slug.md", "spec-session-naming-20261005.md", "state.md",
    "stem.md", "team.md", "teams.md", "teamset.md",
    "tick-prompt-v65-unified.md", "tree.md", "update.md", "verdict-data-sovereignty-20260923.md",
    "x.md",
)
CANON = ("GOAL-", "GUIDE-", "SEATBELT", "VERDICTS-", "AUTONOMY-", "BOARD", "README",
         "PLAN-oppa-ledger", "FLAG-DECISIONS", "MERGE-QUEUE", "STATE.md", "NANO-LEDGER", "NEWS-TREE", "DECISION",
         "LEDGER")


def key(text):
    """비교 키 = NFKC + casefold — 대소문자·호환 문자(ſ→s · ﬁ→fi · K→k) 우회를 같은 값으로 접는다(DA⑥ r1 처방 1)."""
    return unicodedata.normalize("NFKC", text).casefold()


def shape_problem(path):
    """⑥ 경로 모양 — 제어문자·NFC 아님·호환문자(NFKC 로 바뀜)·빈 조각·`.`·`..`·점 조각이면 사유(아니면 빈 값)."""
    if any(ord(c) < 0x20 or ord(c) == 0x7F for c in path):
        return "제어문자 포함 경로: %r" % path
    if not unicodedata.is_normalized("NFC", path):
        return "NFC 아닌 이름: %s" % path
    for seg in path.split("/"):
        if seg in ("", ".", ".."):
            return "경로 모양 우회(빈 조각·.·..): %s" % path
        if seg.startswith("."):
            return "숨김 조각(점으로 시작): %s" % path
        if unicodedata.normalize("NFKC", seg) != seg:
            return "호환 문자 조각(NFKC 로 바뀜 — 긴 s ſ·전각 등): %s" % path
    return ""


def excluded_dir(segs):
    """③ 제외 폴더 — 팀 이름 «뒤» 조각 중 하나라도 EXCLUDE_DIRS(key 비교)면 사유."""
    for seg in segs:
        if key(seg) in EXCLUDE_DIRS:
            return "도구가 판정 입력으로 읽는 제외 폴더(%s)" % (" · ".join(EXCLUDE_DIRS))
    return ""


def canon_hit(name):
    """③ 정본·승인근거·판정입력 이름 접두(마지막 조각 · key 비교)."""
    low = key(name)
    return any(low.startswith(key(c)) for c in CANON)


def excluded_name(name):
    """③ 키트가 «이름으로» 부르는 .md(EXCLUDE_NAMES · key 비교) — 모든 깊이의 파일 이름에 적용."""
    return key(name) in EXCLUDE_NAMES


def team_of(path, status="A"):
    """doc-exempt ③⑥ — (팀, 사유). status = git 변경 종류(A/M/D/R). 사유가 있으면 경로가 범위 밖.
    R741 오빠 결정(선택지 1 · arch 124 결정 묶음): 팀 «하위 폴더» 는 새 파일 추가(A) 만 면제 —
    수정·삭제·이름바꾸기(M/D/R)는 «직속» 만. 이유: 이미 어느 카드나 master 명령 인자가 가리키는 판정 파일은
    이름이 코드에 안 박혀 목록으로 못 막는다 — 새로 «추가» 되는 파일은 아직 아무도 안 가리킨다."""
    why = shape_problem(path)
    if why:
        return "", why
    if not path.startswith(TEAMS_PREFIX):
        return "", "팀 폴더(design/teams/) 아님: %s" % path
    tail = path[len(TEAMS_PREFIX):]
    team, _, rest = tail.partition("/")
    if not rest:
        return "", "팀 폴더 직속 파일도 하위 폴더 문서도 아님: %s" % path
    segs = rest.split("/")
    name = segs[-1]
    if not TEAM_RX.match(team):
        return "", "팀 이름 형식 틀림: %s" % path
    why = excluded_dir(segs[:-1])
    if why:
        return "", "%s: %s" % (why, path)
    if not name.endswith(".md"):
        return "", "문서(.md) 아님: %s" % path
    if len(segs) > 1 and status != "A":
        return "", "팀 하위 폴더는 «새 파일 추가(A)» 만 면제 — 수정·삭제·이름바꾸기(%s)는 직속만: %s" % (status, path)
    if canon_hit(name):
        return "", "정본·승인근거·판정입력 이름(%s)은 예외 아님: %s" % (" · ".join(CANON), path)
    if excluded_name(name):
        return "", "키트가 이름으로 부르는 판정입력 .md(%s)은 예외 아님: %s" % (name, path)
    return team, ""
