#!/usr/bin/env bash
# test_doc_exempt_index_move_r1175.sh — r1175: 문서 면제에 «ft-index-move 가 만든 진행→완성 이동» 한 꼴만 연다
# 범위: ft_doc_exempt_moves.py index_move_pair + ft_doc_exempt.py 호출 1곳(반례 R1~R8 · 변이 2 · 옛 판 빨강).
# 격리: 임시 origin(bare)+clone · 가짜 tmux(세션명) · 임시 명부 — 실 gh·실 저장소·실 원격·press 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
BIN="$HERE/../bin"; DX="$BIN/ft_doc_exempt.py"; MV="$BIN/ft_doc_exempt_moves.py"
KITBIN="$(cd "$HERE/../kit/fable-team/bin" && pwd)"; KPFX="${KITBIN#$TOP/}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
[ -f "$MV" ] || { echo "FAIL 이동 판정 모듈 없음: $MV"; exit 1; }
for f in ft_doc_exempt.py ft_doc_exempt_moves.py ft_doc_exempt_paths.py; do cmp -s "$KITBIN/$f" "$BIN/$f"; ck "ⓔ 짝 사본 cmp0(키트 ↔ harness/bin) $f" $?; done
bash -n "${BASH_SOURCE[0]:-$0}"; ck "bash -n" $?

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SEAT='byz-t-master-claude#1'; PLANNER_SEAT='byz-planner-master-claude#105'
mkrepo "$T"
printf '.fable-team/\n' >> "$W/.git/info/exclude"
mkdir -p "$W/.fable-team"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[2]},open(sys.argv[1],"w"))' "$W/.fable-team/seats-planner.json" "$PLANNER_SEAT"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[2]},open(sys.argv[1],"w"))' "$W/.fable-team/seats-t.json" "$SEAT"
mkdir -p "$T/fakebin"; printf '%s' "$SEAT" > "$T/seatname"
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat %s; exit 0; }\nexit 1\n' "$T/seatname" > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
export FT_ROOT="$W" FT_SEAT="$SEAT" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
dxw() { out="$(FT_SEAT="$SEAT" python3 "$1" --mode doc-exempt --repo "$W" --root "$W" --base "$BASEC" --head "$2" 2>&1)"; rc=$?; }
dx() { dxw "$DX" "$1"; }

TD=design/teams/t; RUN="$TD/indices/진행/X.md"; DONE="$TD/indices/완성/X.md"
OLD_CARD='# 인덱스: X — 시험 카드
- 상태: 진행
- 대상: a

## 구현 범위
1. 본문 줄

## 상태
- 2026-10-30 21:00 — 대기→진행 · 좌석 S'
DA_OK="$TD/ARCH-close-x.md#§1"
mkdir -p "$W/$TD/indices/진행" "$W/$TD/indices/대기"
printf '%s\n' "$OLD_CARD" > "$W/$RUN"; printf '%s\n' "$OLD_CARD" > "$W/$TD/indices/대기/X.md"
printf '# 닫기\n## §1 결론\n- 닫힘 — X — main %s\n## §2 기타\n- 열림\n' "$M0" > "$W/$TD/ARCH-close-x.md"
printf '# 열림\n## §1 결론\n- 보류(아직)\n## §17 다른 절\n- 닫힘\n' > "$W/$TD/ARCH-open.md"
cm "$W" "base cards"; git -C "$W" checkout -q -B c-main; BASEC="$(sha "$W" c-main)"
# done_card <DA> [변형] — ft-index-move 꼴 새 판(머리 상태 줄 교체 + 끝 기록 2줄)을 stdout 으로
done_card() { printf '%s\n' "$OLD_CARD" | sed 's/^- 상태: 진행$/- 상태: 완성 · 2026-10-30 22:00 · S/'
  printf -- '- 2026-10-30 22:00 — 진행→완성 · 좌석 S · DA %s\n- 착지: %s\n' "$1" "$M0"; }
# mkmove <가지> <src> <dst> <새 판 파일> [덧붙일 경로…] — src 삭제 + dst 에 새 판 + 경로마다 'x' 파일
mkmove() { local b="$1" src="$2" dst="$3" body="$4"; shift 4
  git -C "$W" checkout -q -B "$b" c-main; git -C "$W" rm -q "$src"; mkdir -p "$W/$(dirname "$dst")"; cp "$body" "$W/$dst"
  for p in "$@"; do mkdir -p "$W/$(dirname "$p")"; printf 'x\n' > "$W/$p"; done; cm "$W" "case $b"; HS="$(sha "$W" "$b")"; }

