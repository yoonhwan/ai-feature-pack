#!/usr/bin/env bash
# test_merge_base_head_target_r1687.sh — r1687: 기준 헤드가 «대상 가지마다» 따로다(main = 지금 그대로 · 그 밖 = base-head@<가지를 - 로>).
#   ⓐ main 착지 = 옛 경로·옛 동작(조상 검사 + 착지 뒤 전진 · 가지 파일 안 만든다)
#   ⓑ ops 착지 = base-head(main)가 후보의 조상이 아니어도 ALLOW · 착지 뒤 base-head@ops-main-base 생김 · base-head(main) 바이트 불변
#   ⓒ ops 기준 헤드가 후보의 조상 아님 → DENY(같은 문구) · main 착지는 그 파일을 보지 않는다
#   ⓓ 다른 리포 접미(r648)와 가지 접미가 함께 붙는다(경로 1개로 결정) ⓔ 대상 파일 손상(빈 값·2줄·40hex 아님) = 지금 문구로 DENY
#   변이 M1 대상 접미 삭제 → ⓑ ALLOW 가 DENY 로 · M2 착지 뒤 전진을 base-head(main)에 씀 → ⓑ main 바이트 불변 FAIL · M3 게이트 기본 경로 옛것
# 임시 bare 원격(main·ops/main-base 두 가지 · 서로 조상 아님) · 가짜 gh · 실 원격 push 0 · 실 state 0 · sleep 0
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../../harness/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"
export STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_GH="$T/gh" FT_GH_WRITE="$T/gh" FT_INSTALL_CHECK="$T/ick"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\n' > "$T/gh"
printf '#!/bin/bash\nexit 0\n' > "$T/ick"; chmod +x "$T/gh" "$T/ick"
git -C "$W" checkout -q -b ops/main-base; echo ops > "$W/ops.txt"; cm "$W" "ops work"; OPS="$(sha "$W" HEAD)"
git -C "$W" push -q origin ops/main-base; git -C "$W" checkout -q main; echo m2 > "$W/m2.txt"; cm "$W" "main work"
git -C "$W" push -q origin main; git -C "$W" fetch -q origin
ST="$T/.fable-team/state"; mkdir -p "$ST"; export FT_AUTONOMY_STATE_DIR="$ST"; BH="$ST/base-head"; OPSBH="$BH@ops-main-base"
inst() {  # inst <루트> — 병합 도구 묶음 사본 + 무동작 스텁(변이는 이 사본만 고친다)
  local b="$1/.fable-team/bin" f; mkdir -p "$b"
  for f in ft-merge-land.sh ft-merge-lib.sh ft-evidence-lib.sh ft-heavy-slot-lib.sh ft-merge-gate.sh ft_merge_lines.py ft-autonomy.sh ft-autonomy-level.sh ft-autonomy-oppa.sh ft-autonomy-scope.sh ft-autonomy-standing.sh ft-autonomy-standing-d2.sh ft-goal-table.sh ft-team-lib.sh ft-harness-root.sh ft-merge-deny.sh ft-merge-deny.txt ft-press-evidence.sh press_evidence_land.py press_evidence_verify.py press_evidence_parts.py; do cp "$BIN/$f" "$b/$f"; done
  for f in ft-autonomy-start.sh ft-head-lag.sh; do printf '#!/bin/bash\nexit 0\n' > "$b/$f"; done
  chmod +x "$b"/*.sh; echo "$b"
}
XB="$(inst "$T/i")"
land() { out="$(cd "$T" && FT_ROOT="$T" bash "$XB/ft-merge-land.sh" "$@" --repo "$W" 2>&1)"; rc=$?; }   # cwd = git 밖(교차 리포 판정 회피 · 픽스처 원격은 로컬 경로)
gate() { out="$(cd "$T" && FT_ROOT="$T" bash "${GB:-$XB/ft-merge-gate.sh}" "$@" --repo "$W" 2>&1)"; rc=$?; }
apv() { FT_ROOT="$T" bash "$XB/ft-autonomy.sh" approve-merge "$1" >/dev/null 2>&1; }
mkpr() {  # mkpr <번호> <브랜치> <시작점> <base> → PRSHA · STUB_JSON
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":sys.argv[3]}))' "$PRSHA" "$1" "$4" > "$STUB_JSON"
}
otip() { git -C "$ORIGIN" rev-parse "refs/heads/$1"; }
FT_ROOT="$T" bash "$XB/ft-autonomy.sh" on >/dev/null 2>&1

printf '%s\n' "$M0" > "$BH"   # main 기준 헤드 = M0(조상 검사 통과해야 하는 값)
git -C "$W" checkout -q main; mkpr 31 pr31 origin/main main; apv "$PRSHA"; Q31="$PRSHA"
land 31 --approve-sha "$Q31"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(cat "$BH")" = "$(otip main)" ]; ck "ⓐ main 착지 = 옛 경로 그대로(LANDED · base-head 전진)" $?
[ ! -e "$OPSBH" ]; ck "ⓐ main 착지는 가지 파일을 만들지 않는다" $?

MAINB="$(otip main)"; printf '%s\n' "$MAINB" > "$BH"   # main 기준 헤드 = main 꼭대기 = ops 후보의 조상 아님(실사건 재현)
mkpr 32 pr32 origin/ops/main-base ops/main-base; apv "$PRSHA"; P32="$PRSHA"
land 32 --approve-sha "$P32" --target ops/main-base
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(cat "$OPSBH" 2>/dev/null)" = "$(otip ops/main-base)" ] && [ "$(cat "$BH")" = "$MAINB" ]; ck "ⓑ ops 착지 = ALLOW · @ops-main-base 생김 · main 파일 불변" $?
git -C "$W" fetch -q origin

printf '%s\n' "$MAINB" > "$OPSBH"   # ops 기준 헤드가 다음 ops 후보의 조상이 아니다
mkpr 33 pr33 origin/ops/main-base ops/main-base; apv "$PRSHA"
land 33 --approve-sha "$PRSHA" --target ops/main-base
[ "$rc" != 0 ] && grep -q '조상이 아님' <<<"$out"; ck "ⓒ ops 기준 헤드가 조상 아님 → DENY(같은 문구)" $?
mkpr 34 pr34 origin/main main; apv "$PRSHA"
land 34 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓒ main 착지는 @ops 파일을 보지 않는다(LANDED)" $?

git init -q "$T/cross"; git -C "$T/cross" remote add origin git@github.com:o/n.git; git init -q "$T/elsewhere"
out="$( cd "$T/elsewhere" && . "$BIN/ft-merge-lib.sh" && fm_land_ctx "$T/cross" origin "$T/rt" ops/main-base )"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s' "$out" | cut -d'|' -f4)" = "$T/rt/.fable-team/state/base-head-o-n@ops-main-base" ]; ck "ⓓ 다른 리포 접미(-o-n) + 가지 접미(@ops-main-base) 한 경로" $?

mkpr 35 pr35 origin/ops/main-base ops/main-base; apv "$PRSHA"; P35="$PRSHA"
for bad in '' 'deadbeef
deadbeef' 'zzzzzzzz'; do   # ⓔ 손상 3종 — 대상 파일(@ops-main-base)마다
  printf '%s\n' "$bad" > "$OPSBH"
  gate "$P35" --target ops/main-base
  [ "$rc" != 0 ] && grep -q '기준 헤드 파일 손상' <<<"$out"; ck "ⓔ 대상 파일 손상 DENY(«${bad:0:8}»)" $?
done

rm -f "$OPSBH"; printf '%s\n' "$MAINB" > "$BH"   # 가지 파일 없음 = 그 검사만 생략 → 옛 코드라면 main 파일에 막힌다
gate "$P35" --target ops/main-base
[ "$rc" = 0 ] && [[ "$out" == ALLOW* ]]; ck "ⓑ 가지 파일 없음 = 조상 검사 생략(ALLOW)" $?
XB2="$(inst "$T/m1")"; python3 - "$XB2/ft-merge-lib.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('[ "${2:-main}" = main ] && { printf \'%s\\n\' "$1"; return 0; }', 'true && { printf \'%s\\n\' "$1"; return 0; }')
p.write_text(s)
PY
GB="$XB2/ft-merge-gate.sh" gate "$P35" --target ops/main-base   # M1: 접미 삭제 → main 파일에 막힘
[ "$rc" != 0 ] && grep -q '조상이 아님' <<<"$out"; ck "M1 대상 접미 삭제 → ⓑ 가 DENY 로(변이 잡힘)" $?
XB3="$(inst "$T/m3")"; python3 - "$XB3/ft-merge-gate.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'BHF="$(fm_base_head_file "${FT_ROOT:-$(dirname "$COMMON")}/.fable-team/state/base-head" "$TARGET")"'
assert s.count(old) == 1
p.write_text(s.replace(old, 'BHF="${FT_ROOT:-$(dirname "$COMMON")}/.fable-team/state/base-head"'))
PY
GB="$XB3/ft-merge-gate.sh" gate "$P35" --target ops/main-base   # M3: 기본 BHF 가 옛 경로
[ "$rc" != 0 ] && grep -q '조상이 아님' <<<"$out"; ck "M3 게이트 기본 경로가 옛것 → ALLOW 가 DENY 로(변이 잡힘)" $?
GB=""
XB4="$(inst "$T/m2")"; python3 - "$XB4/ft-merge-land.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = 'OLD="$(head -n1 "$BH" 2>/dev/null | tr -d \'[:space:]\')"'
assert s.count(old) == 1
p.write_text(s.replace(old, 'BH="${BH%@*}"; ' + old))
PY
printf '%s\n' "$M0" > "$BH"   # main 파일 값이 ops 후보의 조상 = 전진 조건이 실제로 성립하는 회차(M2 검출용)
apv "$P35"; MAINB4="$(cat "$BH")"
out="$(cd "$T" && FT_ROOT="$T" bash "$XB4/ft-merge-land.sh" 35 --approve-sha "$P35" --repo "$W" --target ops/main-base 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$BH")" != "$MAINB4" ]; ck "M2 전진을 main 파일에 씀 → main 바이트가 바뀐다(변이 잡힘)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
