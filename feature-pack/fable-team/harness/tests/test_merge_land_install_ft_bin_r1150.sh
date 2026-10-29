#!/usr/bin/env bash
# test_merge_land_install_ft_bin_r1150.sh — r1150: 착지 뒤 설치 대조에 FT_BIN 을 넘긴다(없으면 착지 도구 폴더 · ft-index-move-install.sh:47 과 같은 꼴)
#   반례 R1~R3(카드 동결) + 변이 1(FT_BIN 넘김 삭제) · 키트 cmp
#   임시 origin+clone · 대조기 = 대역 스텁(ft_live_install_check.py:181 subst() 처럼 bin 행인데 FT_BIN 없으면 ERROR rc3 · 받은 FT_BIN 기록) · 실 라이브·실 gh·실 원격 0 · 자기 재호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team" "$T/other-bin"
unset FT_BIN
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/chk-stub" CHK_LOG="$T/chk.log"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
exit 0
EOF
cat > "$T/chk-stub" <<'EOF'
#!/bin/bash
# CHK_KIND=bin → 지도 «$FT_BIN» 행(FT_BIN 없으면 subst() 처럼 ERROR rc3) · home → «$HOME» 행만(FT_BIN 안 봄)
printf '%s\n' "${FT_BIN-<unset>}" > "$CHK_LOG"
if [ "${CHK_KIND:-bin}" = bin ] && [ -z "${FT_BIN:-}" ]; then echo "ERROR FT_BIN 환경변수 없음 — 라이브 도구 폴더를 모른다"; exit 3; fi
echo "OK n=1 skip=0"
EOF
chmod +x "$T/gh-stub" "$T/chk-stub"
mkpr() {  # mkpr <번호> — origin/main 위 PR head 를 refs/pull/N/head 에 올리고 스텁 JSON
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() {  # land <land.sh> <번호> [KEY=VAL…] — env -u FT_BIN 위에 KEY=VAL 을 얹어 착지
  local l="$1" n="$2"; shift 2; mkpr "$n"; apv --approve-sha "$PRSHA"; : > "$CHK_LOG"
  out="$(env -u FT_BIN "$@" bash "$l" "$n" --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
}
got() { head -n1 "$CHK_LOG" 2>/dev/null; }
rp() { (cd "$1" 2>/dev/null && pwd -P); }
S1=$SECONDS

# R1 env 에 FT_BIN 없음 · bin 행 → «INSTALL OK» · «FT_BIN 환경변수 없음» 0 · 대조기가 받은 FT_BIN = 착지 도구 폴더
land "$LAND" 11 CHK_KIND=bin
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=11 "* ]] && [[ "$out" == *"INSTALL OK n=1 skip=0"* ]] && [[ "$out" != *"FT_BIN 환경변수 없음"* ]]; ck "R1 FT_BIN 없음 → INSTALL OK · ERROR 0" $?
g="$(got)"; [ -n "$g" ] && [ "$g" != "<unset>" ] && [ "$(rp "$g")" = "$BIN" ]; ck "R1 대조기가 받은 FT_BIN = 착지 도구 폴더(받은 값 $g)" $?

# R2 env 에 FT_BIN=<다른 폴더> → 그 값 우선(지금처럼)
land "$LAND" 12 CHK_KIND=bin FT_BIN="$T/other-bin"
[ "$rc" = 0 ] && [[ "$out" == *"INSTALL OK n=1 skip=0"* ]] && [ "$(got)" = "$T/other-bin" ]; ck "R2 FT_BIN 주입값 우선 → 받은 값 = $T/other-bin" $?

# R3 «$HOME» 행만(홈 훅) → 지금처럼 OK · 바뀐 것 0
land "$LAND" 13 CHK_KIND=home; Q13="$(sha "$ORIGIN" refs/heads/main)"
[ "$rc" = 0 ] && [[ "$out" == *"INSTALL OK n=1 skip=0"* ]] && [[ "$out" != *"INSTALL ERROR"* ]] && [ -z "$(find "$T" -path "*install-pending/$Q13.txt" 2>/dev/null)" ]; ck "R3 홈 훅 범위 → INSTALL OK · 이 착지 대기 기록 0" $?
S2=$SECONDS

# 변이 — 사본 bin 에서 FT_BIN 넘김을 지우고 R1 을 다시: «FT_BIN 환경변수 없음» 이 나오면(= 반례가 잡음) PASS
rm -rf "$T/m"; cp -R "$BIN" "$T/m"
python3 -c 'import sys;p=sys.argv[1];s=open(p).read();k="FT_BIN=\"${FT_BIN:-$HERE}\" ";n=s.count(k);open(p,"w").write(s.replace(k,""));sys.exit(0 if n==1 else 1)' "$T/m/ft-merge-land.sh"; mrc=$?
land "$T/m/ft-merge-land.sh" 21 CHK_KIND=bin
[ "$mrc" = 0 ] && [ "$rc" = 0 ] && [[ "$out" == *"INSTALL ERROR FT_BIN 환경변수 없음"* ]] && [ "$(got)" = "<unset>" ]; ck "변이1 FT_BIN 넘김 삭제 → R1 ERROR(반례가 잡음)" $?
S3=$SECONDS

# 키트 사본 · 문법
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && bash -n "$LAND"; ck "키트 사본 cmp0 · bash -n" $?

echo "단계별 초: 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