done_card "$DA_OK" > "$T/r1.md"
# ===== ⓐ 빨강 먼저: 옛 판(착지 전 팩 main 1ce58fcf)은 R1 도 «추가·수정 아닌 변경(D)» 으로 거절 =====
mkdir -p "$T/red"; cp -R "$BIN/." "$T/red/"
git -C "$TOP" show "1ce58fcf0b8bb25a302b03bb19a61d7cff09ad0a:$KPFX/ft_doc_exempt.py" > "$T/red/ft_doc_exempt.py" || { echo "FAIL 옛 판을 못 꺼냄"; exit 1; }
mkmove r1 "$RUN" "$DONE" "$T/r1.md"; R1SHA="$HS"
dxw "$T/red/ft_doc_exempt.py" "$R1SHA"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]]; ck "ⓐ 빨강: 옛 판 = R1 이동도 거절(${out:0:60})" $?

# ===== ① 이동 꼴 면제 · R1·R7 =====
dx "$R1SHA"
[ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $R1SHA files=2 team=t by=$SEAT index-move=1" ]; ck "ⓐ R1 ft-index-move 꼴 진행→완성 → DOC-EXEMPT index-move=1" $?
mkmove r7 "$RUN" "$DONE" "$T/r1.md" "$TD/HANDOFF-r7.md"
dx "$HS"
[ "$rc" = 0 ] && [ "$out" = "DOC-EXEMPT $HS files=3 team=t by=$SEAT index-move=1" ]; ck "ⓐ R7 R1 + 팀 직속 새 .md → 면제(남은 행도 면제)" $?
# 이 변형은 git 이 이름바꾸기(R066)로 짝지을 만큼 비슷하다 — 옛 diff 옵션(--no-renames --find-copies=0)이면 R 로 나와 거절됐다
printf '%s\n' "$OLD_CARD" > "$T/r1n.md"; printf -- '- 2026-10-30 22:00 — 진행→완성 · DA %s\n' "$DA_OK" >> "$T/r1n.md"
mkmove r1n "$RUN" "$DONE" "$T/r1n.md"; R1NSHA="$HS"
dx "$HS"
[ "$rc" = 0 ] && [[ "$out" == *"index-move=1"* ]]; ck "ⓐ R1 변형: 상태 줄 그대로 · 좌석 칸 없는 기록 1줄(ft-index-move SEAT 빈 꼴) → 면제" $?
# 끝 줄바꿈 없는 옛 판(ft-index-move 가 줄바꿈 1개를 보장한 뒤 덧붙임) — 꼴 대조가 마지막 줄을 «바뀜» 으로 보지 않는다
printf '%s' "$OLD_CARD" > "$T/nonl-old.md"; { printf '%s\n' "$OLD_CARD"; printf -- '- 2026-10-30 22:00 — 진행→완성 · 좌석 S · DA %s\n' "$DA_OK"; } > "$T/nonl-new.md"
git -C "$W" checkout -q -B nonl-base c-main; cp "$T/nonl-old.md" "$W/$RUN"; cm "$W" nonl-base; NB="$(sha "$W" nonl-base)"
git -C "$W" rm -q "$RUN"; mkdir -p "$W/$(dirname "$DONE")"; cp "$T/nonl-new.md" "$W/$DONE"; cm "$W" nonl-head
out="$(FT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$W" --root "$W" --base "$NB" --head "$(sha "$W" HEAD)" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"index-move=1"* ]]; ck "ⓐ R1 변형: 옛 판 끝 줄바꿈 없음 → 면제" $?

