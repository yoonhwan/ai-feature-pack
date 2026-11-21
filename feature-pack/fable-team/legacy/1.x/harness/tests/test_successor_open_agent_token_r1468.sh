#!/usr/bin/env bash
# test_successor_open_agent_token_r1468.sh — r1468: 승계 이름 꼬리 토큰 = --agent · R213 면제의 agent 교체 · 하위 인박스 계보 잇기.
#   T1 꼬리≠agent → REJECT rc2 · tmuxc 0 | T2 OLD 베이스의 agent 토큰만 바꾼 #N+1 → R213 면제(문지기 --succession)
#   T3 번호 +3 · 팀 다름 → 면제 0 | T4 ft-inbox.py link → 새 큐 첫 줄 prev_lineage · 옛 파일 바이트 불변 · 두 번 불러도 1행
#   T5 옛 큐 1 + 새 큐 1 → 새 좌석 show 에 옛→새 순 · --seqs·--count 도 같은 계보 읽기 · 계보 같으면 prev_lineage 0 | T7 agent 왕복 교대(pi→claude)도 이전 큐 읽기 | T6 기존 시험 5개 = 따로 실행(시험 1개 70초 · 하드 룰 22) — 여기선 존재·bash -n
#   임시 리포·가짜 tmux·tmuxc·문지기 스텁(임시 bin 사본)만 — 실 명부·실 tmux·실 큐 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${FT_SO_KIT:-$HERE/../kit/fable-team/bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"; cp -R "$KIT/." "$BIN/"; SO="$BIN/ft-successor-open.sh"
# 문지기 스텁 — 받은 인자를 적고 rc1(그 뒤 단계로 가지 않는다 · 면제 여부만 본다)
printf '#!/usr/bin/env bash\necho "GATE $*" >> "$LOG"; echo "REJECT stub gate"; exit 1\n' > "$BIN/ft-resource-gate.sh"
printf 'import sys\nsys.exit(0)\n' > "$BIN/ft_teamset.py"   # arch 상시 게이트 = 이 시험 범위 밖(통과)
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; RES="$TMP/res"
mkdir -p "$REPO" "$FAKE" "$RES/.fable-team"; git -C "$REPO" init -q
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux  'case "$1" in has-session) [ "$3" = "=$LIVE_OLD" ] && exit 0; exit 1;; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; exit 0'
printf '골 1\n골 2\n골 3\n본문\n열린 칸 감시: 없음\n' > "$BODY"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-claude | — |\n' > "$TMP/teamset.md"
OLD='byz-t-master-claude#4'
printf '{"_master": "%s", "%s": {"agent": "claude"}}\n' "$OLD" "$OLD" > "$RES/.fable-team/seats-t.json"
run() {   # run <구> <후계> <agent>
  rm -f "$LOG"; : > "$LOG"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" LOG="$LOG" LIVE_OLD="$1" FT_RES_ROOT="$RES" FT_TEAMSET_MD="$TMP/teamset.md" FT_RECLAIM=0 \
      bash "$SO" "$1" "$REPO" --name "$2" --agent "$3" --model m --verdict 1 --body-file "$BODY" > "$TMP/out" 2>&1   # r2403: 모델 «m» 은 표 값이 아니다 — 사람 판정(--verdict)으로 통과시켜 꼬리 검사만 본다
  RC=$?
}

# T1 꼬리 claude ≠ --agent pi → REJECT 1줄 rc2 · 열기 0 · 문지기 0
run "$OLD" 'byz-t-master-claude#5' pi
{ [ "$RC" = 2 ] && grep -q '^REJECT 이름 꼬리 claude ≠ --agent pi — 이름 = byz-t-master-pi#N' "$TMP/out" && ! grep -q '^tmuxc\|^GATE' "$LOG"; } \
  && ok "T1 꼬리≠agent → REJECT rc2 · 열기 0" || bad "T1 rc=$RC out=$(tr '\n' ' ' < "$TMP/out") log=$(tr '\n' ' ' < "$LOG")"
# T1-2 옛 이름 교대(꼬리 = agent) 는 꼬리 검사 통과(문지기까지 간다)
run "$OLD" 'byz-t-master-claude#5' claude
{ ! grep -q '이름 꼬리' "$TMP/out" && grep -q '^GATE check --succession' "$LOG"; } \
  && ok "T1-2 옛 이름 교대 = 면제 그대로" || bad "T1-2 rc=$RC out=$(tr '\n' ' ' < "$TMP/out") log=$(tr '\n' ' ' < "$LOG")"

