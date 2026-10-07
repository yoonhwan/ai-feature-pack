#!/bin/bash
# PreToolUse hook — 파괴적/비가역 Bash 명령 차단 (HIL 강제)
# 신설 2026-06-09: FB_MR#8 세션을 HIL 없이 kill한 사고 재발방지.
# 데이터/인프라/세션 등 복구 불가 삭제를 시스템 레벨에서 차단한다.
# exit 2 = PreToolUse deny (stderr 메시지가 Claude에 피드백됨).

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception:
    print('')" 2>/dev/null)

# 파괴/비가역 패턴 (대소문자 무시)
# 2026-07-11 예외: tmux kill-session은 하드블록에서 제외(사용자 명시 표준승인 —
# "tmux,tmuxc는 컨트롤해도됨", cmux 메모리 고갈 방지 위한 상시 세션 정리 목적).
# kill-server(전체 서버 종료, 모든 세션 동시 파괴)는 그대로 차단 유지.
PATTERN='tmux kill-server|rm -[rf][rf]|rm -[rf] +-[rf]|gcloud [a-z0-9 _-]*(delete|destroy)|DROP +(TABLE|DATABASE|SCHEMA)|TRUNCATE +TABLE|dropdb|terraform +destroy|kubectl +delete|git +push[^&|;]*(--force|-f\b)|git +worktree +remove|git +branch +-D|supabase [a-z0-9 _-]*delete|kill -9|pkill'

if printf '%s' "$CMD" | grep -qiE "$PATTERN"; then
  printf '🚫 파괴적/비가역 명령 차단 — HIL(사람 승인) 필수\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '데이터/인프라/세션을 복구 불가하게 삭제할 수 있습니다. yoonhwan 오빠의 명시 승인을 받은 뒤에만 진행하세요. (정당한 경우 사용자가 직접 ! 로 실행하거나 승인)\n' >&2
  exit 2
fi

# ── 스테이징 오염 차단 (신설 2026-09-16, CFO 트랙 규율 F17) ──────────────────
# 같은 워크트리를 여러 세션이 동시에 쓰면 `git add .`/`-A` 가 "남이 만든 파일"까지
# 자기 커밋에 싣는다. 2026-09-15 하루에 세 번 났고, 한 번은 코드 3파일이 다른 세션의
# 문서 커밋에 섞여 구조/문서 혼합(Tidy First 위반)까지 갔다.
# ★파괴적이지 않지만 되돌리기 어렵다★ — 공유 브랜치라 히스토리 재정리가 위험하다.
# ★이 훅이 막지 못하는 것★: `git add <디렉토리>/` 형태. 그것도 같은 사고를 내지만
# 의도적인 경우가 많아 차단하지 않는다 — 그건 사람이 판단한다.
# ★알려진 오탐(허용)★: 명령문 안에 문자열로 들어 있기만 해도 차단된다(문서·echo·주석 포함).
#   위 파괴 패턴도 같은 성질이고(`rm -rf` 를 문장에 쓰면 차단), 이 훅의 관행이다.
#   ★정교하게 파싱하지 않는 이유★: 판정기를 촘촘하게 만들수록 예외 목록이 자라고,
#   예외가 자라면 그 판정기는 결국 아무것도 안 막는다(2026-09-15 CFO 트랙에서 배운 것).
#   막히면 우회하지 말고 파일에 써서 실행하거나 사람이 직접 실행한다.
# ★경계를 요구한다★ — 뒤에 공백이나 줄끝이 와야 「전체 스테이징」이다.
#   2026-09-16 실측 오탐: 경계가 없으면 숨김 폴더로 시작하는 경로(.claude/… .github/… 등)의
#   맨 앞 점이 「전체」로 오인돼 정당한 경로 지정까지 막았다. 구현 좌석이 그 자리에서 걸렸다.
STAGE_PATTERN='git +add +(\.([[:space:]]|$)|-A([[:space:]]|$)|--all([[:space:]]|$))'
if printf '%s' "$CMD" | grep -qE "$STAGE_PATTERN"; then
  printf '🚫 git add . / -A 차단 — 스테이징 오염 방지 (CFO 규율 F17)\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '같은 워크트리를 다른 세션이 동시에 쓰고 있으면 남의 파일까지 커밋에 실립니다.\n' >&2
  printf '대신: (1) git status 로 스테이징에 내가 안 만진 파일이 있는지 보고 (2) git add <내 파일 경로들> 로 경로를 지정하세요.\n' >&2
  printf '그래도 섞이면 "섞였다"고 보고하고, 히스토리 재정리는 하지 마세요(공유 브랜치).\n' >&2
  exit 2
fi
exit 0
