#!/usr/bin/env bash
# test_desk_reply_wake_r1574.sh — ft_desk_reply_wake.py 반례 ⓐ~ⓔ + 변이 M1~M4 + stall-scan 연결 1줄
#   ⓐ 등록(정상·sha 오타·장부 못 씀 = «감시 등록 실패» 1줄) ⓑ 답글 → 현역 _desk 1통·중복 0
#   ⓒ h 실행 기록/24시간 경과 = 줄 닫힘(경과는 _master 1통) ⓓ 조회 실패·_desk 없음 = «판정 불가» 1줄·알림 기록 0·다음 주기 재시도 ⓔ 쓰기 범위 = 장부·쪽지뿐
#   격리: 임시 FT_ROOT(명부) · 가짜 mbox(보낸 to·본문 기록) · 가짜 replies(FT_SLACK_REPLIES_CMD · 실 Slack 0) · 가짜 시계 FT_NOW · 임시 HIL_DIR
#   변이 4 = M1 중복 억제 제거(→ ⓑ FAIL) · M2 조회 실패를 알림함으로(→ ⓓ FAIL) · M3 끝 시각 검사 제거(→ ⓒ FAIL) · M4 수신자 = 명부 정렬 첫 desk 값(→ ⓑ FAIL)
#   안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0(sleep 0) · exit 0 = 전부 통과
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

NOW=1794301443                      # 2026-11-10 09:2x KST 무렵 고정 시계
QTS=1794295513.494289               # 질문 글 ts(실사건 그대로)
RTS=1794295574.209829               # 오빠 답글 ts
SHA=0123456789abcdef0123456789abcdef01234567
DESK="byz-planner-desk-pi#127"
MASTER="byz-planner-master-pi#249"

ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm" "$T/bin" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"
printf '{"_master":"%s","_desk":"%s","_desk_retired":"byz-planner-desk-claude#126"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
export SENT="$T/sent.tsv" CALLS="$T/replies-calls.log" REPLIES_JSON="$T/replies.json"
: > "$SENT"; : > "$CALLS"

# 가짜 mbox(send = 받는이·본문 1줄 기록 · 실제 발신 0)
cat > "$T/bin/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\n' "$2" "$4" >> "$SENT"
echo "QUEUED seq=stub"
SH

# 가짜 replies(FT_SLACK_REPLIES_CMD) — 부를 때마다 1줄 기록 · REPLY_FAIL=1 이면 rc9(조회 실패)
cat > "$T/bin/replies.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${FT_SLACK_TS:-}" >> "$CALLS"
[ "${REPLY_FAIL:-0}" = 1 ] && { echo "slack: not_authed" >&2; exit 9; }
cat "$REPLIES_JSON"
SH