# T2 OLD 베이스의 agent 토큰만 pi 로 바꾼 #5 → R213 면제(--succession)
run "$OLD" 'byz-t-master-pi#5' pi
{ grep -q '^GATE check --succession' "$LOG" && ! grep -q '이름 꼬리' "$TMP/out"; } \
  && ok "T2 agent 토큰 교체 #N+1 → R213 면제" || bad "T2 rc=$RC out=$(tr '\n' ' ' < "$TMP/out") log=$(tr '\n' ' ' < "$LOG")"

# T3 번호 +3 · 팀 다름 → 면제 0(일반 문턱)
run "$OLD" 'byz-t-master-pi#7' pi
{ grep -q '^GATE check$' "$LOG"; } && ok "T3 번호 +3 → 면제 0" || bad "T3 log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"
run "$OLD" 'byz-u-master-pi#5' pi
{ grep -q '^GATE check$' "$LOG"; } && ok "T3-2 팀 다름 → 면제 0" || bad "T3-2 log=$(tr '\n' ' ' < "$LOG") out=$(tr '\n' ' ' < "$TMP/out")"

# T4·T5 하위 인박스 계보 잇기 — 임시 FT_ROOT
FR="$TMP/ftroot"; IN="$FR/.fable-team/state/inbox"; CM="$FR/.fable-team/comm"; mkdir -p "$IN" "$CM/bodies"
mail() { printf '{"seq": %s, "ts": "2026-11-08T15:0%s:00", "from": "byz-x-nano-claude#1", "to": "%s", "body": "%s"}\n' "$1" "$1" "$2" "$3" >> "$CM/mailbox.jsonl"; }
ib() { env FT_ROOT="$FR" python3 "$BIN/ft-inbox.py" "$@"; }
lk() { env FT_ROOT="$FR" python3 "$BIN/ft-inbox.py" link "$@"; }
mail 1 "$OLD" '옛 계보 쪽지 하나'
ib ingest 1 > /dev/null 2>&1
OLDQ="$IN/byz-t-master-claude.jsonl"; NEWQ="$IN/byz-t-master-pi.jsonl"
SUM0="$(shasum "$OLDQ" 2>/dev/null)"
lk "$OLD" 'byz-t-master-pi#5' > "$TMP/l1" 2>&1; L1=$?
lk "$OLD" 'byz-t-master-pi#5' > "$TMP/l2" 2>&1; L2=$?
{ [ "$L1" = 0 ] && [ "$L2" = 0 ] && [ -n "$SUM0" ] && [ "$(head -1 "$NEWQ" 2>/dev/null)" = '{"prev_lineage": "byz-t-master-claude"}' ] \
  && [ "$(grep -c prev_lineage "$NEWQ")" = 1 ] && [ "$(shasum "$OLDQ")" = "$SUM0" ]; } \
  && ok "T4 새 큐 첫 줄 prev_lineage · 옛 파일 불변 · 두 번에 1행" || bad "T4 L1=$L1 L2=$L2 new=$(cat "$NEWQ" 2>&1 | tr '\n' ' ') l1=$(cat "$TMP/l1")"

mail 2 'byz-t-master-pi#5' '새 계보 쪽지 둘'
ib ingest 2 > /dev/null 2>&1
ib show 'byz-t-master-pi#5' > "$TMP/show" 2>&1; SR=$?
{ [ "$SR" = 0 ] && [ "$(grep -o 'seq=[0-9]* ' "$TMP/show" | tr -d '\n')" = "seq=1 seq=2 " ] \
  && [ "$(head -1 "$NEWQ")" = '{"prev_lineage": "byz-t-master-claude"}' ] && [ "$(shasum "$OLDQ")" = "$SUM0" ]; } \
  && ok "T5 새 좌석 show = 옛→새 2건" || bad "T5 rc=$SR show=$(tr '\n' ' ' < "$TMP/show") new=$(tr '\n' ' ' < "$NEWQ" 2>&1)"
# T5-2 mark 가 옛 계보 줄에 닿으면 옛 파일에 쓰고 새 파일로 옮기지 않는다(중복 0)
ib mark 1 처리 '옛 줄 처리' --seat 'byz-t-master-pi#5' > /dev/null 2>&1; MR=$?
{ [ "$MR" = 0 ] && [ "$(grep -c '"seq": 1' "$NEWQ")" = 0 ] && grep -q '"kind": "처리"' "$OLDQ" && [ "$(head -1 "$NEWQ")" = '{"prev_lineage": "byz-t-master-claude"}' ]; } \
  && ok "T5-2 옛 줄 mark = 옛 파일에 · 새 파일 중복 0" || bad "T5-2 rc=$MR new=$(tr '\n' ' ' < "$NEWQ") old=$(tr '\n' ' ' < "$OLDQ")"