# ===== ② 꼴 밖 거절 · R2·R5·R6 =====
done_card "$DA_OK" | sed 's/^1\. 본문 줄$/1. 본문 줄(손 편집)/' > "$T/r2.md"
mkmove r2 "$RUN" "$DONE" "$T/r2.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"이동 꼴 아님"*"6번째 줄"* ]]; ck "ⓑ R2 가운데 줄 1개 수정 → 거절 «이동 꼴 아님»(${out:0:80})" $?
done_card "$DA_OK" | sed 's/^- 상태: 완성 · .*/- 상태: 진행(손)/' > "$T/r2b.md"
mkmove r2b "$RUN" "$DONE" "$T/r2b.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"이동 꼴 아님"* ]]; ck "ⓑ R2 변형: 머리 상태 줄을 «완성» 아닌 값으로 → 거절" $?
printf '%s\n' "$OLD_CARD" > "$T/r2c.md"; printf -- '- 착지: %s\n' "$M0" >> "$T/r2c.md"
mkmove r2c "$RUN" "$DONE" "$T/r2c.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"기록 줄 0개"* ]]; ck "ⓑ R2 변형: 덧붙은 줄에 «진행→완성 · DA» 기록 0 → 거절" $?
{ done_card "$DA_OK"; printf -- '- 2026-10-30 22:01 — 진행→완성 · DA %s\n' "$DA_OK"; } > "$T/r2d.md"
mkmove r2d "$RUN" "$DONE" "$T/r2d.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"기록 줄 2개"* ]]; ck "ⓑ R2 변형: 기록 줄 2개 → 거절" $?
done_card "$DA_OK" | sed '/^1\. 본문 줄$/d' > "$T/r2e.md"; mkmove r2e "$RUN" "$DONE" "$T/r2e.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"이동 꼴 아님"* ]]; ck "ⓑ R2 변형: 옛 줄 1개 삭제 → 거절" $?
# DA ① C1·C2 — «\r» 바이트가 있는 짝은 면제 아님(ft-index-move 는 LF 만 쓴다 · CR 정규화 0)
{ done_card "$DA_OK"; printf -- '- 2026-10-30 22:01 — 진행→완성 · DA %s\r\n' "$DA_OK"; } > "$T/c1.md"
mkmove c1 "$RUN" "$DONE" "$T/c1.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"CRLF 줄 있음"* ]]; ck "ⓑ C1 정상 기록 LF 1줄 + CRLF 기록 1줄 → 면제 아님 «CRLF 줄 있음»" $?
git -C "$W" checkout -q -B c2-base c-main; printf '%s\n' "$OLD_CARD" | sed 's/$/\r/' > "$W/$RUN"; cm "$W" c2-base; C2B="$(sha "$W" c2-base)"
git -C "$W" rm -q "$RUN"; mkdir -p "$W/$(dirname "$DONE")"; { printf '%s\n' "$OLD_CARD" | sed 's/$/\r/'; printf -- '- 2026-10-30 22:00 — 진행→완성 · DA %s\r\n' "$DA_OK"; } > "$W/$DONE"; cm "$W" c2-head
out="$(FT_SEAT="$SEAT" python3 "$DX" --mode doc-exempt --repo "$W" --root "$W" --base "$C2B" --head "$(sha "$W" HEAD)" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"CRLF 줄 있음"* ]]; ck "ⓑ C2 CRLF 카드 + CRLF 기록 1개 → 면제 아님 «CRLF 줄 있음»" $?
mkmove r5 "$RUN" "$TD/indices/완성/Y.md" "$T/r1.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]] && [[ "$out" != *"이동 꼴"* ]]; ck "ⓑ R5 진행/X 삭제 + 완성/Y 추가(이름 다름) → 짝 아님 · 지금 규칙으로 거절(${out:0:60})" $?
mkmove r6 "$TD/indices/대기/X.md" "$DONE" "$T/r1.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"추가·수정 아닌 변경(D)"*"대기/X.md"* ]]; ck "ⓑ R6 대기/X 삭제 + 완성/X 추가 → 거절(진행→완성만)" $?
mkmove r6b "$RUN" "$TD/indices/아카이브/X.md" "$T/r1.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]]; ck "ⓑ R6 변형: 진행→아카이브 → 거절" $?
git -C "$W" checkout -q -B r6c c-main; git -C "$W" rm -q "$RUN"; cm "$W" r6c; dx "$(sha "$W" r6c)"
[ "$rc" = 1 ] && [[ "$out" == *"추가·수정 아닌 변경(D)"* ]]; ck "ⓑ 진행/X 삭제만(짝 없음) → 거절" $?

