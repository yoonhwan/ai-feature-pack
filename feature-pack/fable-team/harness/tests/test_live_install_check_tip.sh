#!/usr/bin/env bash
# test_live_install_check_tip.sh — R367: `--range A..B` 는 «대상 파일 집합»만 정하고, 라이브 대조 blob 은 --ref(기본 origin/main) tip 에서 읽는다.
# 임시 HOME·임시 git 리포(origin/main 은 refs/remotes/origin/main 으로 흉내)·가짜 launchctl 없음(plist 파일 안 건드림). 실 라이브·실 원격·press 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
CHK="$BIN/ft-live-install-check.sh"; GATE="$BIN/ft-index-move-install.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home" FT_BIN="$T/ftbin"; mkdir -p "$HOME" "$FT_BIN"
R="$T/repo"; KD=scripts/harness-install; KA="$KD/fable-team/bin/ft-a.sh"; KB="$KD/fable-team/bin/ft-b.sh"
mkdir -p "$R/$KD/fable-team/bin"
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
commit_kit() { G add -A && G commit -qm "$1" && G update-ref refs/remotes/origin/main HEAD; G rev-parse HEAD; }   # 새 HEAD 를 origin/main 으로 둔다
put() { printf '#!/bin/bash\necho %s\n' "$2" > "$1"; chmod 755 "$1"; }
blob10() { git -C "$R" hash-object --no-filters "$1" | cut -c1-10; }
chk() { out="$(bash "$CHK" "$@" --repo "$R" --kit "$KD" 2>&1)"; rc=$?; }   # r426: r385 뒤 키트 경로 기본 = 하네스 루트 → 임시 리포는 --kit 명시(shim 시험 r413 과 같은 꼴)

put "$R/$KA" v0; C0="$(commit_kit c0)"
put "$R/$KA" v1; B="$(commit_kit B-v1)"          # 착지 B
put "$R/$KA" v2; C="$(commit_kit C-v2-tip)"      # 뒤 커밋이 같은 파일을 또 고침 = tip
put "$FT_BIN/ft-a.sh" v2                          # 라이브 = tip(v2)

