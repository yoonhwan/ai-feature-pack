#!/bin/bash
# ft-ctx-triage.sh <project-root> — 증류 결정 전 컨텍스트 진단 (§2-3① / context-management.md §2.5)
# 독립 체크 3함수(bloat/state/sessions) + 결정론 reducer. 판단·수정은 오케(LLM) 몫 —
# 스크립트는 사실 수집만 한다. stdout ≤15줄.
#
# ★ 각 함수 개별 fail-open: 오류 시 해당 카테고리만 `CHECK_FAIL <name>` 1줄 출력하고 나머지 계속.
# ★ reducer는 가용 결과만으로 `RECOMMEND CONTINUE|COMPACT|DISTILL` 1줄 산출(문제 시 FIX 지시 병기).
set +e

LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"
[ -f "$LIB" ] && . "$LIB"

ROOT="${1:-}"
if command -v ft_resolve_root >/dev/null 2>&1; then
  ROOT="$(ft_resolve_root "$ROOT")"
else
  [ -n "$ROOT" ] || ROOT="$(pwd)"
fi
FT="$ROOT/.fable-team"

# ── check_bloat: 대용량 파일(>50M, 최근 7일) 상위 5 ──
check_bloat() {
  local files
  # find rc는 무시(MINOR-4): 일부 경로 권한오류로 rc!=0여도 부분 결과를 살려 진행(fail-open 철학 정합).
  files="$(find "$ROOT" \
      \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name .worktrees \) -prune \
      -o -type f -size +50M -mtime -7 -print 2>/dev/null)"
  [ -n "$files" ] || return 0
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    du -sh "$f" 2>/dev/null
  done | sort -rh 2>/dev/null | head -5 | while IFS=$'\t' read -r sz path; do
    [ -n "$path" ] || { path="$sz"; sz="?"; }
    echo "BLOAT $sz $path"
  done
}

# ── check_state: ACTIVE→state.md 존재 + 산출물 실재 (부재 시 STALE_POINTER) ──
check_state() {
  local active="$FT/state/ACTIVE"
  [ -f "$active" ] || return 0   # 활성 피처 없음 = 정상
  local slug; slug="$(head -1 "$active" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$slug" ] || { echo "CHECK_FAIL check_state"; return 0; }
  local md="$FT/state/$slug.state.md"
  [ -f "$md" ] || md="$FT/state/state.md"
  if [ ! -f "$md" ]; then echo "STALE_POINTER stage=? missing=state.md"; return 0; fi
  local stage; stage="$(grep -iE 'stage:' "$md" 2>/dev/null | head -1 | sed -E 's/.*stage:[[:space:]]*([0-9]+).*/\1/')"
  [ -n "$stage" ] || stage="?"
  # '산출:' 라인의 산출물 경로만 검사(바운드) — stage 대비 산출물 실재.
  local arts; arts="$(grep -E '산출' "$md" 2>/dev/null | grep -oE '\.fable-team/[A-Za-z0-9._/-]+\.(md|json|ya?ml)' | sort -u)"
  local n=0
  printf '%s\n' "$arts" | while IFS= read -r a; do
    [ -n "$a" ] || continue
    if [ ! -e "$ROOT/$a" ]; then
      n=$((n+1)); [ "$n" -le 3 ] && echo "STALE_POINTER stage=$stage missing=$a"
    fi
  done
}

# ── check_sessions: tmux ls의 ft-* CPU → hang 후보 ──
check_sessions() {
  command -v tmux >/dev/null 2>&1 || { echo "CHECK_FAIL check_sessions"; return 0; }
  local errf out rc
  errf="$(mktemp 2>/dev/null || echo /tmp/ft-ctx-tmuxerr.$$)"
  out="$(tmux ls -F '#{session_name}' 2>"$errf")"; rc=$?
  local err; err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf" 2>/dev/null
  if [ "$rc" -ne 0 ]; then
    case "$err" in
      *"no server"*|*"no sessions"*|*"error connecting"*) return 0;;  # 세션 0 = 정상
      *) echo "CHECK_FAIL check_sessions"; return 0;;
    esac
  fi
  printf '%s\n' "$out" | while IFS= read -r s; do
    case "$s" in ft-*) ;; *) continue;; esac
    local cpu
    if command -v ft_sess_cpu >/dev/null 2>&1; then cpu="$(ft_sess_cpu "$s")"; else cpu=""; fi
    [ -n "$cpu" ] || continue
    if awk -v c="$cpu" 'BEGIN{exit !(c+0 < 0.3)}'; then
      echo "HANG_CANDIDATE $s cpu=$cpu"
    fi
  done
}

# ── 실행 + reducer ──────────────────────────────────────────
echo "TRIAGE root=$ROOT"

BLOAT_OUT="$(check_bloat)"
STATE_OUT="$(check_state)"
SESS_OUT="$(check_sessions)"

[ -n "$BLOAT_OUT" ] && printf '%s\n' "$BLOAT_OUT" | head -3
[ -n "$STATE_OUT" ] && printf '%s\n' "$STATE_OUT" | head -2
[ -n "$SESS_OUT" ]  && printf '%s\n' "$SESS_OUT"  | head -3

has_bloat=0; printf '%s' "$BLOAT_OUT" | grep -q '^BLOAT ' && has_bloat=1
has_stale=0; printf '%s' "$STATE_OUT" | grep -q '^STALE_POINTER' && has_stale=1
has_hang=0;  printf '%s' "$SESS_OUT"  | grep -q '^HANG_CANDIDATE' && has_hang=1

# 문제 시 DISTILL 전 수정 지시 병기(§2-2 [2])
[ "$has_stale" = 1 ] && echo "FIX stale 포인터 → §4 규칙 롤백 후 재개(증류 전 상태 정합 확보)"
[ "$has_bloat" = 1 ] && echo "FIX 비대 로그 → ft-gzip.sh(승인/토큰) 압축"
[ "$has_hang"  = 1 ] && echo "FIX hang 워커 → ft-tmux-distill.sh 증류"

# 결정론 reducer — 판단은 오케 몫, 여기선 사실 기반 1줄 권고.
if [ "$has_hang" = 1 ]; then
  echo "RECOMMEND DISTILL"
elif [ "$has_bloat" = 1 ]; then
  echo "RECOMMEND COMPACT"
else
  echo "RECOMMEND CONTINUE"
fi
exit 0
