#!/usr/bin/env bash
# ft-fp-run.sh — 훅 오탐 «기록 + 허용» 래퍼 (R105-a · governance §7 「오탐 = 파일 기록 + 실행 허용 + 묶음 알림」)
#   ft-fp-run.sh --file <명령 파일> "<사유 1줄>"   ← 기본 입구: 좌석이 Write 도구로 먼저 쓴 파일(명령 글자가 Bash 인자에 안 들어가 훅을 안 건드린다)
#   ft-fp-run.sh "<사유 1줄>" -- <명령…>           ← 짧은 명령: 인자를 그대로 FT_FP_RUN_DIR/<ts>-<seat>.sh 에 쓰고 같은 길로
# 순서: ①hook-falsepos.log 1줄 자동 기록 ②파일 내용을 판정기(글자 vs 실행 가려냄) + 훅의 PATTERN 으로 «다시» 검사
#       — «실행 자리» 에 걸리면 진짜 파괴로 보고 실행 0 · rc 3 · planner [HIL] 안내(우회 도구가 아니다) ③안 걸리면 bash <파일> · rc 그대로.
# rc: 0 실행 성공(또는 명령 rc) · 2 사용법(사유 개행 포함) · 3 진짜 파괴로 거부 · 4 훅·판정기를 못 찾음(fail-closed) · 5 로그 기록 실패(실행 0)
# env: FT_FP_LOG(기본 <루트>/.fable-team/state/hook-falsepos.log) · FT_FP_RUN_DIR(기본 <루트>/.fable-team/state/fp-run) · FT_FP_HOOK(block-destructive.sh 경로) · FT_SEND_FROM(좌석명)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { echo "usage: ft-fp-run.sh --file <파일> \"<사유>\"  |  ft-fp-run.sh \"<사유>\" -- <명령…>" >&2; exit 2; }
if [ "${1:-}" = "--file" ]; then
  [ $# -eq 3 ] && [ -n "$3" ] && [ -f "$2" ] || usage
  F="$2"; REASON="$3"; INLINE=0
else
  [ $# -ge 3 ] && [ -n "$1" ] && [ "$2" = "--" ] || usage
  REASON="$1"; shift 2; INLINE=1
fi
case "$REASON" in *$'\n'*|*$'\r'*) echo "ft-fp-run: 사유는 1줄이어야 한다" >&2; exit 2;; esac
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; ROOT="${ROOT%/.git}"; [ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 4   # r385: cwd git 밖 → ft_repo_root(옛 설치 꼴) → 못 찾음 rc4(fail-closed)
LOG="${FT_FP_LOG:-$ROOT/.fable-team/state/hook-falsepos.log}"
DIR="${FT_FP_RUN_DIR:-$ROOT/.fable-team/state/fp-run}"
SEAT="${FT_SEND_FROM:-$(tmux display-message -p '#S' 2>/dev/null || echo unknown)}"
HOOK="${FT_FP_HOOK:-}"
for c in "$HOOK" "$HOME/.claude/hooks/block-destructive.sh" "$HERE/../harness-install/fable-team/templates/hooks/block-destructive.sh"; do
  [ -n "$c" ] && [ -f "$c" ] && { HOOK="$c"; break; }
done
JUDGE="$(dirname "$HOOK")/block-destructive-judge.py"
[ -f "$HOOK" ] && [ -f "$JUDGE" ] || { echo "ft-fp-run: 훅·판정기를 못 찾음 — 실행 0" >&2; exit 4; }
PATTERN="$(sed -n 's/^PATTERN=//p' "$HOOK" | head -1)"; PATTERN="${PATTERN#\'}"; PATTERN="${PATTERN%\'}"
[ -n "$PATTERN" ] || { echo "ft-fp-run: 훅에서 PATTERN 을 못 읽음 — 실행 0" >&2; exit 4; }
if [ "$INLINE" = 1 ]; then
  mkdir -p "$DIR" && F="$DIR/$(date +%Y%m%dT%H%M%S)-${SEAT//[^A-Za-z0-9_.-]/_}.sh"
  { printf '%q ' "$@"; printf '\n'; } > "$F"
fi
note() { mkdir -p "$(dirname "$LOG")" && printf '%s %s ft-fp-run [%s] %s · %s · %.80s\n' "$(date '+%F %T')" "$SEAT" "$1" "$REASON" "$F" "$(tr '\n' ' ' < "$F")" >> "$LOG"; }
recheck() {   # 판정기가 «글자» 로 가린 뒤에도 PATTERN 이 남으면 0
  local eff; eff="$(python3 "$JUDGE" "$(cat "$F")" '{}' 2>/dev/null)" || eff="$(cat "$F")"
  printf '%s' "$eff" | grep -qiE "$PATTERN"
}
recheck_rc=0; recheck && recheck_rc=1
if [ "$recheck_rc" = 1 ]; then
  note REJECT
  echo "ft-fp-run: 실행 자리에 파괴 명령이 있다 — 래퍼는 우회 도구가 아님 · 실행 0 · planner [HIL] 로 올릴 것($F)" >&2
  exit 3
fi
note ALLOW || { echo "ft-fp-run: 로그 기록 실패($LOG) — 실행 0" >&2; exit 5; }   # 기록 성공이 실행의 전제
bash "$F"
