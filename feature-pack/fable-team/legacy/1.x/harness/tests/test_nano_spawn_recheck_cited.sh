#!/usr/bin/env bash
# test_nano_spawn_recheck_cited.sh — r580: ft-nano-spawn.sh ①b(카드 base_sha 재대조) «인용 파일 뽑기» 정밀화.
#   인용 = 확장자 있는 파일 토큰만(폴더·ref 토큰 버림) · 확장자 교대는 긴 것 먼저(.tsx→.ts·.json→.js 잘림 0) · 맨 이름 = basename 대조
#   · 겹침 0 통과면 카드 base_sha 를 지금 HEAD 로 갱신(BASE-RENEW). 시험은 ①b 블록만 잘라 임시 리포·임시 카드에서 돌린다(실 tmux·실 워크트리·실 좌석 0).
#   환경변수 SRC_OVERRIDE 로 «고치기 전 판» 스크립트 폴더를 주면 같은 시험이 그 판에서 실패한다(red 증거).
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$HERE/../.."
SRC="${SRC_OVERRIDE:-$REPO_ROOT/harness/kit/fable-team/bin}"
BIN="$REPO_ROOT/harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
SNIP="$(awk '/^# ①b 카드 base_sha 대조/{p=1} p{print} p&&/^fi$/{exit}' "$SRC/ft-nano-spawn.sh")"
[ -n "$SNIP" ] && ok "①b 블록 추출" || bad "①b 블록 없음($SRC)"

# ── 임시 리포: base 커밋(A) → 변경 커밋(B). 카드 base_sha = A, CUR_HEAD = B.
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main
GIT() { git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$R/clients/web/src/components/toolbar" "$R/clients/web/src/components/credit" "$R/worker"
printf 'a\n' > "$R/clients/web/src/components/toolbar/corner-controls-v5.tsx"
printf '{}\n' > "$R/config.json"; printf 'w\n' > "$R/worker/x.py"
GIT add -A; GIT commit -q -m base; BASE="$(GIT rev-parse HEAD)"
printf 'b\n' > "$R/clients/web/src/components/credit/x.tsx"
printf 'c\n' >> "$R/clients/web/src/components/toolbar/corner-controls-v5.tsx"
printf '{"k":1}\n' > "$R/config.json"; printf 'w2\n' > "$R/worker/x.py"
GIT add -A; GIT commit -q -m changed; HEAD="$(GIT rev-parse HEAD)"

# 카드 만들기: card <이름> <구현 범위 본문> [관련 파일 줄]
CARDN=0
card() { CARDN=$((CARDN+1)); local p="$T/card-$CARDN.md"
  { echo "# 카드 $CARDN"; echo; echo "## 구현 범위"; printf '%s\n' "$2"; [ -z "${3:-}" ] || { echo; echo "관련 파일: $3"; }; echo; echo "## 상태"; echo "- base_sha: $BASE (spawn 2026-10-20)"; } > "$p"
  printf '%s' "$p"; }
sha_of() { grep -oE '[0-9a-f]{40}' "$1" | head -1; }
# ①b 블록을 서브셸에서 실행 — exit 가 서브셸만 끝낸다
runb() { ( WT="$R"; IDX="$1"; RESEARCH="${3:-0}"; RECHECK="${2:-}"; BASE_REF=""; eval "$SNIP" ) 2>&1; }

echo "== ⓐ 툴바 꼴: 폴더 토큰 + 인용 .tsx 3개 · 변경은 인용 밖 → 통과 + 카드 base_sha = 지금 HEAD"
C="$(card x '- 범위: clients/web · clients/web/src/ 에서 아래 3개만' 'clients/web/__tests__/unit/components/toolbar/caption-window-controls.test.tsx, clients/web/__tests__/unit/components/mobile-toolbar-overflow.test.tsx, clients/web/src/components/toolbar/caption-window-controls.tsx')"
out="$(runb "$C")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"BASE-RENEW ${BASE:0:9} → ${HEAD:0:9}"* ]] && [ "$(sha_of "$C")" = "$HEAD" ]; } \
  && ok "ⓐ 폴더 토큰은 인용 아님 → 겹침 0 통과 · BASE-RENEW · base_sha 갱신" || bad "ⓐ rc=$rc sha=$(sha_of "$C") ← $out"
has "$out" "인용 3개 겹침 0" "  └ 인용 개수 3(폴더 2개 제외)"
hasnt "$out" "REJECT" "  └ REJECT 0"

echo "== ⓑ 맨 이름 .tsx 인용 · 그 파일이 바뀜 → REJECT (옛 판은 .ts 로 잘려 거짓 통과)"
C="$(card x '- 고친다: corner-controls-v5.tsx 하나')"
out="$(runb "$C")"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *REJECT* ]] && [[ "$out" == *"corner-controls-v5.tsx"* ]] && [ "$(sha_of "$C")" = "$BASE" ]; } \
  && ok "ⓑ 맨 이름 basename 대조 → REJECT · base_sha 그대로" || bad "ⓑ rc=$rc ← $out"

echo "== ⓒ .json 인용 · 그 파일이 바뀜 → REJECT (.js 로 잘림 0)"
C="$(card x '- 설정: config.json')"
out="$(runb "$C")"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *"config.json"* ]]; } && ok "ⓒ .json 온전히 인용 → REJECT" || bad "ⓒ rc=$rc ← $out"

echo "== ⓓ «관련 파일:» 줄에 명시된 폴더는 접두로 유지 → 그 아래 변경 = REJECT"
C="$(card x '- 툴바 손본다' 'clients/web/src/components/toolbar/')"
out="$(runb "$C")"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *REJECT* ]] && [[ "$out" == *"corner-controls-v5.tsx"* ]]; } && ok "ⓓ 관련 파일 폴더 = 접두 대조 → REJECT" || bad "ⓓ rc=$rc ← $out"

echo "== ⓔ 인용 0(확장자 토큰 없음) → 기본 세트 경로 그대로 (worker/ 변경 = REJECT)"
C="$(card x '- clients/web 아래 정리')"
out="$(runb "$C")"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *"worker/x.py"* ]]; } && ok "ⓔ 인용 0 → 기본 세트(worker/ 포함) → REJECT" || bad "ⓔ rc=$rc ← $out"

echo "== ⓕ 겹침 있음 + --recheck 판정문에 지금 HEAD → 통과(RECHECK 줄) · base_sha 그대로"
C="$(card x '- 고친다: corner-controls-v5.tsx 하나')"
V="$T/verdict.md"; printf '판정: 재대조 OK · head %s\n' "$HEAD" > "$V"
out="$(runb "$C" "$V")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"RECHECK 통과"* ]] && [ "$(sha_of "$C")" = "$BASE" ]; } && ok "ⓕ --recheck 경로 그대로" || bad "ⓕ rc=$rc ← $out"

echo "== ⓖ 리서치 좌석(RESEARCH=1) 면제 → 대조·갱신 0"
C="$(card x '- 고친다: corner-controls-v5.tsx 하나')"
out="$(runb "$C" "" 1)"; rc=$?
{ [ "$rc" = 0 ] && [ -z "$out" ] && [ "$(sha_of "$C")" = "$BASE" ]; } && ok "ⓖ 리서치 면제 그대로(출력 0 · base_sha 그대로)" || bad "ⓖ rc=$rc ← $out"

[ "$SRC" != "$REPO_ROOT/harness/kit/fable-team/bin" ] && echo "INFO 고치기 전 판($SRC)에서 실행 — 위 FAIL 이 red 증거다"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