# ⓐ 라이브 = tip, 범위 끝 B 는 v1 → OK (지금은 B blob 과 비교해 DIFF — RED)
chk --range "$B^..$B"; [ "$rc" = 0 ] && has "OK n=1"; ck "ⓐ 라이브=tip(뒤 커밋이 덮음) → OK n=1 rc0" $?
# ⓑ 라이브 = v1(낡음) → PENDING + live/tip/landed 줄
put "$FT_BIN/ft-a.sh" v1; L10="$(blob10 "$FT_BIN/ft-a.sh")"; put "$T/v2" v2; TIP10="$(blob10 "$T/v2")"
chk --range "$B^..$B"; [ "$rc" = 1 ] && has "PENDING n=1" && has "DIFF $KA" && has "live=$L10" && has "tip=$TIP10" && has "landed=${B:0:10}"; ck "ⓑ 라이브 낡음 → PENDING + DIFF · live= tip= landed=" $?
# ⓒ B 가 ref 조상이 아님(다른 가지) → ERROR rc3
G checkout -q -b side "$C0"; put "$R/$KA" side; G add -A; G commit -qm side; S="$(G rev-parse HEAD)"; G checkout -q main
put "$FT_BIN/ft-a.sh" v2
chk --range "$C0..$S"; [ "$rc" = 3 ] && has "ERROR" && has "조상"; ck "ⓒ B 가 ref 조상 아님 → ERROR 조상 rc3(조용한 통과 0)" $?
# ⓓ --all 경로 변화 0: 같음 → OK · 다름 → DIFF <키트> -> <라이브> (landed= 없음)
chk --all --ref "$C"; [ "$rc" = 0 ] && has "OK n=1"; ck "ⓓ --all 같음 → OK n=1" $?
put "$FT_BIN/ft-a.sh" v1; chk --all --ref "$C"; [ "$rc" = 1 ] && has "DIFF $KA -> $FT_BIN/ft-a.sh" && ! has "landed="; ck "ⓓ --all 다름 → DIFF 줄 그대로(landed= 0)" $?
put "$FT_BIN/ft-a.sh" v2
# ⓔ 범위 안 파일이 tip 에서 삭제됨 → landed(B) 지도로 라이브 경로를 풀어: 잔재 있음 → STALE PENDING · 없음 → REMOVED OK · 못 풂 → UNKNOWN
put "$R/$KB" b1; B2="$(commit_kit add-b)"; G rm -q -f "$KB"; E="$(commit_kit rm-b)"
put "$FT_BIN/ft-b.sh" b1   # 라이브 잔재
chk --range "$B2^..$B2"; [ "$rc" = 1 ] && has "PENDING n=1" && has "STALE $KB -> $FT_BIN/ft-b.sh" && [ -f "$FT_BIN/ft-b.sh" ]; ck "ⓔ 삭제 + 라이브 잔재 있음 → PENDING STALE rc1 (삭제 0)" $?
rm -f "$FT_BIN/ft-b.sh"
chk --range "$B2^..$B2"; [ "$rc" = 0 ] && has "REMOVED $KB" && has "OK n=0"; ck "ⓔ 삭제 + 라이브 잔재 없음 → REMOVED · OK n=0 rc0" $?
mkdir -p "$R/$KD/newdir"; echo y > "$R/$KD/newdir/y.txt"; B3="$(commit_kit add-unmapped)"; G rm -q -f "$KD/newdir/y.txt"; commit_kit rm-unmapped >/dev/null
chk --range "$B3^..$B3"; [ "$rc" = 1 ] && has "UNKNOWN $KD/newdir/y.txt"; ck "ⓔ 삭제 + landed 지도로 경로 못 풂 → UNKNOWN rc1(조용한 통과 0)" $?
# ⓗ 착지 직후: push 성공 · 로컬 origin/main 은 M(옛) · 라이브는 Q → 기본 ref 는 ERROR, --ref Q 는 OK (ft-merge-land 가 --ref "$Q" 를 넘긴다)
G update-ref refs/remotes/origin/main "$B"
chk --range "$B..$C"; [ "$rc" = 3 ] && has "조상"; ck "ⓗ 로컬 origin/main=M(Q 미반영) 기본 ref → ERROR rc3" $?
chk --range "$B..$C" --ref "$C"; [ "$rc" = 0 ] && has "OK n=1"; ck "ⓗ --ref Q → OK(ERROR 0)" $?
grep -q -- '--ref "\$Q"' "$BIN/ft-merge-land.sh"; ck "ⓗ ft-merge-land.sh 가 착지 직후 검사에 --ref \"\$Q\" 전달" $?
G update-ref refs/remotes/origin/main "$E"
# ⓕ 이동 게이트: --landed <B> 그대로 OK · install-pending 파일 제거
mkdir -p "$R/design/harness/indices/진행"; printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| cfo | `design/cfo/` | c | 현역 |\n' > "$R/design/TEAMS.md"   # R383: 하네스 카드 판정이 팀 폴더 명단을 읽는다
PD="$T/pending"; mkdir -p "$PD"; : > "$PD/$B.txt"
CARD="$R/design/harness/indices/진행/t.md"; printf '# 인덱스: t\n- 설치: 있음\n- 실사건: 뒤 커밋 덮은 카드 · 증거 mbox #107707\n## 상태\n- x\n' > "$CARD"
out="$(FT_INSTALL_PENDING_DIR="$PD" bash "$GATE" "$CARD" --landed "$B" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "OK 설치 확인"; ck "ⓕ ft-index-move-install --landed B → OK(우회 0)" $?
[ ! -e "$PD/$B.txt" ]; ck "ⓕ 통과 시 B 의 install-pending 파일 제거" $?
# ⓖ 오염·상한
[ "$(git -C "$R" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
