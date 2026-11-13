#!/usr/bin/env bash
# test_merge_land_close_before_lag_r1389.sh — r1389: 착지 뒤 단계(설치 대조 · 뒤처짐 알림)는 착지 마감(FT_LAND_DEADLINE)의 «남은 시간» 안에서만 돈다.
#   PR 닫기는 그 앞(r1592) · 남은 시간 < 1초면 호출 0 + 1줄(timeout 0 = 무한 함정 차단) · 착지 rc·LANDED 줄·push 줄 불변
#   C1 head-lag 멈춤 + 마감 6초 → 상한 = 남은 시간(<25) WARN · rc0 · 닫기 1회  C2 설치 검사 멈춤 → 남은 시간에 끊김 · head-lag 은 호출 0 + WARN
#   C3 정상 = 출력·rc 그대로  C4 닫기 실패 = rc3 · 장부 1줄 · 뒤 단계 돎  C5 push 거절 = 닫기 0
#   변이 V1(head-lag 고정 상한) → C1 FAIL · V2(설치 고정 상한) → C2 FAIL · V3(남은 0 검사 삭제) → C2 FAIL
#   임시 origin+clone · 가짜 gh·가짜 head-lag(HERE 사본)·가짜 설치 검사 · 고정 sleep 0 · 실 원격·실 gh 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:500}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'touch "$T/go"; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"; ORDER="$T/order.txt"; GO="$T/go"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" ORDER GO FT_INSTALL_CHECK="$T/install-stub"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
[ "$1" = pr-close ] || exit 0
echo close >> "$ORDER"
[ -z "${FAIL_CLOSE:-}" ] || { echo "GraphQL: Resource not accessible (addComment)" >&2; exit 1; }
exit 0
EOF
# 설치 검사·head-lag 가짜: HOLD_*=1 이면 표식 파일($GO)이 생길 때까지 멈춘다(고정 sleep 0 · 바깥 timeout 이 끊는다)
printf '#!/bin/bash\necho install >> "$ORDER"\n[ -z "${HOLD_INSTALL:-}" ] || while [ ! -e "$GO" ]; do :; done\necho "OK n=1 (r1389 stub)"\nexit 0\n' > "$T/install-stub"
HL='#!/bin/bash\necho head-lag >> "$ORDER"\n[ -z "${HOLD_LAG:-}" ] || while [ ! -e "$GO" ]; do :; done\nexit 0\n'
chmod +x "$T/gh-stub" "$T/install-stub"
mkbin() {  # mkbin <폴더> [python 치환 원문 새문] — HERE 사본 + 가짜 head-lag · 쪽지 + (변이면) 한 곳 치환
  rm -rf "$1"; cp -R "$BIN" "$1"; printf "$HL" > "$1/ft-head-lag.sh"; chmod +x "$1/ft-head-lag.sh"
  printf 'fm_land_notify_land() { echo notify >> "$ORDER"; }\n' >> "$1/ft-merge-lib.sh"
  [ $# -lt 3 ] || python3 -c 'import sys
p=sys.argv[1]+"/ft-merge-land.sh"; s=open(p,encoding="utf-8").read(); assert s.count(sys.argv[2])==1, sys.argv[2]
open(p,"w",encoding="utf-8").write(s.replace(sys.argv[2],sys.argv[3]))' "$1" "$2" "$3"
}
mkpr() {
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <bin> <번호> [KEY=VAL…] — 바깥 timeout 40(호출자 70 의 대역) · el = 착지 1회 초
  local b="$1" n="$2" s; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$ORDER"; rm -f "$GO"; s=$SECONDS
  out="$(env "$@" timeout 40 bash "$b/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s)); touch "$GO"
}
ran() { grep -qx "$1" "$ORDER" 2>/dev/null; }
closes() { grep -c '^pr-close' "$STUB_LOG" 2>/dev/null; }
dl() { echo "FT_LAND_DEADLINE=$(( $(date +%s) + 6 ))"; }   # 호출자 마감 대역 — 착지 1회 마감 epoch(r1363 이 자식에 넘기는 값과 같은 칸)
c1() { land "$1" "$2" HOLD_LAG=1 FT_HEAD_LAG_EVENT_S=12 "$(dl)"
  [ "$rc" = 0 ] && grep -q "^LANDED" <<<"$out" && [ "$(closes)" = 1 ] && grep -qE '^WARN 뒤처짐 알림 [0-6]초 초과' <<<"$out" && [ "$el" -le 9 ]; }
