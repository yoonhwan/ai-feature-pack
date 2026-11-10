#!/usr/bin/env bash
# test_desk_reply_wake_question_r1591.sh — h·sha 칸이 없는 오빠 질문(설계 승인 등)도 답글 감시 장부에 등록되고, 오빠 답글이 오면 planner master 를 1통으로 깨운다(승인 판정 0)
#   ⓐ question_row_wakes_planner_once: --register-question <질문ts> r1590 = 장부 1줄(kind=question · h·sha 없음 · +24h) → scan = _master 1통 «[오빠 답글] r1590 ts=<답글>» · 같은 답글 2회차 0통 · 답글 ts 가 바뀌면 1통 더 · 24h 경과 = closed(timeout) + master 1통 · 답글 없음 = 발신 0(열린 줄 유지)
#   ⓑ question_mode_never_prints_slack_ok: ft_oppa_slack_check --reply-only = stdout «REPLY-SEEN parent=<질문> reply=<답글>» 1줄(rc0) · 답글 없음 rc3 · 두 경우 다 SLACK-OK 0줄(승인 길과 분리)
#   ⓒ 기존 시험 rc 불변: test_desk_reply_wake_r1574.sh · test_hil_register_reply_wait_r1587.sh · test_hil_oppa_thread_r1275.sh · test_hil_oppa_only_r1275.sh
#   M1 = 질문 줄 알림 수신자를 _desk 로 → ⓐ «받는이 = _master» 검사 FAIL(시험이 잡는다)
#   격리: 임시 FT_ROOT(명부) · 가짜 mbox(발신 기록) · 가짜 replies(FT_SLACK_REPLIES_CMD · 실 Slack 0) · 가짜 시계 FT_NOW · 임시 HIL_DIR
#   안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0 · exit 0 = 전부 통과
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO_LIMIT=70
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft_desk_reply_wake.py"
CHECK="$BIN/ft_oppa_slack_check.py"
[ -f "$TOOL" ] || { echo "도구 없음: $TOOL" >&2; exit 1; }
[ -f "$CHECK" ] || { echo "점검 도구 없음: $CHECK" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
has() { if grep -Fq -- "$1" "$2" 2>/dev/null; then echo "  OK   $3"; else echo "  FAIL $3 — 없음[$1] in ${2##*/}"; fail=1; fi; }
nhas() { if grep -Fq -- "$1" "$2" 2>/dev/null; then echo "  FAIL $3 — 있으면 안 되는[$1]"; fail=1; else echo "  OK   $3"; fi; }

NOW=1794301443                      # 고정 시계
QTS=1794300200.123456               # h·sha 가 없는 질문 글 ts(설계 승인 질문 꼴)
RTS=1794300260.654321               # 오빠 답글 ts
KEY=r1590                           # 사유키(카드 slug)
DESK="byz-planner-desk-pi#127"
MASTER="byz-planner-master-pi#249"

ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm" "$T/bin" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"
printf '{"_master":"%s","_desk":"%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
export SENT="$T/sent.tsv"; : > "$SENT"

# 가짜 mbox(send = 받는이·본문 1줄 기록 · 실제 발신 0)
cat > "$T/bin/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\n' "$2" "$4" >> "$SENT"
echo "QUEUED seq=stub"
SH

# 가짜 replies(FT_SLACK_REPLIES_CMD) — 부모 질문 + 오빠 답글(REPLY=0 이면 답글 없음)
cat > "$T/bin/replies.sh" <<'SH'
#!/usr/bin/env bash
cat "$REPLIES_JSON"
SH
mk_replies() {  # [답글ts] — 빈 인자면 오빠 답글 없음
  python3 - "$REPLIES_JSON" "${1-$RTS}" "$QTS" <<'PY'
import json, sys
out, rts, qts = sys.argv[1], sys.argv[2], sys.argv[3]
msgs = [{"ts": qts, "user": "U0C9GRFHJ", "text": "설계 승인 부탁드립니다 — r1590 카드"}]
if rts:
    msgs.append({"ts": rts, "user": "U0AC2JF0M7D", "text": "좋아 진행"})
json.dump({"ok": True, "messages": msgs}, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
export REPLIES_JSON="$T/replies.json"
mk_replies

run_tool() {  # [env k=v …] — 임시 루트·가짜 시계·가짜 도구
  ( cd "$ROOT" || exit 1
    export FT_ROOT="$ROOT" FT_NOW="${RUN_NOW:-$NOW}" FT_MBOX_SH="$T/bin/mbox.sh" HIL_DIR="$T/hil" \
           FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" FT_SLACK_CHECK="$CHECK" \
           FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" FT_DESK_REPLY_LEDGER="$LEDGER"
    timeout $TO_LIMIT python3 "${RUN_TOOL:-$TOOL}" )
}
reg_q() { ( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register-question "$@" ); }
sends() { wc -l < "$SENT" 2>/dev/null | tr -d ' ' || echo 0; }
field() { python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r.get(sys.argv[2],"—"))' "$LEDGER" "$1" 2>/dev/null; }
reset() { : > "$SENT"; rm -f "$LEDGER"; }

echo "== ⓐ question_row_wakes_planner_once = 등록 1줄 → scan = _master 1통 · 중복 0 · 24h 닫힘 =="
reset
reg_q "$QTS" "$KEY" >/dev/null 2>&1; RC_A=$?
chk "ⓐ 등록 rc=0" 0 "$RC_A"
chk "ⓐ 장부 1줄" 1 "$(wc -l < "$LEDGER" | tr -d ' ')"
chk "ⓐ q_ts" "$QTS" "$(field q_ts)"
chk "ⓐ kind=question" "question" "$(field kind)"
chk "ⓐ key" "$KEY" "$(field key)"
chk "ⓐ h 칸 없음(h 없이 등록된다)" "—" "$(field h)"
chk "ⓐ sha 칸 없음" "—" "$(field sha)"
chk "ⓐ state" "open" "$(field state)"
chk "ⓐ 끝 시각 = 등록 + 24h" "86400" "$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r["deadline"]-r["at"])' "$LEDGER")"
chk "ⓐ 장부 파일 모드 644(실행 비트 0)" "644" "$(stat -f '%Lp' "$LEDGER" 2>/dev/null || stat -c '%a' "$LEDGER")"

run_tool >"$T/out-a1" 2>"$T/err-a1"; RC_A1=$?
chk "ⓐ scan rc=0" 0 "$RC_A1"
chk "ⓐ 쪽지 1통" 1 "$(sends)"
chk "ⓐ 받는이 = seats-planner.json _master(desk 아님)" "$MASTER" "$(cut -f1 "$SENT")"
chk "ⓐ 본문 = «[오빠 답글] r1590 ts=<답글>»" "[오빠 답글] $KEY ts=$RTS" "$(cut -f2 "$SENT")"
chk "ⓐ 장부 줄 «알림함»" "notified" "$(field state)"
run_tool >/dev/null 2>&1
chk "ⓐ 두 번째 주기 = 같은 답글 0통(중복 억제)" 1 "$(sends)"
mk_replies 1794300300.000001
run_tool >/dev/null 2>&1
chk "ⓐ 답글이 바뀌면(다른 ts) 1통 더" 2 "$(sends)"
mk_replies
reset
reg_q "$QTS" "$KEY" >/dev/null 2>&1
mk_replies ""
run_tool >"$T/out-a3" 2>"$T/err-a3"; RC_A3=$?
chk "ⓐ 답글 없음 = rc0(정상 열린 줄)" 0 "$RC_A3"
chk "ⓐ 답글 없음 = 쪽지 0" 0 "$(sends)"
chk "ⓐ 답글 없음 = 판정 불가 0줄(정상 열림 · 재시도 대기)" 0 "$(grep -c '판정 불가' "$T/err-a3" || true)"
chk "ⓐ 답글 없어도 줄은 open 그대로" "open" "$(field state)"
mk_replies
RUN_NOW=$((NOW + 86401)) run_tool >/dev/null 2>"$T/err-a4"; RC_A4=$?
chk "ⓐ 24h 경과 rc=0" 0 "$RC_A4"
chk "ⓐ 경과 = master 1통" 1 "$(sends)"
chk "ⓐ 경과 받는이 = _master" "$MASTER" "$(cut -f1 "$SENT")"
case "$(cut -f2 "$SENT")" in *"[답글 없음 24시간] $KEY"*) echo "  OK   ⓐ 경과 본문 = «[답글 없음 24시간] r1590»";; *) echo "  FAIL ⓐ 경과 본문: $(cut -f2 "$SENT")"; fail=1;; esac
chk "ⓐ 경과 = 줄 닫힘(timeout)" "closed timeout" "$(field state) $(field closed)"
reset
reg_q "$QTS" "$KEY" >/dev/null 2>&1
OUT_A5="$(reg_q "$QTS" "$KEY" x 2>&1)"; RC_A5=$?
chk "ⓐ 인자 3개(꼴 아님) = rc3" 3 "$RC_A5"
case "$OUT_A5" in *"감시 등록 실패"*) echo "  OK   ⓐ 꼴 아님 = «감시 등록 실패» 1줄";; *) echo "  FAIL ⓐ 꼴 아님 답: $OUT_A5"; fail=1;; esac
chk "ⓐ 꼴 아님 = 장부 안 늘어남(1줄)" 1 "$(wc -l < "$LEDGER" | tr -d ' ')"
OUT_A6="$(reg_q "$QTS" "$KEY" 2>&1)"; RC_A6=$?
chk "ⓐ 같은 질문 재등록 rc=0(멱등)" 0 "$RC_A6"
case "$OUT_A6" in *"이미 등록"*) echo "  OK   ⓐ 재등록은 «이미 등록» 1줄로 답한다";; *) echo "  FAIL ⓐ 재등록 답: $OUT_A6"; fail=1;; esac

