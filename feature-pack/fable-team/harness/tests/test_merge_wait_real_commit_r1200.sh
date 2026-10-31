#!/usr/bin/env bash
# test_merge_wait_real_commit_r1200.sh — r1200: ft-merge-land «승인 파일 없음» 거절의 기다림 표식은 실제 커밋 sha 에만 · 승인된 조상이 있으면 표식 0 + 안내 · ft-hil-notify.sh void-scan (카드 반례 R1~R6)
# 격리: 임시 origin+clone(_merge_fixture) · 임시 상태 폴더 · 가짜 쪽지함 · 가짜 gh(R3) — 실 리포·실 gh·실 상태 0 · 고정 sleep 0 · 자기 재호출은 real_state_guard 재진입 표지(RSG_ACTIVE)뿐
# 변이 대조: R1200_BIN=<변이 사본 bin> 으로 돌리면 ⓐ(ft-merge-lib.sh fm_ap_wait 의 cat-file 확인 두 줄 삭제 → 커밋 아닌 sha 에 표식 1)가 FAIL 한다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1200_BIN:-$HERE/../bin}"
. "$HERE/_merge_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

C="$T/comm"; mkdir -p "$C" "$T/state"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
mkrepo "$T/r"; mkdir -p "$T/r/.fable-team"
git -C "$ORIGIN" config uploadpack.allowAnySHA1InWant true   # GitHub 처럼 sha 로 fetch 허용(R2b)
export FT_ROOT="$T/r" FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_LEVEL=each FT_MBOX_DIR="$C" FT_SEAT='byz-cfo-master-claude#120'
WD="$T/state/autonomy-merge-wait"
sib() { git -C "$W" commit-tree "$M0^{tree}" -p "${2:-$M0}" -m "$1"; }   # main 밖 형제 커밋(로컬 객체만)
land() { out="$(bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$1" --repo "$W" 2>&1)"; rc=$?; }
nmark() { ls "$WD" 2>/dev/null | grep -cxE '[0-9a-f]{40}'; }
approve() { bash "$BIN/ft-autonomy.sh" approve-merge "$1" >/dev/null 2>&1; }

echo "== ⓐ R1 커밋 아닌 40hex · 승인 파일 없음 → REJECT «커밋이 아님» rc2 · 표식 0"
FAKE="390b15c540cec6a2e4a8b6b9f1f8e3e0f1c6c1c0"; land "$FAKE"
[ "$rc" = 2 ] && has "$out" "REJECT 승인 sha 가 이 리포 커밋이 아님(오타 또는 받기 실패) — ${FAKE:0:10} · 기다림 등록 0" "커밋 아님 거절 rc2" || bad "rc=$rc $out"
[ ! -e "$WD/$FAKE" ] && [ "$(nmark)" = 0 ] && ok "  └ 표식 0" || bad "표식이 생겼다: $(ls "$WD" 2>&1)"

echo "== ⓑ R2 실제 커밋(로컬) · 승인 파일 없음 → 지금과 같음(REJECT 승인 파일 없음 + 표식 1)"
S2="$(sib s2)"; land "$S2"
[ "$rc" = 2 ] && has "$out" "REJECT 오빠 승인 파일 없음" "승인 파일 없음 거절 rc2 그대로" || bad "rc=$rc $out"
has "$out" "기다림 등록 $WD/$S2" "  └ 기다림 등록 줄"
grep -qE '^seat=byz-cfo-master-claude#120 epoch=[0-9]+$' "$WD/$S2" 2>/dev/null && ok "  └ 표식 1" || bad "표식: $(cat "$WD/$S2" 2>&1)"

echo "== ⓑ R2b 원격에만 있는 실제 커밋 → fetch 뒤 표식 1"
O2="$T/o2"; git clone -q "$ORIGIN" "$O2" 2>/dev/null; git -C "$O2" config user.name t; git -C "$O2" config user.email t@t
git -C "$O2" checkout -q -b side; printf 'x\n' > "$O2/x.txt"; cm "$O2" remote-only; RB="$(sha "$O2" HEAD)"; git -C "$O2" push -q origin side
git -C "$W" cat-file -e "$RB^{commit}" 2>/dev/null && bad "전제 깨짐: 로컬에 이미 있음" || ok "  └ 전제: 로컬 없음"
land "$RB"
[ "$rc" = 2 ] && has "$out" "REJECT 오빠 승인 파일 없음" "원격 전용 커밋 = 승인 파일 없음 거절" || bad "rc=$rc $out"
[ -f "$WD/$RB" ] && ok "  └ 표식 1(fetch 뒤)" || bad "표식 없음: $(ls "$WD")"