# ===== ③ 판정문 재확인 · R3·R4 =====
done_card "$TD/ARCH-close-missing.md#§1" > "$T/r3.md"; mkmove r3 "$RUN" "$DONE" "$T/r3.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"판정문이 head 트리에 없음"* ]]; ck "ⓒ R3 DA 경로가 head 에 없음 → 거절" $?
done_card "$TD/ARCH-open.md#§1" > "$T/r4.md"; mkmove r4 "$RUN" "$DONE" "$T/r4.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"판정문"*"«닫힘»/«CLOSE» 없음"* ]]; ck "ⓒ R4 판정문 §1 에 «닫힘»·«CLOSE» 없음(§17 의 닫힘은 §1 아님) → 거절" $?
done_card "$TD/ARCH-close-x.md#§9" > "$T/r4b.md"; mkmove r4b "$RUN" "$DONE" "$T/r4b.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"절 «§9» 없음"* ]]; ck "ⓒ R4 변형: 판정문에 그 절 없음 → 거절" $?
done_card "$TD/ARCH-close-x.md#§1" > "$T/r3b.md"
git -C "$W" checkout -q -B r3b c-main; git -C "$W" rm -q "$RUN" "$TD/ARCH-close-x.md"; mkdir -p "$W/$(dirname "$DONE")"; cp "$T/r3b.md" "$W/$DONE"; cm "$W" r3b
dx "$(sha "$W" r3b)"
[ "$rc" = 1 ] && [[ "$out" == *"판정문이 head 트리에 없음"* ]]; ck "ⓒ R3 변형: 같은 PR 이 판정문을 지움(base 에만 있음) → 거절" $?
done_card "../outside.md#§1" > "$T/r3c.md"; mkmove r3c "$RUN" "$DONE" "$T/r3c.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"판정문 경로 모양 틀림"* ]]; ck "ⓒ R3 변형: 판정문 경로 «..» → 거절" $?

# ===== ④ 다른 파일 규칙 그대로 · R8 =====
mkmove r8 "$RUN" "$DONE" "$T/r1.md" "$TD/tool.py"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"문서(.md) 아님"* ]]; ck "ⓓ R8 R1 + .py 1개 → 거절(지금처럼)" $?
mkmove r8b "$RUN" "$DONE" "$T/r1.md" "design/teams/u/HANDOFF-u.md"; dx "$HS"
[ "$rc" = 1 ] && [[ "$out" == *"한 PR 한 팀 폴더가 아님"* ]]; ck "ⓓ R8 변형: R1 + 다른 팀 .md → 거절(한 팀)" $?

# ===== ⓕ 변이: 짝 찾기 끔 → R1 거절 · 판정문 재확인 끔 → R4 통과 (시험이 검사를 실제로 잡는다) =====
mkdir -p "$T/mut"; cp -R "$BIN/." "$T/mut/"
mutm() { python3 - "$MV" "$T/mut/ft_doc_exempt_moves.py" "$1" "$2" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  cmp -s "$MV" "$T/mut/ft_doc_exempt_moves.py" && { echo "FAIL 변이 생성 실패: $1"; fail=$((fail+1)); return 1; }; }
mutm 'if st == "D" and c and c[1] == FROM_DIR:' 'if False:'
dxw "$T/mut/ft_doc_exempt.py" "$R1SHA"
[ "$rc" = 1 ] && [[ "$out" == NOT* ]]; ck "ⓕ① 짝 찾기 끔 → R1 거절로 되돌아감(ⓐ R1 시험이 FAIL = 변이 감지)" $?
mutm 'why = why or verdict_closed(logs[0], lambda q: read_blob(head, q))' 'why = why'
dxw "$T/mut/ft_doc_exempt.py" "$(sha "$W" r4)"
[ "$rc" = 0 ]; ck "ⓕ② 판정문 재확인 끔 → R4 통과(ⓒ R4 시험이 FAIL = 변이 감지)" $?
cp "$MV" "$T/mut/ft_doc_exempt_moves.py"
python3 - "$DX" "$T/mut/ft_doc_exempt.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = '"--name-status", "-z", "--no-renames", base, head)'
assert old in s, "변이 대상 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, '"--name-status", "-z", "--no-renames", "--find-copies=0", base, head)', 1))
PY
dxw "$T/mut/ft_doc_exempt.py" "$R1NSHA"
[ "$rc" = 1 ] && [[ "$out" == *"(R0"* ]]; ck "ⓕ③ 옛 diff 옵션(--find-copies=0) 되살림 → R1 변형이 이름바꾸기(R)로 거절(변이 감지 · ${out:0:50})" $?

# ===== ⓖ 격리 =====
[ "$(git -C "$TOP" rev-parse HEAD)" = "$(git -C "$HERE" rev-parse HEAD)" ]; ck "ⓖ 격리: 실 리포 HEAD 무변경" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
