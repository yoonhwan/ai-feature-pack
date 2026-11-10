#!/usr/bin/env bash
# test_queue_reask_r529.sh — 오빠 큐 줄 칸 셋(번호·팀·보여준 시각) + ft-queue.sh shown|due|take|remind + 틱 queue_watch
#   ⓐ proxy-decide 새 줄 번호 q<N>·팀·보여준 시각 - (옛 7칸 머리 = 머리만 10칸 · 옛 줄 바이트 0 변경) ⓑ shown = 그 줄 한 칸만
#   ⓒ due = 대기 ∧ (보여준 시각 ≤ 지금−60분 ∨ -) · 보류 재확인 지남 = «재확인» ⓓ remind = 그 팀 _master 에 [재질문] 1통 · 60분 안 반복 0
#   ⓔ 자율 ON = 쪽지 0 · 아침 묶음 줄만 ⓕ take = 진행 — <master> · 사유 끝 오빠 값 · RESUME 1줄 ⓖ 팀 - 줄 = planner _master ⓗ 틱 호출 1줄
# 격리: 임시 큐·FT_ROOT·상태·가짜 mbox(받은 argv 기록) · 시각 FT_NOW — 실 큐·실 mbox 쓰기 0 · 외부 호출 0 · GIT_* 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; MIR="$HERE/../../harness/kit/fable-team/bin"
FQ="$BIN/ft-queue.sh"; QS="$BIN/ft_queue_state.py"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

for f in ft-queue.sh ft_queue.py ft_queue_remind.py ft-proxy-decide.sh ft-tick.sh; do cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp 0: $f" $?; done
[ -f "$FQ" ]; ck "도구 파일 실재: ft-queue.sh" $?
bash -n "$FQ" 2>/dev/null; ck "bash -n ft-queue.sh" $?
for f in ft-queue.sh ft_queue.py ft_queue_remind.py; do [ "$(wc -l < "$BIN/$f" 2>/dev/null || echo 999)" -le 200 ]; ck "$f ≤ 200줄" $?; done
python3 -m py_compile "$BIN/ft_queue.py" "$BIN/ft_queue_remind.py" 2>/dev/null; ck "py_compile ft_queue.py · ft_queue_remind.py" $?

S="$T/state"; P="$T/planner"; R="$T/rosters"; mkdir -p "$S" "$P" "$R"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$P" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
Q="$P/AUTONOMY-QUEUE.md"
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$P/VERDICTS-planner-1.md"
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" = on ]; ck "준비: 자율 ON" $?
PD() { out="$("$BASH" "$BIN/ft-proxy-decide.sh" --kind card-start --verdict 100 --choice c --why w --undo u "$@" 2>&1)"; rc=$?; }
cell() { python3 "$QS" parse "$Q" | python3 -c 'import json,sys;r=[x for x in json.load(sys.stdin) if x["cells"].get("질문")==sys.argv[1]];print(r[0]["cells"].get(sys.argv[2],"-") if r else "NOROW")' "$1" "$2"; }

# ===== ⓐ 새 줄 칸 셋 =====
PD --card "$T/design/teams/graphics/indices/대기/g1.md" --q q-a1
[ "$rc" = 2 ]; ck "ⓐ 준비: QUEUE rc2" $?
head="$(grep -m1 '^| 자율' "$Q")"; echo "  ⓐ 원문: $head"; echo "  ⓐ 원문: $(grep '| q-a1 |' "$Q")"
[ "$head" = '| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 상태 | 번호 | 팀 | 보여준 시각 |' ]; ck "ⓐ 새 파일 머리 10칸 · 상태 뒤 번호·팀·보여준 시각" $?
[ "$(cell q-a1 번호)|$(cell q-a1 팀)|$(cell q-a1 '보여준 시각')|$(cell q-a1 상태)" = 'q1|graphics|-|대기' ]; ck "ⓐ 첫 줄 = q1 · 팀(카드 경로) graphics · 보여준 시각 - · 대기" $?
PD --card "$T/none.md" --q q-a2 --team room
[ "$(cell q-a2 번호)|$(cell q-a2 팀)" = 'q2|room' ]; ck "ⓐ 둘째 줄 = q2(최대+1) · --team room" $?
PD --card "$T/none.md" --q q-a3
[ "$(cell q-a3 번호)|$(cell q-a3 팀)" = 'q3|-' ]; ck "ⓐ --team·팀 카드 둘 다 없음 → 팀 -" $?
python3 "$QS" lint "$Q" >/dev/null; ck "ⓐ 도구가 쓴 큐 = 상태 린트 OK" $?
# 옛 7칸 머리 큐 → 머리·구분 행만 10칸 · 옛 줄 바이트 그대로 · 번호 = 옛 줄 무시 최대+1
printf '# AUTONOMY-QUEUE\n\n| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 처리됨 |\n|---|---|---|---|---|---|---|\n| A9 | 2026-10-20 09:00 | x | 옛질문 | 추 | 사 | 대기 |\n| A9 | 2026-10-20 09:01 | x | 옛2 | 추 | 사 | |\n' > "$Q"
old="$(sed -n '5,6p' "$Q")"
PD --card "$T/none.md" --q q-a4 --team graphics
[ "$(sed -n '5,6p' "$Q")" = "$old" ] && [ "$(sed -n 3p "$Q")" = '| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 처리됨 | 번호 | 팀 | 보여준 시각 |' ] && [ "$(sed -n 4p "$Q")" = '|---|---|---|---|---|---|---|---|---|---|' ]
ck "ⓐ 옛 머리(처리됨) → 머리·구분 행만 10칸 · 옛 줄 2개 바이트 0 변경" $?
[ "$(cell q-a4 번호)" = q1 ] && [ "$(cell 옛질문 번호)|$(cell 옛질문 '보여준 시각')" = '-|-' ]; ck "ⓐ 옛 줄 번호·보여준 시각 = - 로 읽음 · 새 줄 q1" $?