c2() { land "$1" "$2" HOLD_INSTALL=1 FT_INSTALL_CHECK_TIMEOUT=12 "$(dl)"
  [ "$rc" = 0 ] && grep -q "^LANDED" <<<"$out" && [ "$(closes)" = 1 ] && grep -q '^INSTALL-PENDING 설치 검사 [0-6]초 초과' <<<"$out" \
    && ! ran head-lag && grep -qE '^WARN 뒤처짐 알림 0초 초과' <<<"$out" && [ "$el" -le 9 ]; }
S1=$SECONDS; FIX="$T/bin"; mkbin "$FIX"

c1 "$FIX" 61; ck "C1 head-lag 멈춤 · 마감 6초 → WARN 남은 시간 상한 · 닫기 1회 · rc0 · ≤9초" $?
c2 "$FIX" 62; ck "C2 설치 검사 멈춤 → 남은 시간에 끊김 · head-lag 호출 0 + WARN 0초 · rc0 · ≤9초" $?
land "$FIX" 63
[ "$rc" = 0 ] && grep -q "^LANDED" <<<"$out" && grep -q '^push ok objects=' <<<"$out" && grep -q '^INSTALL OK n=1' <<<"$out" && ran head-lag && ! grep -q '^WARN' <<<"$out" \
  && [ "$(head -n1 "$ORDER")" = close ]; ck "C3 정상 → LANDED·push ok·INSTALL 그대로 · WARN 0 · 닫기 먼저" $?
CPL="$T/state/merge-close-pending.jsonl"; : > "$CPL" 2>/dev/null
land "$FIX" 64 FAIL_CLOSE=1
[ "$rc" = 3 ] && grep -q 'WARN 착지는 성공 — PR #64 코멘트/닫기 실패' <<<"$out" && [ "$(grep -c . "$CPL")" = 1 ] && ran install && ran head-lag; ck "C4 닫기 실패 → rc3 · 장부 1줄 · 설치·head-lag 돎" $?
: > "$CPL"
printf '#!/bin/sh\ngrep -q " refs/heads/main$" || exit 0\necho "denied by r1389 test" >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
land "$FIX" 65
[ "$rc" = 1 ] && grep -q '^REJECT' <<<"$out" && [ "$(closes)" = 0 ]; ck "C5 push 거절 → REJECT rc1 · 닫기 0" $?
rm -f "$ORIGIN/hooks/pre-receive"
S2=$SECONDS

HLN='HLTO="$(fm_tail_s "${FT_HEAD_LAG_EVENT_S:-25}")"'; ITN='ITO="$(fm_tail_s "${FT_INSTALL_CHECK_TIMEOUT:-7}")"'
mkbin "$T/v1" "$HLN" 'HLTO="${FT_HEAD_LAG_EVENT_S:-25}"'; c1 "$T/v1" 71; [ $? != 0 ]; ck "변이 V1 head-lag 고정 상한 12 → C1 FAIL" $?
mkbin "$T/v2" "$ITN" 'ITO="${FT_INSTALL_CHECK_TIMEOUT:-7}"'; c2 "$T/v2" 72; [ $? != 0 ]; ck "변이 V2 설치 고정 상한 → C2 FAIL" $?
mkbin "$T/v3" '[ "$HLTO" -ge 1 ] && ' ''; c2 "$T/v3" 73; [ $? != 0 ]; ck "변이 V3 남은 0 검사 삭제 → C2 FAIL(head-lag 호출됨)" $?
S3=$SECONDS

cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 cmp0(land·lib)" $?
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ] && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-land.sh ≤ 120줄 · bash -n" $?
echo "단계별 초: C1~C5 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
