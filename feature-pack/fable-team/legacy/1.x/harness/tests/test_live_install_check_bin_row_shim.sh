#!/usr/bin/env bash
# test_live_install_check_bin_row_shim.sh — r583: bin 행의 라이브 파일이 «연결 파일(shim)» 이면 ft_live_install_check 가
# <그 폴더>/../LIVE_BIN 의 «판 폴더» 같은 상대 경로 파일과 대조하고 줄 끝에 «via shim → <판 폴더>» 를 붙인다.
# 팀 env FT_BIN = 연결 파일 폴더 → 설치가 맞아도 DIFF 로 나오던 것(완성 이동 16장 정지).
# 임시 HOME·임시 git 리포(= 프로젝트 루트)·임시 판 폴더·임시 연결 파일만 — 실 라이브·실 원격·press·Redis 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
CHK="${FT_CHK:-$BIN/ft-live-install-check.sh}"   # FT_CHK = 옛 판 대조(전/후 red 증거용)
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:800}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home" FT_BIN="$T/repo/.fable-team/bin"; mkdir -p "$HOME" "$FT_BIN"
LIVE="$T/live"; mkdir -p "$LIVE"                       # 판 폴더(= LIVE_BIN 이 가리키는 곳)
LIVE_P="$(cd "$LIVE" && pwd -P)"                        # realpath — 출력 판 폴더와 같은 글자
R="$T/repo"; KD=scripts/harness-install; KBIN="$KD/fable-team/bin"
mkdir -p "$R/$KBIN"
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
put() { printf '#!/bin/bash\necho %s\n' "$2" > "$1"; chmod 755 "$1"; }
put "$R/$KBIN/ft-a.sh" a; put "$LIVE/ft-a.sh" a                 # 키트 = 판 폴더(DIFF 0)
G add -A && G commit -qm kit && G update-ref refs/remotes/origin/main HEAD
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_BIN"
shim() { printf '# ft-root-bin-shim: ft-a.sh → LIVE_BIN\n# 설치본 아님 — 판 폴더로 넘긴다\n' > "$1"; chmod 755 "$1"; }
shim "$R/.fable-team/bin/ft-a.sh"                              # 프로젝트 루트 연결 파일(shim 검사 통과용)
chk() { out="$(bash "$CHK" "$@" --repo "$R" --kit "$KD" --project "$R" 2>&1)"; rc=$?; }
shim "$FT_BIN/ft-a.sh"                                         # FT_BIN = 연결 파일 폴더(팀 env 그대로)

# ⓐ FT_BIN = 연결 파일 폴더 · 판 폴더 파일 = 키트 → OK rc0 (옛 판 = DIFF rc1 · 전/후 red 증거)
chk --all; [ "$rc" = 0 ] && has "OK n=1" && ! has "DIFF"; ck "ⓐ 연결 파일 → 판 폴더 파일 대조 = OK rc0" $?
# ⓑ 판 폴더 파일이 키트와 다름 → 진짜 어긋남은 그대로 DIFF · «via shim → 판 폴더» 표시
put "$LIVE/ft-a.sh" b; chk --all; [ "$rc" = 1 ] && has "DIFF $KBIN/ft-a.sh -> $FT_BIN/ft-a.sh" && has "via shim → $LIVE_P"; ck "ⓑ 판 폴더 어긋남 = DIFF + via shim → 판 폴더" $?
cp "$R/$KBIN/ft-a.sh" "$LIVE/ft-a.sh"
# ⓒ1 연결 파일인데 ../LIVE_BIN 없음 → MISSING rc1 (통과로 후퇴 0)
O="$T/other/bin"; mkdir -p "$O"; shim "$O/ft-a.sh"; FT_BIN="$O" chk --all
[ "$rc" = 1 ] && has "MISSING $KBIN/ft-a.sh" && has "LIVE_BIN (없음)"; ck "ⓒ1 ../LIVE_BIN 없음 = MISSING rc1" $?
# ⓒ2 LIVE_BIN 이 절대경로 아님 → ERROR rc3 (조용한 폴백 0)
printf 'relative/path\n' > "$O/../LIVE_BIN"; FT_BIN="$O" chk --all
[ "$rc" = 3 ] && has "ERROR LIVE_BIN 이 절대경로 폴더가 아님"; ck "ⓒ2 LIVE_BIN 절대경로 아님 = ERROR rc3" $?
# ⓒ3 판 폴더에 같은 이름 파일 없음 → MISSING rc1
printf '%s\n' "$T/nope" > "$O/../LIVE_BIN"; mkdir -p "$T/nope"; NOPE="$(cd "$T" && pwd -P)/nope"; FT_BIN="$O" chk --all
[ "$rc" = 1 ] && has "MISSING $KBIN/ft-a.sh" && has "via shim → $NOPE"; ck "ⓒ3 판 폴더 파일 없음 = MISSING rc1" $?
rm -f "$O/../LIVE_BIN"
# ⓓ FT_BIN = 판 폴더(연결 파일 아님) → 동작 불변 OK rc0
FT_BIN="$LIVE" chk --all; [ "$rc" = 0 ] && has "OK n=1" && ! has "via shim"; ck "ⓓ 판 폴더 직접 = 동작 불변 rc0" $?
# ⓔ 오염·상한
[ "$(git -C "$R" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