echo "== ⓑ2 R2c 승인된 X 위 main 병합만 얹은 Y → 표식 0 · 안내 줄에 X 40자"
X="$(sib x-approved)"; approve "$X"
printf 'm\n' > "$W/m.txt"; cm "$W" main-moves; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; M1="$(sha "$W" HEAD)"
Y="$(git -C "$W" commit-tree "$M1^{tree}" -p "$X" -p "$M1" -m "Merge main into nano")"; land "$Y"
[ "$rc" = 2 ] && has "$out" "REJECT 이 sha 는 승인 sha 가 아님 — 승인된 조상 ${X:0:10} 가 있다" "승인된 조상 안내 rc2" || bad "rc=$rc $out"
has "$out" "--approve-sha $X 로 다시" "  └ 안내 줄에 X 40자"
[ ! -e "$WD/$Y" ] && ok "  └ 표식 0" || bad "표식이 생겼다"
X2="$(sib x2-approved "$X")"; approve "$X2"; Y2="$(git -C "$W" commit-tree "$M1^{tree}" -p "$X2" -p "$M1" -m "Merge main 2")"; land "$Y2"
has "$out" "승인된 조상 ${X2:0:10}" "승인된 조상 여럿 = 가장 가까운 1개(X2)"

echo "== ⓑ2 R2d 승인된 sha 가 있으나 Y 의 조상 아님(다른 PR) → 표식 1"
Z="$(sib z-approved)"; approve "$Z"; Y3="$(sib other-pr "$M1")"; land "$Y3"
[ "$rc" = 2 ] && has "$out" "REJECT 오빠 승인 파일 없음" "조상 아님 = 승인 파일 없음 거절 그대로" || bad "rc=$rc $out"
[ -f "$WD/$Y3" ] && ok "  └ 표식 1" || bad "표식 없음"

echo "== ⓑ R3 승인 파일 있음 → 커밋 확인 길 안 탐(승인 파일 없음 거절 0 · 표식 0)"
printf '#!/bin/bash\nexit 1\n' > "$T/gh"; chmod +x "$T/gh"; n0="$(nmark)"
out="$(FT_GH="$T/gh" bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$Z" --repo "$W" 2>&1)"; rc=$?
[ "$rc" != 2 ] && case "$out" in *"승인 파일 없음"*|*"커밋이 아님"*|*"승인된 조상"*) bad "승인 길에서 거절: $out";; *) ok "승인 파일 통과(다음 단계 gh 거절 rc=$rc)";; esac || bad "rc=$rc $out"
[ "$(nmark)" = "$n0" ] && ok "  └ 새 표식 0" || bad "표식 수 바뀜"

echo "== ⓒ R4 void-scan: 커밋 1 · 커밋 아님 1 · .sent 1 → 커밋 아님만 .void · «바꿈=1 그대로=1»"
V="$T/v"; VW="$V/autonomy-merge-wait"; mkdir -p "$VW"
printf 'seat=byz-lecture-master-claude#29 epoch=1\n' > "$VW/$FAKE"; printf 'seat=a epoch=1\n' > "$VW/$S2"; printf 'seat=b epoch=1\n' > "$VW/$M0.sent"
out="$(bash "$BIN/ft-hil-notify.sh" void-scan "$V" "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "$out" "VOID $FAKE seat=byz-lecture-master-claude#29" "VOID 줄(seat)" || bad "rc=$rc $out"
has "$out" "void-scan 끝 바꿈=1 그대로=1" "  └ 끝 줄 수"
[ -f "$VW/$FAKE.void" ] && [ ! -e "$VW/$FAKE" ] && [ -f "$VW/$S2" ] && [ -f "$VW/$M0.sent" ] && ok "  └ 커밋 아님만 .void · 나머지 이름 그대로" || bad "폴더: $(ls "$VW")"

echo "== ⓒ R5 void-scan: 둘째 리포에서만 커밋 → 그대로"
mkrepo "$T/r2"; printf 'q\n' > "$T/r2/w/q.txt"; cm "$T/r2/w" only-r2; Q2="$(sha "$T/r2/w" HEAD)"; printf 'seat=c epoch=1\n' > "$VW/$Q2"
git -C "$T/r/w" cat-file -e "$Q2^{commit}" 2>/dev/null && bad "전제 깨짐: 첫 리포에도 있음" || ok "  └ 전제: 첫 리포 없음"
out="$(bash "$BIN/ft-hil-notify.sh" void-scan "$V" "$T/r/w" "$T/r2/w" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$VW/$Q2" ] && has "$out" "void-scan 끝 바꿈=0 그대로=2" "어디에도 없을 때만 .void" || bad "rc=$rc $out · $(ls "$VW")"

echo "== ⓓ R6 void-scan: 리포 경로가 git 아님 → 판정 불가 rc≠0 · 바꿈 0"
printf 'seat=d epoch=1\n' > "$VW/$FAKE"; before="$(ls "$VW")"; mkdir -p "$T/notgit"
out="$(bash "$BIN/ft-hil-notify.sh" void-scan "$V" "$W" "$T/notgit" 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "판정 불가" "판정 불가 rc=$rc" || bad "rc=$rc $out"
[ "$(ls "$VW")" = "$before" ] && ok "  └ 바꿈 0" || bad "폴더 바뀜: $(ls "$VW")"

echo "== ⓘ 팩 추적본 bin = 키트 bin (cmp0 ×3)"
K="$HERE/../kit/fable-team/bin"
for f in ft-hil-notify.sh ft-merge-land.sh ft-merge-lib.sh; do cmp -s "$HERE/../bin/$f" "$K/$f" && ok "cmp0 $f" || bad "키트 사본 다름: $f"; done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