# ===== 고정 큐(ⓑ~ⓖ) =====
mkfix() { { printf '# AUTONOMY-QUEUE\n\n| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 상태 | 번호 | 팀 | 보여준 시각 |\n|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | graphics 다음 일감을 무엇으로 할지 오빠 선택이 필요합니다 — 후보 셋 중 하나를 고르는 질문입니다 | 추 | 사 | 대기 | q1 | graphics | 2026-10-20 08:48 |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | g 최근 | 추 | 사 | 대기 | q2 | graphics | 2026-10-20 09:30 |\n'
  printf '| A9 | 2026-10-20 08:00 | press-order | g 안보임 | 추 | 사 | 대기 | q3 | graphics | - |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | room 것 | 추 | 사 | 대기 | q4 | room | - |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | g 보류지남 | 추 | 사 | 보류 — 출장 · 재확인 2026-10-20 09:00 | q5 | graphics | 2026-10-20 07:00 |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | g 보류아직 | 추 | 사 | 보류 — 출장 · 재확인 2026-10-21 09:00 | q6 | graphics | 2026-10-20 07:00 |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | g 진행중 | 추 | 사 | 진행 — m | q7 | graphics | 2026-10-20 07:00 |\n'
  printf '| A9 | 2026-10-20 08:00 | card-start | 팀없음 | 추 | 사 | 대기 | q8 | - | 2026-10-20 08:00 |\n'
  printf '| A9 | 2026-10-20 08:00 | x | 옛줄 | 추 | 사 | 대기 |\n'; } > "$Q"; }
NOWV='2026-10-20 10:00'   # FT_NOW 는 ft-queue 호출에만(export 하면 ft-autonomy 도 그 시각으로 켜 실제 시계로 바로 만료)
FQr() { out="$(FT_NOW="$NOWV" "$BASH" "$FQ" "$@" 2>&1)"; rc=$?; }

# ===== ⓑ shown =====
mkfix; cp "$Q" "$T/before.md"
FQr shown q3 --at '2026-10-20 09:10'
[ "$rc" = 0 ] && [ "$(cell 'g 안보임' '보여준 시각')" = '2026-10-20 09:10' ]; ck "ⓑ shown q3 --at → 그 칸만 바뀜" $?
[ "$(diff "$T/before.md" "$Q" | grep -c '^[<>]')" = 2 ]; ck "ⓑ diff = 그 줄 1개(다른 줄 바이트 0 변경)" $?
FQr shown q99; [ "$rc" != 0 ] && grep -q '^ERROR' <<<"$out"; ck "ⓑ 없는 번호 → ERROR rc≠0(조용한 통과 0)" $?
FQr shown q2; [ "$rc" = 0 ] && [ "$(cell 'g 최근' '보여준 시각')" = '2026-10-20 10:00' ]; ck "ⓑ --at 없음 = 지금(FT_NOW)" $?