# 부모 질문 글 + 오빠 답글 1개(ft_oppa_slack_check 판정 규칙 그대로)
mk_replies() {  # [답글ts] [부모 ts] [부모 글자]
  python3 - "$REPLIES_JSON" "${1:-$RTS}" "${2:-$QTS}" "${3:-sha $SHA 승인 요청}" <<'PY'
import json, sys
out, rts, qts, text = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
msgs = [{"ts": qts, "user": "U0C9GRFHJ", "text": text}]
if rts:
    msgs.append({"ts": rts, "user": "U0AC2JF0M7D", "text": "OK 승인"})
json.dump({"ok": True, "messages": msgs}, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
mk_replies

run_tool() {  # [env k=v …] — 임시 루트·가짜 시계·가짜 도구
  ( cd "$ROOT" || exit 1
    export FT_ROOT="$ROOT" FT_NOW="${RUN_NOW:-$NOW}" FT_MBOX_SH="$T/bin/mbox.sh" HIL_DIR="$T/hil" \
           FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" FT_SLACK_CHECK="$CHECK" \
           FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" FT_DESK_REPLY_LEDGER="$LEDGER"
    for kv in "$@"; do export "${kv?}"; done
    timeout $TO_LIMIT python3 "${RUN_TOOL:-$TOOL}" )
}
sends() { wc -l < "$SENT" 2>/dev/null | tr -d ' ' || echo 0; }
reset() { : > "$SENT"; : > "$CALLS"; rm -f "$LEDGER" "$T/hil"/*.ran; }
reg() { run_tool "$@" -- 2>/dev/null; }   # 자리표시(쓰지 않음)

echo "== ⓐ 등록 = 장부 1줄(질문 ts · h · sha · 등록 시각 · 끝 시각 = +24h) =="
reset
OUT_A="$( ( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h12 "$SHA" ) 2>"$T/err-a" )"; RC_A=$?
chk "ⓐ 정상 등록 rc=0" 0 "$RC_A"
chk "ⓐ 장부 1줄" 1 "$(wc -l < "$LEDGER" 2>/dev/null | tr -d ' ')"
python3 - "$LEDGER" "$NOW" "$QTS" <<'PY' > "$T/a-fields" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
now, q = int(sys.argv[2]), sys.argv[3]
print("%s %s %s %d %d %s" % (r.get("q_ts"), r.get("h"), r.get("sha"), r.get("at", 0), r.get("deadline", 0) - r.get("at", 0), r.get("state")))
PY
chk "ⓐ 칸 값(질문 ts · h12 · sha · at · +86400 · open)" "$QTS h12 $SHA $NOW 86400 open" "$(cat "$T/a-fields")"
chk "ⓐ 장부 파일 모드 644(실행 비트 0)" "644" "$(stat -f '%Lp' "$LEDGER" 2>/dev/null || stat -c '%a' "$LEDGER")"
OUT_A2="$( ( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h13 "0123456789abcdef" ) 2>&1 )"; RC_A2=$?
chk "ⓐ sha 오타 등록 = rc3" 3 "$RC_A2"
case "$OUT_A2" in *"감시 등록 실패"*) echo "  OK   ⓐ 실패를 1줄로 드러낸다(조용한 0 금지)";; *) echo "  FAIL ⓐ 실패 줄 없음: $OUT_A2"; fail=1;; esac
chk "ⓐ 실패한 등록은 장부를 안 늘린다" 1 "$(wc -l < "$LEDGER" | tr -d ' ')"
mv "$LEDGER" "$LEDGER.ok"; : > "$LEDGER.dir-as-file-check"
BADLED="$T/bad-dir/desk-reply-wait.jsonl"; : > "$T/bad-dir"
OUT_A3="$( ( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$BADLED" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h12 "$SHA" ) 2>&1 )"; RC_A3=$?
chk "ⓐ 장부를 못 쓰면 rc3" 3 "$RC_A3"
case "$OUT_A3" in *"감시 등록 실패"*) echo "  OK   ⓐ 못 씀이 «감시 등록 실패» 1줄";; *) echo "  FAIL ⓐ 못 씀 줄 없음: $OUT_A3"; fail=1;; esac
rm -f "$LEDGER"; mv "$LEDGER.ok" "$LEDGER"

echo "== ⓑ 오빠 답글 → 현역 _desk 1통 · 같은 답글 1통 =="
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h12 "$SHA" ) >/dev/null
run_tool >"$T/out-b1" 2>"$T/err-b1"; RC_B1=$?
chk "ⓑ rc=0" 0 "$RC_B1"
chk "ⓑ 쪽지 1통" 1 "$(sends)"
chk "ⓑ 받는이 = seats-planner.json _desk" "$DESK" "$(cut -f1 "$SENT")"
chk "ⓑ 본문 = «[오빠 답글] h12 ts=<답글> → 실행 차례»" "[오빠 답글] h12 ts=$RTS → 실행 차례" "$(cut -f2 "$SENT")"
python3 - "$LEDGER" "$RTS" <<'PY' > "$T/b2-state" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
print(r.get("state"), r.get("notified_ts") == sys.argv[2])
PY
chk "ⓑ 장부 줄 «알림함»" "notified True" "$(cat "$T/b2-state")"
run_tool >/dev/null 2>&1
chk "ⓑ 두 번째 주기 = 같은 답글 0통(중복 억제)" 1 "$(sends)"
mk_replies 1794295600.000001; : > "$SENT"
run_tool >/dev/null 2>&1
chk "ⓑ 답글이 바뀌면(다른 ts) 1통 더" 1 "$(sends)"
mk_replies

echo "== ⓒ h 실행 기록 · 24시간 경과 = 줄 닫힘 =="
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h21 "$SHA" ) >/dev/null
: > "$T/hil/h21.ran"
run_tool >/dev/null 2>&1
chk "ⓒ h 실행 기록 = 쪽지 0" 0 "$(sends)"
python3 - "$LEDGER" <<'PY' > "$T/c1-state" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
print(r.get("state"), r.get("closed"))
PY
chk "ⓒ 그 줄 닫힘(executed)" "closed executed" "$(cat "$T/c1-state")"
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h22 "$SHA" ) >/dev/null
RUN_NOW=$((NOW + 86401)) run_tool >/dev/null 2>"$T/err-c2"; RC_C2=$?
chk "ⓒ 끝 시각 경과 rc=0" 0 "$RC_C2"
chk "ⓒ 경과 = planner master 1통" 1 "$(sends)"
chk "ⓒ 경과 받는이 = _master" "$MASTER" "$(cut -f1 "$SENT")"
case "$(cut -f2 "$SENT")" in *"[답글 없음 24시간] h22"*) echo "  OK   ⓒ 경과 본문 = «[답글 없음 24시간]»";; *) echo "  FAIL ⓒ 경과 본문: $(cut -f2 "$SENT")"; fail=1;; esac
python3 - "$LEDGER" <<'PY' > "$T/c2-state" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
print(r.get("state"), r.get("closed"))
PY
chk "ⓒ 그 줄 닫힘(timeout)" "closed timeout" "$(cat "$T/c2-state")"
RUN_NOW=$((NOW + 90000)) run_tool >/dev/null 2>&1
chk "ⓒ 닫힌 줄은 다시 알리지 않는다" 1 "$(sends)"

echo "== ⓓ 조회 실패 · _desk 없음 = «판정 불가» 1줄 · 알림 기록 0 · 다음 주기 재시도 =="
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h31 "$SHA" ) >/dev/null
REPLY_FAIL=1 run_tool >/dev/null 2>"$T/err-d1"; RC_D1=$?
chk "ⓓ 조회 실패 rc=1(판정 불가 있음)" 1 "$RC_D1"
chk "ⓓ 조회 실패 = 쪽지 0" 0 "$(sends)"
has "판정 불가" "$T/err-d1" "ⓓ «판정 불가» 1줄"
python3 - "$LEDGER" <<'PY' > "$T/d1-state" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
print(r.get("state"), "notified_ts" in r)
PY
chk "ⓓ 알림 완료 기록 0(줄은 open 그대로)" "open False" "$(cat "$T/d1-state")"
run_tool >/dev/null 2>&1
chk "ⓓ 다음 주기에 다시 봐서 1통" 1 "$(sends)"
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h32 "$SHA" ) >/dev/null
printf '{"_master":"%s"}\n' "$MASTER" > "$T/seats-nodesk.json"
run_tool "FT_SEATS_PLANNER=$T/seats-nodesk.json" >/dev/null 2>"$T/err-d3"; RC_D3=$?
chk "ⓓ _desk 없음 rc=1" 1 "$RC_D3"
chk "ⓓ _desk 없음 = 쪽지 0" 0 "$(sends)"
has "_desk 없음" "$T/err-d3" "ⓓ «_desk 없음» 1줄(다음 주기 재시도)"
python3 - "$LEDGER" <<'PY' > "$T/d3-state" || true
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").readline())
print(r.get("state"), "notified_ts" in r)
PY
chk "ⓓ _desk 없음 = 알림 기록 0" "open False" "$(cat "$T/d3-state")"

echo "== ⓔ 쓰기 범위 = 장부·쪽지뿐(Slack 쓰기 0 · h 실행 0) =="
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h41 "$SHA" ) >/dev/null
BEFORE="$(cd "$ROOT" && find . -type f ! -name 'desk-reply-wait.jsonl' | sort | xargs shasum 2>/dev/null | shasum)"
: > "$CALLS"
run_tool >/dev/null 2>&1
AFTER="$(cd "$ROOT" && find . -type f ! -name 'desk-reply-wait.jsonl' ! -name 'desk-reply-wait.jsonl.tmp' | sort | xargs shasum 2>/dev/null | shasum)"
chk "ⓔ 장부 밖 파일 변화 0(명부·루트 그대로)" "$BEFORE" "$AFTER"
chk "ⓔ h 실행 기록 0(실행은 desk)" 0 "$(ls "$T/hil" | grep -c '\.ran$')"
case "$(cat "$CALLS")" in *"$QTS"*) echo "  OK   ⓔ Slack 은 읽기(conversations.replies 대역)만 불렀다";; *) echo "  FAIL ⓔ replies 조회 0"; fail=1;; esac
chk "ⓔ 쪽지 1통(그 외 발신 0)" 1 "$(sends)"

echo "== stall-scan 연결 1줄(120초 주기 재사용 · --dry-run 제외 · 새 launchd 0) =="
has "ft_desk_reply_wake.py" "$BIN/ft-stall-scan.sh" "ft-stall-scan.sh 에 점검 호출 1줄"
grep -Fq -- '[ "${1:-}" = --dry-run ] || [ ! -f "$HERE/ft_desk_reply_wake.py" ]' "$BIN/ft-stall-scan.sh" \
  && echo "  OK   --dry-run 에서는 부르지 않는다" || { echo "  FAIL --dry-run 가드 없음"; fail=1; }
cmp -s "$BIN/ft_desk_reply_wake.py" "$BIN/../kit/fable-team/bin/ft_desk_reply_wake.py" \
  && echo "  OK   cmp0 harness/bin ↔ kit 사본(점검)" || { echo "  FAIL cmp0 점검 스크립트"; fail=1; }
cmp -s "$BIN/ft-stall-scan.sh" "$BIN/../kit/fable-team/bin/ft-stall-scan.sh" \
  && echo "  OK   cmp0 harness/bin ↔ kit 사본(ft-stall-scan.sh)" || { echo "  FAIL cmp0 ft-stall-scan.sh"; fail=1; }

echo "== 변이 4 =="
MUT="$T/mut"; mkdir -p "$MUT"
mutate() {  # <이름> <python 조각> — 원본을 복사해 조각을 적용
  cp "$TOOL" "$MUT/$1.py"
  python3 - "$MUT/$1.py" "$2" <<'PY'
import sys, pathlib
p, frag = pathlib.Path(sys.argv[1]), sys.argv[2]
t = p.read_text(encoding="utf-8")
old, new = frag.split("@@")
assert old in t, old
p.write_text(t.replace(old, new, 1), encoding="utf-8")
PY
}
# M1: 중복 억제 제거 — 같은 답글에도 다시 1통
mutate m1 'if row.get("notified_ts") == m.group(1):  # ⓑ 중복 억제 키 = 질문 ts·답글 ts@@if False:  # M1'
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h51 "$SHA" ) >/dev/null
RUN_TOOL="$MUT/m1.py" run_tool >/dev/null 2>&1
RUN_TOOL="$MUT/m1.py" run_tool >/dev/null 2>&1
if [ "$(sends)" = 1 ]; then echo "  FAIL M1 — 중복 억제를 뺐는데도 1통(시험이 약하다)"; fail=1; else echo "  OK   M1 중복 억제 제거 → ⓑ «1통» 검사 FAIL(시험이 잡는다 · 실제 $(sends)통)"; fi
# M2: 조회 실패를 «알림함» 으로 기록 — 판정 불가인데 알림 완료로 남는다
mutate m2 'if not m:  # ⓓ 조회 실패·토큰 없음 = «판정 불가» 1줄 · 알림 완료 기록 0@@if not m:  # M2
            row["notified_ts"], row["state"] = "0.0", "notified"'
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h52 "$SHA" ) >/dev/null
REPLY_FAIL=1 RUN_TOOL="$MUT/m2.py" run_tool >/dev/null 2>&1
STATE_M2="$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r.get("state"),"notified_ts" in r)' "$LEDGER" 2>/dev/null || echo err)"
if [ "$STATE_M2" = "open False" ]; then echo "  FAIL M2 — 조회 실패를 알림함으로 기록했는데도 «open False»(시험이 약하다)"; fail=1; else echo "  OK   M2 조회 실패를 알림함으로 → ⓓ «알림 완료 기록 0» 검사 FAIL(실제 $STATE_M2)"; fi
# M3: 끝 시각 검사 제거 — 24시간 지나도 닫히지 않는다
mutate m3 'if now >= float(row.get("deadline") or 0):  # ⓒ 24시간 경과 = 닫고 planner master 1통@@if False:  # M3'
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h53 "$SHA" 2>/dev/null ) >/dev/null
makereplys_ts="$(RUN_NOW=$((NOW + 86401)) RUN_TOOL="$MUT/m3.py" run_tool 2>&1)"
STATE_M3="$(python3 -c 'import json,sys;print(json.loads(open(sys.argv[1],encoding="utf-8").readline()).get("state"))' "$LEDGER" 2>/dev/null || echo err)"
if [ "$STATE_M3" = "closed" ]; then echo "  FAIL M3 — 끝 시각 검사를 뺐는데도 닫혔다(시험이 약하다)"; fail=1; else echo "  OK   M3 끝 시각 검사 제거 → ⓒ «닫힘(timeout)» 검사 FAIL(실제 $STATE_M3)"; fi
# M4: 수신자를 «명부 정렬 첫 desk 값» 으로 — 현역 _desk 가 아닌 은퇴 좌석으로 간다
mutate m4 'seat["_desk"]@@sorted(v for k, v in seat.items() if "desk" in k)[0]'
reset
( cd "$ROOT" && FT_ROOT="$ROOT" FT_NOW="$NOW" FT_DESK_REPLY_LEDGER="$LEDGER" timeout $TO_LIMIT python3 "$TOOL" --register "$QTS" h54 "$SHA" ) >/dev/null
RUN_TOOL="$MUT/m4.py" run_tool >/dev/null 2>&1
if [ "$(cut -f1 "$SENT" 2>/dev/null)" = "$DESK" ]; then echo "  FAIL M4 — 정렬 첫 값으로 바꿨는데도 현역 _desk 로 갔다(시험이 약하다)"; fail=1; else echo "  OK   M4 수신자 = 정렬 첫 desk 값 → ⓑ «현역 _desk» 검사 FAIL(실제 $(cut -f1 "$SENT" 2>/dev/null))"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (ⓐ~ⓔ · 변이 M1~M4 · stall-scan 연결) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
