#!/usr/bin/env bash
# test_doc_exempt_waiting_card_r804.sh — r804: 문서 면제에 «팀 indices/대기/<이름>.md 새 카드 추가(A)» 한 꼴만 연다
# 범위: ft_doc_exempt_paths.py team_of 한 갈래(진행/·완성/·수정·삭제·더 깊은 경로는 그대로 거절) + 판정기 통합 1건.
# 격리: 임시 origin(bare)+clone · 가짜 tmux(세션명) · 임시 명부 — 실 gh·실 저장소·실 원격·press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; DX="$BIN/ft_doc_exempt.py"; PM="$BIN/ft_doc_exempt_paths.py"
KITBIN="$(cd "$HERE/../kit/fable-team/bin" && pwd)"; KPFX="${KITBIN#$TOP/}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
[ -f "$PM" ] || { echo "FAIL 경로 판정 모듈 없음: $PM"; exit 1; }
cmp -s "$KITBIN/ft_doc_exempt_paths.py" "$PM"; ck "짝 사본 cmp0(키트 ↔ harness/bin)" $?
cmp -s "$KITBIN/ft_doc_exempt.py" "$BIN/ft_doc_exempt.py"; ck "짝 사본 cmp0(판정기)" $?
bash -n "${BASH_SOURCE[0]:-$0}"; ck "bash -n" $?
python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$PM"; ck "py 문법" $?

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# 모듈 직접 판정 — py <모듈폴더> <경로> [상태] → "OK <팀>" | "REJECT <사유>"
py() { python3 - "$1" "$2" "${3:-A}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_doc_exempt_paths as m
team, why = m.team_of(sys.argv[2], sys.argv[3])
print(("REJECT " + why) if why else ("OK " + team))
PY
}
rej() { local n="$1" p="$2" st="${3:-A}"; out="$(py "$BIN" "$p" "$st")"; [[ "$out" == REJECT* ]]; ck "$n → 거절(${out:0:64})" $?; }
acc() { local n="$1" p="$2" st="${3:-A}"; out="$(py "$BIN" "$p" "$st")"; [ "$out" = "OK lecture" ]; ck "$n → 통과(team=lecture)" $?; }
st() { local n="$1" p="$2" want="$3" stt="${4:-A}"; out="$(py "$BIN" "$p" "$stt")"; [ "$out" = "$want" ]; ck "$n → $want" $?; }

