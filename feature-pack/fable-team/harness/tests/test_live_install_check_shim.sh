#!/usr/bin/env bash
# test_live_install_check_shim.sh — R374: 라이브 bin 의 도구마다 루트 `.fable-team/bin/<이름>` 연결 파일(shim, 헤더 `# ft-root-bin-shim:`)이 없으면
# ft-live-install-check.sh 가 `PENDING shim <이름>` 줄(ft-merge-land 가 `INSTALL ` 을 앞에 붙임)로 보고한다.
# 임시 HOME·임시 git 리포(= 임시 루트)·가짜 라이브 bin 만 — 실 라이브·실 원격·press·Redis 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
CHK="$BIN/ft-live-install-check.sh"; SHIM="$BIN/ft-root-bin-shim.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home" FT_BIN="$T/live"; mkdir -p "$HOME" "$FT_BIN"
R="$T/repo"; KD=scripts/harness-install; KBIN="$KD/fable-team/bin"
mkdir -p "$R/$KBIN" "$R/.fable-team/bin"
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
put() { printf '#!/bin/bash\necho %s\n' "$2" > "$1"; chmod 755 "$1"; }
for n in ft-x.sh ft-y.sh ft-z.sh; do put "$R/$KBIN/$n" "$n"; put "$FT_BIN/$n" "$n"; done   # 키트 = 라이브(DIFF 0)
G add -A && G commit -qm kit && G update-ref refs/remotes/origin/main HEAD
printf '%s\n' "$FT_BIN" > "$R/.fable-team/LIVE_BIN"
chk() { out="$(bash "$CHK" "$@" --repo "$R" 2>&1)"; rc=$?; }
mkshim() { out="$(bash "$SHIM" --root "$R" --live "$FT_BIN" --ref main 2>&1)"; rc=$?; }
shim_lines() { printf '%s\n' "$out" | grep -c '^PENDING shim '; }

# ⓐ 라이브에 ft-x.sh 있고 루트 shim 0 → 3줄 PENDING shim + rc1
chk --all; [ "$rc" = 1 ] && has "PENDING shim ft-x.sh" && has "PENDING shim ft-y.sh" && has "PENDING shim ft-z.sh" && [ "$(shim_lines)" = 3 ]; ck "ⓐ 루트 shim 0 → PENDING shim ×3 rc1" $?
# ⓑ shim 재생성(실 도구) → 그 줄 0 · OK
mkshim; [ "$rc" = 0 ] && has "SHIM 3 · MOVED 0 · UNKNOWN 0"; ck "ⓑ0 ft-root-bin-shim.sh → SHIM 3" $?
chk --all; [ "$rc" = 0 ] && has "OK n=" && ! has "shim"; ck "ⓑ shim 실재 → OK · shim 줄 0 rc0" $?
# ⓒ 라이브에 없는 루트 항목(옛 사본) → 이 검사 대상 아님
put "$R/.fable-team/bin/ft-old.sh" old
chk --all; [ "$rc" = 0 ] && ! has "ft-old.sh"; ck "ⓒ 라이브에 없는 루트 옛 사본 → 보고 0" $?
rm -f "$R/.fable-team/bin/ft-old.sh"
# ⓓ LIVE_BIN 파일 없음 → 기존 동작 그대로(새 ERROR 0)
rm -f "$R/.fable-team/bin/ft-x.sh"; mv "$R/.fable-team/LIVE_BIN" "$T/LIVE_BIN.off"
chk --all; [ "$rc" = 0 ] && ! has "shim" && ! has "ERROR"; ck "ⓓ LIVE_BIN 없음 → shim 줄 0 · ERROR 0 · rc0" $?
mv "$T/LIVE_BIN.off" "$R/.fable-team/LIVE_BIN"
# ⓕ 집합 일치: 루트 shim 2개 지움(ft-x 이미 없음 + ft-y) → check 목록 = 시험이 따로 센 «헤더 없는 라이브 이름» · dry-run SHIM n = 라이브 키트 도구 수
rm -f "$R/.fable-team/bin/ft-y.sh"
want="$(for n in $(ls "$FT_BIN"); do head -3 "$R/.fable-team/bin/$n" 2>/dev/null | grep -qF '# ft-root-bin-shim:' || echo "PENDING shim $n"; done | sort)"
chk --all; got="$(printf '%s\n' "$out" | grep '^PENDING shim ' | sort)"
[ "$rc" = 1 ] && [ -n "$want" ] && [ "$got" = "$want" ]; ck "ⓕ check 누락 목록 == 헤더 없는 라이브 이름 집합(2)" $?
out="$(bash "$SHIM" --root "$R" --live "$FT_BIN" --ref main --dry-run 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "SHIM 3 · MOVED 0 · UNKNOWN 0"; ck "ⓕ dry-run SHIM 3 = 라이브 키트 도구 수" $?
# ⓖ 헤더 없는 루트 사본(옛 사본이 라이브 이름과 같음) → 누락과 같이 보고
mkshim; put "$R/.fable-team/bin/ft-z.sh" stale
chk --all; [ "$rc" = 1 ] && has "PENDING shim ft-z.sh" && [ "$(shim_lines)" = 1 ]; ck "ⓖ 헤더 없는 같은 이름 루트 사본 → PENDING shim" $?
# ⓗ --range 모드에서도 같은 검사(범위 밖이어도 루트 shim 은 전역 상태)
mkshim; rm -f "$R/.fable-team/bin/ft-y.sh"
G commit -q --allow-empty -m e; G update-ref refs/remotes/origin/main HEAD
H="$(G rev-parse HEAD)"; chk --range "$H^..$H" --ref "$H"; [ "$rc" = 1 ] && has "PENDING shim ft-y.sh"; ck "ⓗ --range 에서도 PENDING shim" $?
# ⓘ 오염·상한
[ "$(git -C "$R" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
