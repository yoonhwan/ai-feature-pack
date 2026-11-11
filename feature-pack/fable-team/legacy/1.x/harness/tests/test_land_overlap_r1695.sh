#!/usr/bin/env bash
# test_land_overlap_r1695.sh — r1695 ft-land-overlap.sh(같은 파일 사전 경고 · 경고만) + ft-merge-land.sh 게이트 ④ 앞 DRY 1줄 배선
#   ⓓ ⓧ1 재현: 후보가 바꾼 a.txt 를 대상(main)이 먼저 착지 → «OVERLAP 1 landed=a.txt open=-» rc1
#      겹침 없음 → «CLEAR» rc0 · 열린 팀장 가지가 같은 파일 → open=<좌석:파일> rc1
#      merge-land: 배선 사본·배선 없는 사본 모두 LANDED rc0 · stdout 에 경고 줄 0 · state/land-overlap.log 1줄(pr=번호)
#   변이(사본): M3 겹침 계산을 merge-base 이후 대신 후보 tip 기준 → CLEAR 사례 FAIL
# 임시 bare 원격 · 가짜 gh · 실 원격 push 0 · 실 state 0 · sleep 0
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; echo .worktrees/ >> "$W/.git/info/exclude"; S0=$SECONDS
git -C "$W" checkout -q -b cand "$M0"; printf 'l1\nCAND\nl3\n' > "$W/a.txt"; cm "$W" "cand a"
git -C "$W" checkout -q -b cand2 "$M0"; echo c > "$W/c.txt"; cm "$W" "cand2 c"
git -C "$W" checkout -q main; printf 'l1\nMAIN\nl3\n' > "$W/a.txt"; echo b2 > "$W/b.txt"; cm "$W" "main lands a b"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
SD="$T/seats"; mkdir -p "$SD"
ov() { out="$(bash "${OV:-$BIN/ft-land-overlap.sh}" "$@" --repo "$W" --seats-dir "$SD" --no-fetch 2>&1)"; rc=$?; }
case_landed() { ov cand --target main; [ "$rc" = 1 ] && [ "$(tail -n1 <<<"$out")" = "OVERLAP 1 landed=a.txt open=-" ] && [[ "$(head -n1 <<<"$out")" == "BASE main=$(sha "$W" origin/main) "* ]]; }
case_clear() { ov cand2 --target main; [ "$rc" = 0 ] && [ "$(tail -n1 <<<"$out")" = CLEAR ]; }
case_landed; ck "ⓓ ⓧ1 재현 → OVERLAP 1 landed=a.txt rc1 · 첫 줄 BASE" $?
case_clear; ck "ⓓ 겹침 없음 → CLEAR rc0" $?
L="$W/.worktrees/lead"; git -C "$W" worktree add -q -b lead/x "$L" origin/main; echo lead > "$L/c.txt"; cm "$L" "lead c"
printf '{"_master":"byz-ops-master-pi#1","byz-ops-master-pi#1":{"worktree":"lead"}}\n' > "$SD/seats-ops.json"
ov cand2 --target main; [ "$rc" = 1 ] && [ "$(tail -n1 <<<"$out")" = "OVERLAP 1 landed=- open=byz-ops-master-pi#1:c.txt" ]; ck "ⓓ 동시 작업 겹침 → open=좌석:파일 rc1" $?
ov lead/x --target main; [ "$rc" = 0 ] && [ "$(tail -n1 <<<"$out")" = CLEAR ]; ck "ⓓ 후보 자신(팀장 가지)은 동시 작업에서 뺀다" $?
ov nosuch; [ "$rc" = 3 ] && grep -q '^판정 불가 후보' <<<"$out"; ck "후보 못 풂 = rc3 판정 불가" $?
rm -f "$SD/seats-ops.json"

M3="$T/mut-M3.sh"; python3 - "$BIN/ft-land-overlap.sh" "$M3" <<'PY' || { echo "FAIL M3 변이 적용 실패"; fail=$((fail+1)); }
import sys
s=open(sys.argv[1],encoding='utf-8').read(); a="landed = sorted(mine & files(root, mb, tsha))"; assert s.count(a)==1
open(sys.argv[2],'w',encoding='utf-8').write(s.replace(a,"landed = sorted(mine & files(root, cand, tsha))"))
PY
OV="$M3" FT_LEAD_STATUS="$BIN/ft-lead-wt-status.sh" case_clear; [ $? != 0 ]; ck "M3 변이(후보 tip 기준) → CLEAR 사례 FAIL(잡힘)" $?