echo "== ⓑ question_mode_never_prints_slack_ok = REPLY-SEEN 만 · SLACK-OK 0줄 =="
ROUT="$( ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" timeout $TO_LIMIT python3 "$CHECK" --reply-only "$QTS" ) 2>"$T/err-b1" )"; RC_B1=$?
printf '%s\n' "$ROUT" > "$T/out-b1"
chk "ⓑ 답글 있음 rc=0" 0 "$RC_B1"
chk "ⓑ 출력 = «REPLY-SEEN parent=<질문> reply=<답글>» 1줄" "REPLY-SEEN parent=$QTS reply=$RTS" "$ROUT"
chk "ⓑ 출력 줄 수 = 1(SLACK-OK 0줄)" 1 "$(printf '%s\n' "$ROUT" | wc -l | tr -d ' ')"
mk_replies ""
ROUT2="$( ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" timeout $TO_LIMIT python3 "$CHECK" --reply-only "$QTS" ) 2>"$T/err-b2" )"; RC_B2=$?
chk "ⓑ 답글 없음 rc=3(판정 불가 2 아님)" 3 "$RC_B2"
chk "ⓑ 답글 없음 = stdout 0줄" "" "$ROUT2"
mk_replies
SHAS="$( ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" python3 "$CHECK" "$QTS" 0123456789abcdef0123456789abcdef01234567 ) 2>&1 )"; RC_B3=$?
chk "ⓑ 승인 길(2인자)은 그대로 rc=2(질문 글에 sha 없음)" 2 "$RC_B3"
case "$SHAS" in "REJECT 오빠 슬랙 승인 확인 실패: 질문 글에"*) echo "  OK   ⓑ 승인 길은 «질문 글에 sha 없음» 으로 거절(모드 분리)";; *) echo "  FAIL ⓑ 승인 길 답: $SHAS"; fail=1;; esac
nhas "SLACK-OK" "$T/err-b1" "ⓑ stderr 에도 SLACK-OK 0줄(답글 있음)"
nhas "SLACK-OK" "$T/out-b1" "ⓑ stdout 에 SLACK-OK 0줄"

