#!/usr/bin/env bash
# test_merge_land_root_shim_r1845.sh — r1845: 착지 끝(설치 대조 뒤)에 루트 shim 을 데이터 루트(BYZ)·하네스 코드 루트(팩) 순서로 1회씩
#   반례 ①~③ + 같은 루트 1회 + 변이 M1(팩 루트 호출 빼기)·M2(shim rc → 착지 rc) · 키트 cmp
#   FT_ROOT_SHIM = 가짜 shim(받은 --root 마다 라이브 이름의 연결 파일이 없을 때만 쓰고 기록) · 임시 리포 2개(데이터·팩) · 실 라이브·gh·원격 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; D="$T/data"; P="$T/pack"; mkdir -p "$T/state" "$D/.fable-team/bin" "$T/live" "$P/harness/kit/fable-team/bin" "$P/.fable-team/bin"
git init -q "$P"; git -C "$P" config user.name t; git -C "$P" config user.email t@t; echo x > "$P/harness/kit/fable-team/bin/ft-new.sh"; cm "$P" pack
echo x > "$T/live/ft-new.sh"; printf '%s\n' "$T/live" > "$D/.fable-team/LIVE_BIN"; cp "$D/.fable-team/LIVE_BIN" "$P/.fable-team/LIVE_BIN"
export FT_ROOT="$D" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/chk-stub" FT_HARNESS_ROOT="$P/harness" FT_ROOT_SHIM="$T/shim-stub" SHIM_LOG="$T/shim.log"
printf '#!/bin/bash\necho "$*" >> "$STUB_LOG"\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\nexit 0\n' > "$T/gh-stub"
printf '#!/bin/bash\necho "OK n=1 skip=0"\n' > "$T/chk-stub"
cat > "$T/shim-stub" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do case "$1" in --root) R="$2"; shift 2;; --live) L="$2"; shift 2;; *) shift;; esac; done
[ "$R" = "${SHIM_FAIL_ROOT:-}" ] && { echo "ERROR 가짜 실패"; exit 3; }
n=0; w=0; for f in "$L"/*; do b="${f##*/}"; n=$((n+1)); [ -e "$R/.fable-team/bin/$b" ] || { echo shim > "$R/.fable-team/bin/$b"; w=$((w+1)); }; done
echo "$R w=$w" >> "$SHIM_LOG"; echo "SHIM $n · MOVED 0 · UNKNOWN 0"
EOF
chmod +x "$T/gh-stub" "$T/chk-stub" "$T/shim-stub"
mkpr() {
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() { local l="$1" n="$2"; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$SHIM_LOG"; out="$(env "$@" bash "$l" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; }
reset() { rm -f "$D/.fable-team/bin/ft-new.sh" "$P/.fable-team/bin/ft-new.sh"; }
S1=$SECONDS

# ① 새 이름 · 두 루트 연결 파일 없음 → 착지 뒤 두 루트 모두 생김 · 순서 = 데이터 → 팩 · LANDED rc0
land "$LAND" 11 X=1
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=11 "* ]] && [ -f "$D/.fable-team/bin/ft-new.sh" ] && [ -f "$P/.fable-team/bin/ft-new.sh" ]; ck "① 두 루트 연결 파일 생김" $?
[ "$(grep '^SHIM-AFTER-LAND ' <<<"$out" | cut -d' ' -f2 | tr '\n' ' ')" = "$D $P " ] && grep -q "^SHIM-AFTER-LAND $P SHIM 1 · MOVED 0 · UNKNOWN 0$" <<<"$out"; ck "① SHIM-AFTER-LAND 2줄 · 데이터 → 팩 순서 · 끝줄" $?
# ② 데이터 루트 shim rc 3 → WARN 1줄 · 착지 rc 0 · LANDED 그대로 · 팩 루트는 그대로 돈다
reset; land "$LAND" 12 SHIM_FAIL_ROOT="$D"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=12 "* ]] && [ "$(grep -c '^WARN 루트 shim' <<<"$out")" = 1 ] && [ -f "$P/.fable-team/bin/ft-new.sh" ]; ck "② shim rc3 → WARN 1줄 · 착지 rc 0" $?
# ③ 재실행 → 두 루트 SHIM n · MOVED 0 · 쓰기 0(멱등)
land "$LAND" 13 X=1; land "$LAND" 14 X=1
[ "$rc" = 0 ] && [ "$(tr '\n' ' ' < "$SHIM_LOG")" = "$D w=0 $P w=0 " ] && [ "$(grep -c '^SHIM-AFTER-LAND .* MOVED 0 ' <<<"$out")" = 2 ]; ck "③ 재실행 → 두 루트 쓰기 0" $?
# 같은 루트(데이터 루트 = 팩 리포 = 대상 리포 W · r1746 다른 리포 URL 검사 밖) → 1회
mkdir -p "$W/harness/kit/fable-team" "$W/.fable-team/bin"; cp "$D/.fable-team/LIVE_BIN" "$W/.fable-team/LIVE_BIN"
land "$LAND" 15 FT_ROOT="$W" FT_HARNESS_ROOT="$W/harness"
[ "$rc" = 0 ] && [ "$(grep -c '^SHIM-AFTER-LAND ' <<<"$out")" = 1 ] && [ "$(wc -l < "$SHIM_LOG" | tr -d ' ')" = 1 ]; ck "같은 루트 → 1회" $?
S2=$SECONDS

mut() { rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 -c 'import sys;p,a,b=sys.argv[1:];s=open(p).read();n=s.count(a);open(p,"w").write(s.replace(a,b));sys.exit(0 if n==1 else 1)' "$T/m/ft-merge-land.sh" "$1" "$2"; }
mut 'RSR+=("$RPK")' ':'; mrc=$?; reset; land "$T/m/ft-merge-land.sh" 21 X=1
[ "$mrc" = 0 ] && [ "$rc" = 0 ] && [ ! -f "$P/.fable-team/bin/ft-new.sh" ]; ck "M1 팩 루트 호출 빼기 → ① 잡음" $?
mut 'src=$?;' 'src=$?; [ "$src" = 0 ] || exit "$src";'; mrc=$?; land "$T/m/ft-merge-land.sh" 22 SHIM_FAIL_ROOT="$D"
[ "$mrc" = 0 ] && [ "$rc" = 3 ]; ck "M2 shim rc → 착지 rc → ② 잡음(rc=$rc)" $?
S3=$SECONDS

cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && bash -n "$LAND"; ck "키트 사본 cmp0 · bash -n" $?
echo "단계별 초: 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