# merge-land 배선 — r1687 시험과 같은 사본 묶음 + 가짜 gh
export STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_GH="$T/gh" FT_GH_WRITE="$T/gh" FT_INSTALL_CHECK="$T/ick"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\n' > "$T/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/ick"; chmod +x "$T/gh" "$T/ick"
ST="$T/.fable-team/state"; mkdir -p "$ST"; export FT_AUTONOMY_STATE_DIR="$ST"; printf '%s\n' "$M0" > "$ST/base-head"
inst() {  # inst <루트> [겹침 도구 포함 1] — 병합 도구 묶음 사본
  local b="$1/.fable-team/bin" f; mkdir -p "$b"
  for f in ft-merge-land.sh ft-merge-lib.sh ft-evidence-lib.sh ft-heavy-slot-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-autonomy.sh ft-autonomy-level.sh ft-autonomy-oppa.sh ft-autonomy-scope.sh ft-autonomy-standing.sh ft-autonomy-standing-d2.sh ft-goal-table.sh ft-team-lib.sh ft-harness-root.sh ft-merge-deny.sh ft-merge-deny.txt ft-press-evidence.sh press_evidence_land.py press_evidence_verify.py press_evidence_parts.py; do cp "$BIN/$f" "$b/$f"; done
  [ -z "${2:-}" ] || cp "$BIN/ft-land-overlap.sh" "$BIN/ft-lead-wt-status.sh" "$b/"
  for f in ft-autonomy-start.sh ft-head-lag.sh; do printf '#!/bin/bash\nexit 0\n' > "$b/$f"; done
  chmod +x "$b"/*.sh; echo "$b"
}
XA="$(inst "$T/a")"; XB="$(inst "$T/b" 1)"
land() { out="$(cd "$T" && FT_ROOT="$T" bash "$1/ft-merge-land.sh" "${@:2}" --repo "$W" 2>&1)"; rc=$?; }
mkpr() {  # mkpr <번호> <브랜치> <파일> → PRSHA · STUB_JSON
  git -C "$W" checkout -q -B "$2" origin/main; echo "pr$1" > "$W/$3"; cm "$W" "pr $1"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
FT_ROOT="$T" bash "$XA/ft-autonomy.sh" on >/dev/null 2>&1
mkpr 41 pr41 p41.txt; FT_ROOT="$T" bash "$XA/ft-autonomy.sh" approve-merge "$PRSHA" >/dev/null 2>&1; land "$XA" 41 --approve-sha "$PRSHA"; ra="$rc"; oa="$(grep -vE '^(LANDED|push ok|INSTALL|INFO)' <<<"$out" | sed "s|$T/a/|X/|g")"
[ "$ra" = 0 ] && [[ "$out" == LANDED* ]] && [ ! -e "$ST/land-overlap.log" ]; ck "배선 없는 사본: LANDED rc0 · 로그 0" $?
git -C "$W" fetch -q origin; mkpr 42 pr42 p42.txt; FT_ROOT="$T" bash "$XA/ft-autonomy.sh" approve-merge "$PRSHA" >/dev/null 2>&1; land "$XB" 42 --approve-sha "$PRSHA"
[ "$rc" = "$ra" ] && [[ "$out" == LANDED* ]] && ! grep -qE '^(OVERLAP|CLEAR|BASE )' <<<"$out" && [ "$(grep -vE '^(LANDED|push ok|INSTALL|INFO)' <<<"$out" | sed "s|$T/b/|X/|g")" = "$oa" ]; ck "배선 사본: LANDED rc 같음 · stdout 에 경고 줄 0 · 나머지 줄 같음(사본 경로만 정규화)" $?
[ "$(wc -l < "$ST/land-overlap.log" | tr -d ' ')" = 1 ] && grep -qE ' pr=42 (CLEAR|OVERLAP )' "$ST/land-overlap.log"; ck "배선 사본: state/land-overlap.log 1줄(pr=42 · CLEAR|OVERLAP)" $?
echo "secs=$((SECONDS-S0)) fail=$fail"
[ "$fail" = 0 ]