# ===== ⓐ 빨강 먼저: 옛 판(착지 전 main 73f097b3)은 대기/ 새 카드도 «제외 폴더» 로 거절한다 =====
mkdir -p "$T/red"
OLD_BASE=73f097b396eecfe23a916082a69152176fb19911   # r804 착지 전 main — 착지 뒤 origin/main 은 새 판이라 고정
git -C "$TOP" show "$OLD_BASE:$KPFX/ft_doc_exempt_paths.py" > "$T/red/ft_doc_exempt_paths.py" || { echo "FAIL 옛 판을 못 꺼냄"; exit 1; }
[ -s "$T/red/ft_doc_exempt_paths.py" ] || { echo "FAIL 옛 판이 비었다"; exit 1; }
CARDPATH='design/teams/lecture/indices/대기/L51-x.md'
out="$(py "$T/red" "$CARDPATH")"
[[ "$out" == REJECT*제외\ 폴더* ]]; ck "ⓐ 빨강: 옛 판 = 대기/ 새 카드도 거절(${out:0:60})" $?
# ===== ⓑ 초록: 새 판은 («lecture», "") =====
st "ⓑ 대기/ 새 카드(A)" "$CARDPATH" "OK lecture"
# ===== ⓒ 면제 0 그대로 — 여는 문은 «대기/ 새 카드 추가(A)» 한 꼴뿐 =====
rej "ⓒ 대기/ 카드 «수정(M)»" "$CARDPATH" M
rej "ⓒ 대기/ 카드 «삭제(D)»" "$CARDPATH" D
rej "ⓒ 대기/ 카드 «이름바꾸기(R)»" "$CARDPATH" R
rej "ⓒ 진행/ 새 카드" "design/teams/lecture/indices/진행/L51-y.md"
rej "ⓒ 완성/ 새 카드" "design/teams/lecture/indices/완성/L51-y.md"
rej "ⓒ 대기/ 더 깊은 경로" "design/teams/lecture/indices/대기/sub/x.md"
rej "ⓒ indices 직속(상태 폴더 없음)" "design/teams/lecture/indices/x.md"
rej "ⓒ indices/inbox" "design/teams/lecture/indices/inbox/arch/x.md"
rej "ⓒ keys" "design/teams/lecture/keys/x.md"
rej "ⓒ baselines" "design/teams/lecture/baselines/F.md"
rej "ⓒ 대기/ .md 아님" "design/teams/lecture/indices/대기/L51.txt"
rej "ⓒ 대기/ 이름 예외 DECISION-x.md" "design/teams/lecture/indices/대기/DECISION-x.md"
rej "ⓒ 대기/ 이름 예외 BTS.md" "design/teams/lecture/indices/대기/BTS.md"
rej "ⓒ 대기/ 이름 예외 README.md" "design/teams/lecture/indices/대기/README.md"
rej "ⓒ 대기/ 정본 이름 GOAL-lecture.md" "design/teams/lecture/indices/대기/GOAL-lecture.md"
rej "ⓒ 대기/ LEDGER 접두" "design/teams/lecture/indices/대기/LEDGER-run.md"
rej "ⓒ 상태 폴더 이름 변형(대 기 · 공백)" "design/teams/lecture/indices/대 기/L51-x.md"
rej "ⓒ 상태 폴더 이름 변형(대기 + 공백)" "design/teams/lecture/indices/대기 /L51-x.md"
rej "ⓒ 상태 폴더 영어(waiting)" "design/teams/lecture/indices/waiting/L51-x.md"
rej "ⓒ 대기/ 점 파일" "design/teams/lecture/indices/대기/.hidden.md"
rej "ⓒ 팀 폴더 밖" "design/teams/L51-x.md"
rej "ⓒ 팀 이름 대문자" "design/teams/Lecture/indices/대기/L51-x.md"
# 대기/ 를 «지나가는» 다른 indices 변경이 새지 않는다 — 조각 개수 3 고정 + 상태 폴더 이름 key 비교
rej "ⓒ indices/대기 이중" "design/teams/lecture/indices/대기/대기/L51-x.md"
rej "ⓒ 대기/x.md/더" "design/teams/lecture/indices/대기/x.md/y.md"
# 대조: 직속 .md 추가(A)는 이 카드 이전과 같이 통과(회귀 0)
acc "ⓒ 대조 직속 .md(A)" "design/teams/lecture/HANDOFF-x.md"
acc "ⓒ 대조 하위 폴더 .md(A)" "design/teams/lecture/evidence/NOTE-x.md"

