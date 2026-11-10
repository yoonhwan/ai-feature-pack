#!/usr/bin/env bash
# test_doc_exempt_v65_roster_r810.sh — r810 «v65 문서 PR 은 명부 seats.json 으로 판정» (ft_doc_exempt.py roster_master → ft_teamset.roster_path)
# 격리: 임시 origin(bare)+clone · 가짜 tmux 스텁 · 임시 루트 — 실 명부·실 원격·실 gh·press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; DX="$BIN/ft_doc_exempt.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$W/.fable-team"
printf '.fable-team/\n' >> "$W/.git/info/exclude"   # 명부는 «대상 리포 공용 루트» — 커밋·diff 에 안 들어가게 제외
roster() { python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]} if sys.argv[1] else {},open(sys.argv[2],"w"))' "$1" "$W/.fable-team/$2"; }
V65SEAT='byz-v65-master-claude#6'; LECSEAT='byz-lecture-master-claude#3'; PLSEAT='byz-planner-master-claude#105'
roster "$PLSEAT" seats-planner.json; roster "$LECSEAT" seats-lecture.json
mkdir -p "$T/fakebin"; SEATFILE="$T/seatname"; export SEATFILE
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
export TMUX_PANE=%9 PATH="$T/fakebin:$PATH"

# mkdoc <팀> — origin/main 에서 딴 head 에 design/teams/<팀>/NOTE-<n>.md 1개만 추가 → HEAD = $H
n=0; mkdoc() { n=$((n+1)); git -C "$W" checkout -q -B "pr$n" origin/main; mkdir -p "$W/design/teams/$1"; printf 'x\n' > "$W/design/teams/$1/NOTE-$n.md"; cm "$W" "doc $n"; H="$(sha "$W" HEAD)"; }
# dx <판정기> <좌석> — 이 head 를 그 좌석이 판정
dx() { printf '%s' "$2" > "$SEATFILE"; out="$(FT_SEAT="$2" python3 "$1" --mode doc-exempt --repo "$W" --root "$W" --base "$M0" --head "$H" 2>&1)"; rc=$?; }

python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$DX"; ck "py 문법" $?

# ===== ⓐ 빨강 먼저: 옛 판(팩 73f097b3 고정 — origin/main 은 착지 뒤 새 판이 된다)은 v65 명부를 seats-v65.json 으로 찾아 판정 불가 =====
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"; PFX="$(cd "$HERE/.." && pwd)"; PFX="${PFX#$TOP/}"
mkdir -p "$T/red"; for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft_doc_exempt.py"
git -C "$TOP" show "73f097b3:$PFX/kit/fable-team/bin/ft_doc_exempt.py" > "$T/red/ft_doc_exempt.py" || { echo "FAIL 옛 판을 못 꺼냄"; exit 1; }
roster "$V65SEAT" seats.json; mkdoc v65
dx "$T/red/ft_doc_exempt.py" "$V65SEAT"
[ "$rc" = 2 ] && [[ "$out" == *"v65 명부에 _master 없음"* ]]; ck "ⓐ 빨강: v65 문서 PR · seats.json 만 있음 → 옛 판 rc2 «v65 명부에 _master 없음» (seats-v65.json 을 찾아 빈 값)" $?

# ===== 초록: 새 판 =====
dx "$DX" "$V65SEAT"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $H files=1 team=v65 by=$V65SEAT"* ]]; ck "ⓐ 초록: 같은 PR · v65 팀장 → DOC-EXEMPT team=v65 rc0" $?
mkdoc lecture; dx "$DX" "$LECSEAT"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $H files=1 team=lecture by=$LECSEAT"* ]]; ck "ⓑ 다른 팀(seats-lecture.json) 판정 그대로" $?
mkdoc planner; dx "$DX" "$PLSEAT"
[ "$rc" = 0 ] && [[ "$out" == "DOC-EXEMPT $H files=1 team=planner by=$PLSEAT"* ]]; ck "ⓒ planner 명부 판정 그대로" $?
mkdoc v65; dx "$DX" "$LECSEAT"
[ "$rc" = 2 ] && [[ "$out" == *"v65 팀 master($V65SEAT)도 planner"* ]]; ck "ⓒ2 다른 팀 팀장이 v65 폴더 PR → rc2 «v65 팀 master(<seats.json 의 값>)도 planner 도 아님»" $?

# ===== ⓓ v65 인데 seats.json 없음 / ⓔ _master 없음 → rc2 =====
mv "$W/.fable-team/seats.json" "$T/seats.bak"; mkdoc v65; dx "$DX" "$V65SEAT"
[ "$rc" = 2 ] && [[ "$out" == *"v65 명부에 _master 없음"* ]]; ck "ⓓ seats.json 없음 → rc2 (면제 0)" $?
out="$(python3 -c 'import sys;sys.path.insert(0,sys.argv[1]);import ft_doc_exempt as d;d.roster_master(sys.argv[2],"v65")' "$BIN" "$W" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [[ "$out" == *"v65 명부를 못 읽음"*"/.fable-team/seats.json"* ]] && [[ "$out" != *"seats-v65"* ]]; ck "ⓓ2 required 경로 문구 경로 = seats.json" $?
roster "" seats.json; dx "$DX" "$V65SEAT"
[ "$rc" = 2 ] && [[ "$out" == *"v65 명부에 _master 없음"* ]]; ck "ⓔ seats.json 에 _master 없음 → rc2" $?

# ===== ⓖ 변이: roster_path 호출을 옛 조립으로 되돌림 → ⓐ 초록이 깨진다 =====
roster "$V65SEAT" seats.json; mkdoc v65
mkdir -p "$T/mut"; for f in "$BIN"/*; do ln -s "$f" "$T/mut/$(basename "$f")"; done; rm -f "$T/mut/ft_doc_exempt.py"
python3 - "$DX" "$T/mut/ft_doc_exempt.py" <<'EOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
new = 'p = str(teamset.roster_path(root, team))'
assert s.count(new) == 1
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(new, 'p = os.path.join(root, ".fable-team", "seats-%s.json" % team)'))
EOF
dx "$T/mut/ft_doc_exempt.py" "$V65SEAT"
[ "$rc" = 2 ] && [[ "$out" == *"v65 명부에 _master 없음"* ]]; ck "ⓖ 변이(옛 조립 복원) → v65 판정 rc2 로 깨짐" $?
dx "$DX" "$V65SEAT"
[ "$rc" = 0 ]; ck "ⓖ 변이 뒤 정판 복귀 → rc0" $?

echo "FAIL=$fail"; [ "$fail" = 0 ]