echo "== ⓒ 기존 시험 rc 불변 =="
for t in test_desk_reply_wake_r1574.sh test_hil_register_reply_wait_r1587.sh test_hil_oppa_thread_r1275.sh test_hil_oppa_only_r1275.sh; do
  [ -f "$HERE/$t" ] || { echo "  FAIL ⓒ 시험 없음: $t"; fail=1; continue; }
  timeout $TO_LIMIT bash "$HERE/$t" >"$T/$t.log" 2>&1; rc=$?
  chk "ⓒ $t rc=0" 0 "$rc"
done

echo "== kit 사본 2개가 bin 과 같다(cmp0) =="
cmp -s "$TOOL" "$BIN/../kit/fable-team/bin/ft_desk_reply_wake.py" && echo "  OK   cmp0 ft_desk_reply_wake.py" || { echo "  FAIL cmp0 ft_desk_reply_wake.py"; fail=1; }
cmp -s "$CHECK" "$BIN/../kit/fable-team/bin/ft_oppa_slack_check.py" && echo "  OK   cmp0 ft_oppa_slack_check.py" || { echo "  FAIL cmp0 ft_oppa_slack_check.py"; fail=1; }

echo "== 변이 M1 = 질문 줄 알림 수신자를 _desk 로 → ⓐ «받는이 = _master» 검사가 잡는다 =="
MUT="$T/mut"; mkdir -p "$MUT"
cp "$TOOL" "$MUT/m1.py"
python3 - "$MUT/m1.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
old = 'send(base, seat["_master"], "[오빠 답글] %s ts=%s" % (name, m.group(1)))'
assert old in t, old
p.write_text(t.replace(old, 'send(base, seat.get("_desk") or "", "[오빠 답글] %s ts=%s" % (name, m.group(1)))', 1), encoding="utf-8")
PY
reset
reg_q "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$MUT/m1.py" run_tool >/dev/null 2>&1
if [ "$(cut -f1 "$SENT" 2>/dev/null)" = "$MASTER" ]; then echo "  FAIL M1 — 수신자를 _desk 로 바꿨는데도 _master 로 갔다(시험이 약하다)"; fail=1; else echo "  OK   M1 수신자 _desk → ⓐ «받는이 = _master» 검사 FAIL(실제 $(cut -f1 "$SENT" 2>/dev/null))"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (ⓐ ⓑ ⓒ · 변이 M1 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