# ===== ⓒ due =====
mkfix
FQr due --team graphics --min 60; echo "  ⓒ 원문:"; sed 's/^/    /' <<<"$out"
ids="$(grep '^DUE' <<<"$out" | awk '{print $2}' | tr '\n' ' ')"
[ "$rc" = 0 ] && [ "$ids" = 'q1 q3 q5 ' ]; ck "ⓒ graphics due = q1(72분)·q3(안 보임)·q5(보류 재확인 지남) — q2 최근·q4 남의 팀·q6 재확인 전·q7 진행·옛 줄 제외" $?
grep '^DUE q1 ' <<<"$out" | grep -q 'age=72 tag=재질문' && grep '^DUE q3 ' <<<"$out" | grep -q 'shown=- age=- tag=재질문' && grep '^DUE q5 ' <<<"$out" | grep -q 'tag=재확인'
ck "ⓒ 줄 꼴 age·tag(재질문|재확인)" $?
grep -q '^QUEUE-DUE n=3 old=1' <<<"$out"; ck "ⓒ 끝줄 n=3 · 번호 없는 옛 줄 old=1(대상 밖)" $?
printf '| A9 | 짧은 옛 줄 |\n' >> "$Q"; FQr due --min 60
[ "$rc" = 0 ] && grep -qx 'QUEUE-DUE n=5 old=2' <<<"$out"; ck "ⓒ --team 없음 = 전 팀 5 · 상태 칸보다 짧은 옛 줄도 old 로 셈(정본 큐 실측 꼴 · 터짐 0)" $?

# ===== ⓓ remind → 그 팀 _master · 60분 안 반복 0 =====
printf '#!/usr/bin/env bash\nprintf "%%s\\t" "$@" >> "%s"; echo >> "%s"\n' "$T/mbox.log" "$T/mbox.log" > "$T/mbox.sh"
printf '{"_master":"byz-graphics-master-claude#22"}\n' > "$R/seats-graphics.json"
printf '{"_master":"byz-room-master-claude#4"}\n' > "$R/seats-room.json"
printf '{"_master":"byz-planner-master-claude#83"}\n' > "$R/seats-planner.json"
printf '{"_master":"byz-v65-master-claude#215","_name":"Seatbelt"}\n' > "$R/seats.json"
"$BASH" "$BIN/ft-autonomy.sh" off >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" != on ]; ck "준비: 자율 OFF" $?
mkfix; rm -f "$T/mbox.log"
FQr remind --rosters "$R" --mbox "$T/mbox.sh" --min 60; echo "  ⓓ 원문: $(head -3 <<<"$out" | tr '\n' ' ')"
[ "$rc" = 0 ] && [ "$(grep -c 'byz-graphics-master-claude#22' "$T/mbox.log")" = 3 ]; ck "ⓓ graphics master 에 3통(q1·q3·q5)" $?
grep -F 'byz-graphics-master-claude#22' "$T/mbox.log" | grep -F 'ft-tick' | grep -qF '[재질문] q1 · 보여준 지 72분 · graphics 다음 일감을 무엇으로 할지 오빠 선택이 필요합니다 — 후보 셋 중 하나를 고르는 질문입니다 · desk [인터뷰 요청] 로 다시'
ck "ⓓ 쪽지 꼴 = [재질문] q1 · 보여준 지 72분 · <질문 첫 60자> · desk [인터뷰 요청] 로 다시" $?
echo "  ⓓ 쪽지 원문: $(grep -F '[재질문] q1' "$T/mbox.log" | cut -f4)"
[ "$(grep -c "" "$T/mbox.log")" = 5 ]; ck "ⓓ 전체 5통(graphics 3 · room 1 · planner 1)" $?
n1="$(wc -l < "$T/mbox.log")"
FQr remind --rosters "$R" --mbox "$T/mbox.sh" --min 60
[ "$rc" = 0 ] && [ "$(wc -l < "$T/mbox.log")" = "$n1" ]; ck "ⓓ 같은 줄 같은 보여준 시각 → 60분 안 다시 0통" $?
NOWV='2026-10-20 11:01' FQr remind --rosters "$R" --mbox "$T/mbox.sh" --min 60
[ "$(wc -l < "$T/mbox.log")" -gt "$n1" ]; ck "ⓓ 61분 뒤 → 다시 감" $?

# ===== ⓖ 팀 - 줄 → planner _master · 다른 팀 = 그 팀 master =====
grep -F 'byz-planner-master-claude#83' "$T/mbox.log" | grep -qF '[재질문] q8'; ck "ⓖ 팀 - 줄(q8) → planner _master" $?
grep -F 'byz-room-master-claude#4' "$T/mbox.log" | grep -qF '[재질문] q4'; ck "ⓖ room 줄(q4) → room _master" $?