# ===== ⓓ 판정기 통합: ft_doc_exempt.py --mode doc-exempt =====
SEAT='byz-lecture-master-claude#1'; PLANNER_SEAT='byz-planner-master-claude#105'
mkrepo "$T"
printf '.fable-team/\n' >> "$W/.git/info/exclude"
mkdir -p "$W/.fable-team"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[2]},open(sys.argv[1],"w"))' "$W/.fable-team/seats-planner.json" "$PLANNER_SEAT"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[2]},open(sys.argv[1],"w"))' "$W/.fable-team/seats-lecture.json" "$SEAT"
mkdir -p "$T/fakebin"; printf '%s' "$SEAT" > "$T/seatname"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat %s; exit 0; }\nexit 1\n' "$T/seatname" > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
export FT_ROOT="$W" FT_SEAT="$SEAT" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
dx() { out="$(FT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$W" --root "$W" --base "$BASEC" --head "$1" 2>&1)"; rc=$?; }
git -C "$W" checkout -q -B c-main origin/main; BASEC="$(sha "$W" c-main)"
mkb() { git -C "$W" checkout -q -B "$1" c-main; shift; for p in "$@"; do mkdir -p "$W/$(dirname "$p")"; printf 'x\n' > "$W/$p"; done; cm "$W" "case $1"; }
mkb d-ok "$CARDPATH" "design/teams/lecture/HANDOFF-d1.md"
HS="$(sha "$W" d-ok)"; dx "$HS"
[ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $HS files=2 team=lecture by=$SEAT" ]; ck "ⓓ① 대기/ 새 카드 + 팀 일반 .md 한 PR → DOC-EXEMPT" $?
mkb d-mix "$CARDPATH" "design/teams/lecture/indices/진행/L51-y.md"
dx "$(sha "$W" d-mix)"
[ "$rc" != 0 ] && [[ "$out" == NOT* ]]; ck "ⓓ② 대기/ 카드 + 진행/ 카드 섞임 → 거절(${out:0:52})" $?
mkb d-two "design/teams/lecture/indices/대기/L51-a.md" "design/teams/lecture/indices/대기/L51-b.md"
dx "$(sha "$W" d-two)"
[ "$rc" = 0 ] && [[ "$out" == *"files=2 team=lecture"* ]]; ck "ⓓ③ 대기/ 카드 2장 한 PR → 통과(files=2)" $?
dx "$BASEC"
[ "$rc" != 0 ] && [[ "$out" == *"바뀐 경로 0"* ]]; ck "ⓓ④(대조) 빈 diff → 거절" $?

# ===== ⓕ 변이: 여는 문을 지우면 ⓑ·ⓒ 가 무너진다(시험이 검사를 실제로 잡는다) =====
mkdir -p "$T/mut"; cp "$DX" "$T/mut/ft_doc_exempt.py"; cp "$PM" "$T/mut/ft_doc_exempt_paths.py"
# mutp <old> <new> [<old> <new> …] — 여러 자리를 한 번에 지우는 변이(«규칙 한 가지 삭제» 를 재현)
mutp() { python3 - "$PM" "$T/mut/ft_doc_exempt_paths.py" "$@" <<'PY'
import sys
src, dst, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(src, encoding="utf-8").read()
for old, new in zip(rest[::2], rest[1::2]):
    assert old in s, "변이 대상 없음: " + old
    s = s.replace(old, new, 1)
open(dst, "w", encoding="utf-8").write(s)
PY
  cmp -s "$PM" "$T/mut/ft_doc_exempt_paths.py" && { echo "FAIL 변이 생성 실패(대상 문장이 없다): $*"; fail=$((fail+1)); return 1; }
}
unmutp() { cp "$PM" "$T/mut/ft_doc_exempt_paths.py"; }
mutp 'why = "" if waiting_card(segs, status) else excluded_dir(segs[:-1])' 'why = excluded_dir(segs[:-1])'
out="$(py "$T/mut" "$CARDPATH")"; [[ "$out" == REJECT* ]]; ck "ⓕ① 대기/ 허용 삭제 → ⓑ 반례가 거절로 되돌아간다(변이 감지)" $?
unmutp
mutp 'return (status == "A" and len(segs) == 3' 'return (len(segs) == 3' 'if len(segs) > 1 and status != "A":' 'if False:'
out="$(py "$T/mut" "$CARDPATH" M)"; [[ "$out" == OK* ]]; ck "ⓕ② «추가(A)만» 두 곳 삭제 → ⓒ 수정(M) 반례가 통과(변이 감지)" $?
unmutp
mutp 'and len(segs) == 3' 'and len(segs) >= 3' 'and segs[2].endswith(".md")' 'and segs[-1].endswith(".md")'
out="$(py "$T/mut" "design/teams/lecture/indices/대기/sub/L51-z.md")"; [[ "$out" == OK* ]]; ck "ⓕ③ 깊이(조각 3 고정·위치) 삭제 → ⓒ sub 반례가 통과(변이 감지)" $?
unmutp
mutp 'and key(segs[1]) == key(WAITING)' 'and segs[1] == WAITING'
out="$(py "$T/mut" "design/teams/lecture/indices/waiting/L51-x.md")"; [[ "$out" == REJECT* ]]; ck "ⓕ④ key() 비교를 «그대로 비교» 로 바꿔도 waiting 은 여전히 거절(대조)" $?
unmutp
cmp -s "$PM" "$T/mut/ft_doc_exempt_paths.py"; ck "ⓕ 변이 사본 원복" $?

# ===== ⓖ 격리 =====
[ "$(git -C "$TOP" rev-parse HEAD)" = "$(git -C "$HERE" rev-parse HEAD)" ]; ck "ⓖ 격리: 실 리포 HEAD 무변경" $?
! command -v gh >/dev/null 2>&1 || [ -z "${FT_GH_WRITE:-}" ]; ck "ⓖ 격리: 실 gh 호출 경로 0" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