# T5-3 계보 같으면 prev_lineage 0
lk 'byz-t-master-pi#5' 'byz-t-master-pi#6' > "$TMP/l3" 2>&1; L3=$?
{ [ "$L3" = 0 ] && [ "$(grep -c prev_lineage "$NEWQ")" = 1 ]; } && ok "T5-3 같은 계보 → prev_lineage 추가 0" || bad "T5-3 L3=$L3 $(cat "$TMP/l3")"
# T5-4 show --seqs(기계용 창 읽기)·--count 도 이전 계보를 읽는다 — 사람용 show 와 같은 미닫힘(DA#10 HOLD ①)
mail 3 'byz-t-master-pi#5' '새 계보 쪽지 셋'
ib ingest 3 > /dev/null 2>&1
ib show 'byz-t-master-pi#5' --seqs > "$TMP/seqs" 2>&1; QR=$?
ib show 'byz-t-master-pi#5' --count > "$TMP/cnt" 2>&1
{ [ "$QR" = 0 ] && [ "$(grep -o 'seq=[0-9]* 미닫힘=[0-9]*' "$TMP/seqs" | tr '\n' ' ')" = "seq=1 미닫힘=1 seq=2 미닫힘=2 seq=3 미닫힘=3 " ] \
  && [ "$(tr '\n' ' ' < "$TMP/cnt")" = "OPEN 3 OLDEST seq=1 " ]; } \
  && ok "T5-4 show --seqs·--count = 사람용 show 와 같은 미닫힘(옛 seq1 + 새 seq2·3)" || bad "T5-4 rc=$QR seqs=$(tr '\n' ' ' < "$TMP/seqs") cnt=$(tr '\n' ' ' < "$TMP/cnt")"
# T7 agent 왕복 교대 pi#5 → claude#6 — 이전 미처리 큐를 읽고 파일 삭제·이동·복제 0(DA#10 HOLD ②)
L0="$(cat "$OLDQ" "$NEWQ" | grep -c '"seq"')"
lk 'byz-t-master-pi#5' 'byz-t-master-claude#6' > "$TMP/l4" 2>&1; L4=$?
lk 'byz-t-master-pi#5' 'byz-t-master-claude#6' > /dev/null 2>&1
ib show 'byz-t-master-claude#6' > "$TMP/rt" 2>&1; RT=$?
ib show 'byz-t-master-claude#6' --seqs > "$TMP/rts" 2>&1
{ [ "$L4" = 0 ] && [ "$RT" = 0 ] && grep -q 'seq=3 미닫힘=3' "$TMP/rt" && grep -q 'seq=1 미닫힘=1' "$TMP/rt" && grep -q 'seq=3 미닫힘=3' "$TMP/rts" \
  && [ "$(head -1 "$OLDQ")" = '{"prev_lineage": "byz-t-master-pi"}' ] && [ "$(grep -c prev_lineage "$OLDQ")" = 1 ] \
  && [ "$(cat "$OLDQ" "$NEWQ" | grep -c '"seq"')" = "$L0" ] && [ "$(ls "$IN"/*.jsonl | wc -l | tr -d ' ')" = 2 ]; } \
  && ok "T7 왕복 교대 → claude#6 show 에 pi 미처리 seq3 · 행 수 불변 · 파일 2개" || bad "T7 L4=$L4 l4=$(cat "$TMP/l4") rt=$(tr '\n' ' ' < "$TMP/rt") old=$(head -1 "$OLDQ")"
# T7-2 왕복 뒤 새 좌석 mark 가 pi 큐 줄을 그 파일에서 닫는다(옮김·복제 0)
ib mark 3 처리 '왕복 뒤 처리' --seat 'byz-t-master-claude#6' > /dev/null 2>&1; M7=$?
{ [ "$M7" = 0 ] && grep '"seq": 3' "$NEWQ" | grep -q '"kind": "처리"' && [ "$(grep -c '"seq": 3' "$OLDQ")" = 0 ]; } \
  && ok "T7-2 왕복 뒤 mark = pi 파일에서 · claude 파일 복제 0" || bad "T7-2 rc=$M7"

# T6 기존 successor-open 시험 5개 — 존재·bash -n(실행은 따로 · 시험 1개 70초)
t6=0
for t in test_successor_open.sh test_successor_open_carry.sh test_successor_open_resume_r1116c.sh test_successor_open_ctx_r1060.sh test_successor_open_master_model.sh; do
  bash -n "$HERE/$t" || t6=1
done
[ "$t6" = 0 ] && ok "T6 기존 시험 5개 존재·구문(실행 rc0 은 따로)" || bad "T6"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
