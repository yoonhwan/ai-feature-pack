#!/usr/bin/env bash
# test_merge_land_tail_bound_r2061.sh — r2061: 착지 뒤 꼬리 단계(설치 대조 · 뒤처짐 알림)는 손자가 출력을 잡고 남아도 상한 안에 돌아온다
#   꼬리 실행 = ft-merge-lib.sh fm_tail_run 한 함수(출력은 임시 파일 · 직접 자식 pid 만 wait) · 꼬리 상한 = min(지정, 마감 남은 초 − 3)
#   ① 뒤처짐 알림 손자 멈춤 ② 설치 대조 손자 멈춤 ③ 둘 다 ④ 바로 끝남 = 옛 꼴(명령 치환·여유 0)과 출력 같음 ⑤ 남은 ≤ 3초 = 꼬리 호출 0 ⑥ 닫기 실패 + 뒤처짐 멈춤 = rc3
#   변이 M1(뒤처짐 알림 명령 치환) → ① FAIL · M2(설치 대조 명령 치환) → ② FAIL · 변이마다 원본으로 같은 사례 1회 더
#   손자 = 스텁이 띄운 중첩 timeout(자기 process group) + fifo 읽는 cat · 각 착지 뒤 fifo 를 열고 닫아 풂 · 고정 sleep 0 · 실 원격·실 gh 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; el=0; T0=$SECONDS; FIFO=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:600}"; fail=$((fail+1)); fi; }
rel() { [ -p "${1:-}" ] || return 0; exec 3<>"$1"; exec 3>&-; }   # fifo 풀기 — 막힌 cat 이 EOF 를 받는다
T="$(mktemp -d)"; trap 'for f in "$T"/fifo-*; do rel "$f"; done; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state"; ORDER="$T/order.txt"; TBIN="$(command -v timeout || command -v gtimeout)"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" ORDER TBIN FT_INSTALL_CHECK="$T/install-stub" FT_HEAVY_DIR="$T/heavy" FT_PUSH_FIXED_S=1   # push 1단위 = 8초 → 마감 12 안에 착지
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
[ "$1" = pr-close ] || exit 0
[ -z "${FAIL_CLOSE:-}" ] || { echo "GraphQL: Resource not accessible (addComment)" >&2; exit 1; }
exit 0
EOF
# 스텁: HOLD_* 면 손자(중첩 timeout 30 = 자기 process group · 바깥 상한이 못 끝냄)가 출력 pipe 를 물고 fifo 를 읽으며 멈춘다
cat > "$T/install-stub" <<'EOF'
#!/bin/bash
echo install >> "$ORDER"
if [ -n "${HOLD_INSTALL:-}" ]; then "$TBIN" 30 cat "$FIFO" >/dev/null & wait; fi
echo "OK n=1 (r2061 stub)"
EOF
cat > "$T/lag-stub" <<'EOF'
#!/bin/bash
echo head-lag >> "$ORDER"
echo "판정 불가 2곳(훑기 예산 7초 · r2061 stub)" >&2
if [ -n "${HOLD_LAG:-}" ]; then "$TBIN" 30 cat "$FIFO" >/dev/null & wait; fi
exit 0
EOF
chmod +x "$T/gh-stub" "$T/install-stub" "$T/lag-stub"
mkbin() {  # mkbin <폴더> [<파일> <원문> <새문>]… — HERE 사본 + 가짜 head-lag · 쪽지 0 + (변이면) 치환 · 치환 실패 = rc1
  local d="$1"; shift; rm -rf "$d"; cp -R "$BIN" "$d"; cp "$T/lag-stub" "$d/ft-head-lag.sh"
  printf 'fm_land_notify_land() { echo notify >> "$ORDER"; }\n' >> "$d/ft-merge-lib.sh"
  while [ $# -ge 3 ]; do python3 -c 'import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
if s.count(sys.argv[2])!=1: sys.exit("치환 원문 없음: "+sys.argv[2][:60])
open(p,"w",encoding="utf-8").write(s.replace(sys.argv[2],sys.argv[3]))' "$d/$1" "$2" "$3" || return 1; shift 3; done
}
mkpr() {
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <bin> <번호> <바깥 상한초> [KEY=VAL…] — el = 착지 1회 초 · 끝나면 그 착지의 fifo 를 푼다
  local b="$1" n="$2" o="$3" s; shift 3; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$ORDER"
  FIFO="$T/fifo-$n"; rm -f "$FIFO"; mkfifo "$FIFO"; export FIFO; s=$SECONDS
  out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; el=$((SECONDS - s)); rel "$FIFO"
}
ran() { grep -qx "$1" "$ORDER" 2>/dev/null; }
q() { sed -n 's/^LANDED pr=[0-9]* sha=\([0-9a-f]*\).*/\1/p' <<<"$out"; }
c1() { land "$1" "$2" $(($3 + 2)) FT_LAND_TOTAL_S="$3" HOLD_LAG=1   # ① 뒤처짐 알림 손자 멈춤 → 마감 안 rc0 · WARN 1줄
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && [ "$(grep -cE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out")" = 1 ] && [ "$el" -le "$3" ]; }
c2() { land "$1" "$2" $(($3 + 2)) FT_LAND_TOTAL_S="$3" HOLD_INSTALL=1   # ② 설치 대조 손자 멈춤 → rc0 · INSTALL-PENDING 1줄 · 대기 파일 1개
  [ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && [ "$(grep -c '^INSTALL-PENDING 설치 검사' <<<"$out")" = 1 ] && [ -f "$T/.fable-team/state/install-pending/$(q).txt" ] && [ "$el" -le "$3" ]; }
norm() { sed -E 's/[0-9a-f]{7,40}/H/g; s/[0-9]+/N/g'; }
S1=$SECONDS; FIX="$T/bin"; mkbin "$FIX"
c1 "$FIX" 61 12; R1=$?; ck "① 뒤처짐 알림 손자 멈춤 · 마감 12 → rc0 · 마감 안 · WARN 1줄 · LANDED" "$R1"
c2 "$FIX" 62 12; R2=$?; ck "② 설치 대조 손자 멈춤 · 마감 12 → rc0 · INSTALL-PENDING 1줄 · 대기 파일 1" "$R2"
land "$FIX" 63 14 FT_LAND_TOTAL_S=12 HOLD_LAG=1 HOLD_INSTALL=1 FT_INSTALL_CHECK_TIMEOUT=2 FT_HEAD_LAG_EVENT_S=2
[ "$rc" = 0 ] && [ "$el" -le 12 ] && grep -q '^INSTALL-PENDING 설치 검사' <<<"$out" && grep -qE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out"; ck "③ 둘 다 멈춤 → rc0 · 마감 안 · 두 줄" $?
S2=$SECONDS
OLDI='IOUT="$(FT_BIN="${FT_BIN:-$HERE}" "$TB" "$ITO" bash "${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}" --range "$M..$Q" --ref "$Q" --repo "$REPO" 2>&1)"; irc=$?'
NEWI='fm_tail_run IOUT all env FT_BIN="${FT_BIN:-$HERE}" "$TB" "$ITO" bash "${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}" --range "$M..$Q" --ref "$Q" --repo "$REPO"; irc=$?'
OLDH='HLO="$(FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET" 2>&1 >/dev/null)"; hrc=$?'
NEWH='fm_tail_run HLO err env FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET"; hrc=$?'
mkbin "$T/b0" ft-merge-land.sh "$NEWI" "$OLDI" ft-merge-land.sh "$NEWH" "$OLDH" ft-merge-lib.sh 'r=$((r - 3)); ' ''; B0=$?
land "$FIX" 64 30; o4="$out"; r4=$rc; land "$T/b0" 65 30
[ "$B0" = 0 ] && [ "$r4" = 0 ] && [ "$rc" = 0 ] && [ "$(norm <<<"$o4")" = "$(norm <<<"$out")" ] && grep -q '^판정 불가 2곳' <<<"$o4" && ! grep -q '^WARN' <<<"$o4" && grep -q '^INSTALL OK n=1' <<<"$o4"
ck "④ 바로 끝남 → 옛 꼴(명령 치환 · 여유 0)과 줄·순서 같음 · 판정 불가 줄 통과" $?
land "$FIX" 66 14 FT_LAND_TOTAL_S=12 "FT_LAND_DEADLINE=$(( $(date +%s) + 3 ))"
[ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && ! ran install && ! ran head-lag && grep -q '^INSTALL-PENDING 설치 검사 0초 초과' <<<"$out" && grep -q '^WARN 뒤처짐 알림 0초 초과' <<<"$out"
ck "⑤ 마감 남은 ≤ 3초 → 꼬리 호출 0 · 문구 1줄씩" $?
CPL="$T/state/merge-close-pending.jsonl"; : > "$CPL"
land "$FIX" 67 14 FT_LAND_TOTAL_S=12 HOLD_LAG=1 FAIL_CLOSE=1 FT_HEAD_LAG_EVENT_S=2
[ "$rc" = 3 ] && [ "$el" -le 12 ] && [ "$(grep -c . "$CPL")" = 1 ] && grep -qE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out"; ck "⑥ 닫기 실패 + 뒤처짐 멈춤 → rc3 · 닫기 대기 1줄" $?
: > "$CPL"; S3=$SECONDS
mkbin "$T/m1" ft-merge-land.sh "$NEWH" "$OLDH" && { c1 "$T/m1" 72 12; [ $? != 0 ]; } && [ "$R1" = 0 ]; ck "변이 M1 뒤처짐 알림 명령 치환 → ① FAIL(바깥 상한에 잘림 rc=$rc) · 원본 ① PASS" $?
mkbin "$T/m2" ft-merge-land.sh "$NEWI" "$OLDI" && { c2 "$T/m2" 74 12; [ $? != 0 ]; } && [ "$R2" = 0 ]; ck "변이 M2 설치 대조 명령 치환 → ② FAIL(바깥 상한에 잘림 rc=$rc) · 원본 ② PASS" $?
S4=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 cmp0(land·lib)" $?
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ] && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-land.sh ≤ 120줄 · bash -n" $?
echo "단계별 초: ①~③ $((S2 - S1)) · ④~⑥ $((S3 - S2)) · 변이 $((S4 - S3)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