# ===== ⓔ 자율 ON → 쪽지 0 · 아침 묶음 줄만 =====
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1
mkfix; rm -f "$T/mbox.log" "$S/queue-reask.json" "$S/queue-reask-morning.md"
FQr remind --rosters "$R" --mbox "$T/mbox.sh" --min 60
[ "$rc" = 0 ] && [ ! -s "$T/mbox.log" ]; ck "ⓔ 자율 ON → mbox 0통" $?
[ "$(grep -c '^- .*\[재질문\]' "$S/queue-reask-morning.md" 2>/dev/null)" = 5 ]; ck "ⓔ 아침 묶음 줄 5(q1·q3·q4·q5·q8)" $?
echo "  ⓔ 원문: $(head -1 "$S/queue-reask-morning.md" 2>/dev/null)"
FQr remind --rosters "$R" --mbox "$T/mbox.sh" --min 60
[ "$(grep -c '^- ' "$S/queue-reask-morning.md" 2>/dev/null)" = 5 ]; ck "ⓔ 다시 돌려도 아침 묶음 줄 늘지 않음(60분 안)" $?

# ===== ⓕ take =====
mkfix; cp "$Q" "$T/before.md"
FQr take q1 --value '후보 2번(번역 PiP)' --by 'byz-graphics-master-claude#22' --verdict 2501; echo "  ⓕ 원문: $out"
[ "$rc" = 0 ] && [ "$(cell 'graphics 다음 일감을 무엇으로 할지 오빠 선택이 필요합니다 — 후보 셋 중 하나를 고르는 질문입니다' 상태)" = '진행 — byz-graphics-master-claude#22' ]; ck "ⓕ take → 상태 «진행 — <master>»" $?
grep '| q1 |' "$Q" | grep -qF '| 사 · 오빠 값: 후보 2번(번역 PiP) (판정 2501) |'; ck "ⓕ 사유 칸 끝 «오빠 값: … (판정 N)»" $?
grep -qE '^RESUME q1 team=graphics kind=card-start → ' <<<"$out"; ck "ⓕ 출력 1줄 RESUME q1 team=graphics kind=card-start → …" $?
[ "$(diff "$T/before.md" "$Q" | grep -c '^[<>]')" = 2 ]; ck "ⓕ 다른 줄 바이트 0 변경" $?
python3 "$QS" lint "$Q" | tail -1 | grep -qx 'QUEUE-STATE ERR=0 OK=9'; ck "ⓕ take 뒤 상태 린트 OK" $?
FQr take q1 --value v --by m --verdict 1; [ "$rc" != 0 ] && grep -q '^REJECT' <<<"$out"; ck "ⓕ 이미 진행 줄 take → REJECT rc≠0" $?
FQr take q3 --value 'a|b' --by m --verdict x; [ "$rc" != 0 ]; ck "ⓕ 판정 번호 숫자 아님 → rc≠0" $?
FQr take q5 --value '재개' --by m --verdict 7; [ "$rc" = 0 ] && grep -q '| 진행 — m | q5 |' "$Q"; ck "ⓕ 보류 줄도 take 로 꺼냄" $?

# ===== ⓗ 틱 호출 1줄 =====
TICK="$BIN/ft-tick.sh"
awk '/^pass\(\) \{/,/^\}/' "$TICK" | grep -qx '  queue_watch'; ck "ⓗ ft-tick pass() 에 queue_watch 1줄" $?
awk '/^queue_watch\(\) \{/,/^\}/' "$TICK" > "$T/qw.sh"; [ -s "$T/qw.sh" ]; ck "ⓗ queue_watch 함수 추출" $?
mkfix; rm -f "$T/mbox.log" "$S/queue-reask.json"; "$BASH" "$BIN/ft-autonomy.sh" off >/dev/null 2>&1
NOWV='2026-10-20 10:00'
out="$(FT_NOW="$NOWV" "$BASH" -c 'set -uo pipefail; log(){ echo "$*"; }; DRY=0; HERE="$1"; MBOX="$2"; SEATS="$3/seats.json"; ROOT=""; . "$4"; queue_watch' _ "$BIN" "$T/mbox.sh" "$R" "$T/qw.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c '\[재질문\]' "$T/mbox.log" 2>/dev/null)" = 5 ]; ck "ⓗ queue_watch = 명부 폴더로 remind · 5통" $?
out="$("$BASH" -c 'DRY=1; . "$1"; queue_watch' _ "$T/qw.sh" 2>&1)"; [ "$out" = 'DRY kind=queue-reask' ]; ck "ⓗ --dry-run = 쪽지 0 · DRY 1줄" $?
out="$(FT_TICK_QUEUE=0 "$BASH" -c 'DRY=0; . "$1"; queue_watch; echo rc=$?' _ "$T/qw.sh" 2>&1)"; [ "$out" = 'rc=0' ]; ck "ⓗ FT_TICK_QUEUE=0 = 끔" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
