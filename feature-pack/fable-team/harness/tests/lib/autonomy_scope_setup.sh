#!/usr/bin/env bash
# autonomy_scope_setup.sh — source 전용 · test_autonomy_scope_{grant,stop_tamper,code_hook}.sh 공용 준비 (r1197 · 옛 test_autonomy_scope.sh 5~41행 그대로)
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR) + FT_NOW 고정 시계 + 가짜 분류기(FT_SCOPE_CLASSIFY) — 실 state·실 git 분류 0.
# 쓰는 법: 시험 맨 위 real_state_guard(guard_begin) 다음 줄에 `. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"`
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 손 approve-scope 경로라 each(레벨 시험 = test_autonomy_level.sh)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; SG="$ROOT/harness/kit/fable-team/templates/hooks/autonomy-state-guard.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
IH="$T/hooks"; mkdir -p "$IH"; cp "$ROOT/harness/kit/fable-team/templates/hooks/autonomy-"*.sh "$ROOT/harness/kit/hooks/merge_cmd.py" "$IH"/   # r546: 설치 꼴(한 폴더) 재현 — 공용 모듈 merge_cmd.py 를 훅 옆에 둔다
SG="$IH/autonomy-state-guard.sh"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; LOG="$S/autonomy.log"; AP="$S/autonomy-merge-approved"; mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000; NOW=$T0
cat > "$T/stub-classify.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 분류기 — classify: STUB_RC·STUB_OUT(`CLASS <종류>` / `FORBID …`) · check-revert: STUB_REVERT_RC·STUB_REVERT_OUT(rc 4 = `REVERTED L by <sha>`)
printf '%s\n' "$*" >> "${STUB_ARGS_LOG:-/dev/null}"
if [ "$1" = check-revert ]; then printf '%s\n' "${STUB_REVERT_OUT:-OK}"; exit "${STUB_REVERT_RC:-0}"; fi
printf '%s\n' "${STUB_OUT:-CLASS docs}"; exit "${STUB_RC:-0}"
EOF
export FT_SCOPE_CLASSIFY="$T/stub-classify.sh"
cat > "$T/stub-post.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 슬랙 게시 — 실제 게시 0. 본문은 STUB_POST_LOG 에 모은다 · STUB_POST_RC≠0 이면 게시 실패(ERR) · 성공 = `SLACK-TS <ts>`
[ "$1" = --text ] && printf '%s\n' "$2" >> "${STUB_POST_LOG:-/dev/null}"
[ "${STUB_POST_RC:-0}" = 0 ] || { echo "ERR chat.postMessage 호출 실패: URLError" >&2; exit "$STUB_POST_RC"; }
echo "SLACK-TS 1800000000.000100"
EOF
export FT_SCOPE_SLACK_POST="$T/stub-post.sh" STUB_POST_LOG="$T/post.log"

a() { FT_NOW="$NOW" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S"; mkdir -p "$S"; NOW=$T0; a on >/dev/null 2>&1; }   # A1 ON · 시계 T0
sha() { printf '%040x' "$1"; }
lines() { wc -l < "$LOG" | tr -d ' '; }
grant() { run a approve-scope "$@"; }
