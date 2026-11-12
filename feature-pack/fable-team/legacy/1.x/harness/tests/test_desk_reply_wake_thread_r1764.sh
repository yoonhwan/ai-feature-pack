#!/usr/bin/env bash
# test_desk_reply_wake_thread_r1764.sh — r1764: desk 감시에 «스레드 새 글» 갈래(kind=thread · --after)와 «수동 닫기»(--close)가 붙는다
#   ① thread 줄 · 오빠 글 3개(t1<t2<t3) → 주기마다 1통(t1·t2·t3) · 4주기 0통 · 줄은 열린 채
#   ② ① 뒤 desk 글이 사이에 낌 → 창 안 끊김(오빠 글만 셈)
#   ③ thread 줄 끝 시각 경과 → closed expired · 쪽지 0통(조용한 만료)
#   ④ question 줄 --close <키> --reason pane → closed manual:pane · 24h 경과에도 쪽지 0통
#   ⑤ 없는 키 --close → rc3 1줄 · 장부 바이트 그대로
#   ⑥ 기존 길 그대로(--after 없는 --reply-only · SLACK-OK · h 줄 · question 줄 = 기존 2시험 rc0)
#   ⑦ 조회 rc2 → «판정 불가» 1줄 · notified_ts 그대로 · 알림 0통
#   ⑧ 열린 thread 줄이 상한(FT_DESK_REPLY_MAX=4)보다 많아도 <장부>.thread.cursor 순환으로 3주기 안에 5줄 모두 1회 이상 조회
#   ⑥ 에 --after 없는 길의 NoReply stderr 꼴(parent=<부모ts>)까지 본다(NG2)
#   변이 M1 --after 무시 · M2 알림 뒤 닫기 · M3 만료에 쪽지 · M4 --close 잠금 밖·없는 키 rc0 → 각각 잡힌다
#   격리: 임시 FT_ROOT·가짜 mbox(발신 기록)·가짜 replies(실 Slack 0)·가짜 시계 · 안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70; HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft_desk_reply_wake.py"; CHECK="$BIN/ft_oppa_slack_check.py"; THREAD="$BIN/ft_desk_reply_thread.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
NOW=1794401443; QTS=1794400000.100000; T1=1794400600.100000; T2=1794400700.100000; T3=1794400800.100000
DTS=1794400650.500000; KEY=r1764-desk; OPPA=U0AC2JF0M7D; DESKU=U0C9GRFHJ; DESK="byz-planner-desk-pi#127"; MASTER="byz-planner-master-pi#249"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"; SENT="$T/sent.tsv"; : > "$SENT"
printf '{"_master":"%s","_desk":"%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" "$2" "$4" >> "%s"\necho QUEUED\n' "$SENT" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\n[ -f "%s/replies.rc" ] && exit "$(cat "%s/replies.rc")"\ncat "%s/replies.json"\n' "$T" "$T" "$T" > "$T/replies.sh"
cat > "$T/replies5.py" <<'PY'  # ⑧ 전용: 문의한 ts 하나만 담은 스레드(오빠 글 0) + 조회 기록
import json, os, sys
open(sys.argv[1], "a", encoding="utf-8").write(os.environ.get("FT_SLACK_TS", "") + "\n")
json.dump({"ok": True, "messages": [{"ts": os.environ.get("FT_SLACK_TS", ""), "user": "U0C9GRFHJ", "text": "스레드 질문"}]}, sys.stdout, ensure_ascii=False)
PY
printf '#!/usr/bin/env bash\nexec python3 "%s/replies5.py" "%s/q8"\n' "$T" "$T" > "$T/replies5.sh"
mk_replies() {  # $1 = 추가 메시지 JSON 배열(부모 = desk 질문 글)
  REP_EXTRA="${1:-[]}" python3 - "$T/replies.json" "$QTS" <<'PY'
import json, os, sys
m = [{"ts": sys.argv[2], "user": "U0C9GRFHJ", "text": "스레드 질문 — r1764"}]
m += json.loads(os.environ["REP_EXTRA"])
json.dump({"ok": True, "messages": m}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
oppa() { printf '{"ts":"%s","user":"%s","text":"%s"}' "$1" "$OPPA" "$2"; }
desk() { printf '{"ts":"%s","user":"%s","text":"%s"}' "$1" "$DESKU" "$2"; }
three() { mk_replies "[$(oppa "$T1" "첫 새 글"),$(oppa "$T2" "둘째 새 글"),$(oppa "$T3" "셋째 새 글")]"; }
run() { ( cd "$ROOT" || exit 1
  export FT_ROOT="$ROOT" FT_NOW="${RUN_NOW:-$NOW}" FT_MBOX_SH="$T/mbox.sh" HIL_DIR="$T/hil" FT_SLACK_CHECK="$CHECK" \
         FT_SLACK_REPLIES_CMD="${RUN_REPLIES:-bash $T/replies.sh}" FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" FT_DESK_REPLY_LEDGER="$LEDGER"
  timeout $TO python3 "${RUN_TOOL:-$TOOL}" "$@" ); }
field() { python3 -c 'import json,sys;rows=[json.loads(x) for x in open(sys.argv[1],encoding="utf-8") if x.strip()];r=[x for x in rows if x.get("state")!="closed"] or rows;print((r[-1] if r else {}).get(sys.argv[2],"—"))' "$LEDGER" "$1" 2>/dev/null; }
sends() { wc -l < "$SENT" 2>/dev/null | tr -d ' ' || echo 0; }
lastbody() { tail -1 "$SENT" 2>/dev/null | cut -f2; }
reset() { rm -f "$LEDGER" "$LEDGER.cursor" "$LEDGER.thread.cursor"; : > "$SENT"; rm -f "$T/replies.rc"; }

echo "== ① thread_new_post_wakes_desk_once =="
three
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1; chk "① 등록 rc=0" 0 "$?"
chk "① 장부 1줄 · kind=thread · key" "1 thread $KEY" "$(wc -l < "$LEDGER" | tr -d ' ') $(field kind) $(field key)"
chk "① 끝 시각 = 등록 + 24h" "86400" "$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r["deadline"]-r["at"])' "$LEDGER")"
run >/dev/null 2>&1; chk "① 1주기 rc=0" 0 "$?"
chk "① 1주기 1통 · 받는이 = _desk" "1 $DESK" "$(sends) $(cut -f1 "$SENT")"
chk "① 1주기 본문 = 새 글 t1" "[오빠 새 글] $KEY ts=$T1" "$(lastbody)"
run >/dev/null 2>&1; chk "① 2주기 = t2 1통(같은 글 반복 0)" "2 [오빠 새 글] $KEY ts=$T2" "$(sends) $(lastbody)"
run >/dev/null 2>&1; chk "① 3주기 = t3 1통" "3 [오빠 새 글] $KEY ts=$T3" "$(sends) $(lastbody)"
run >/dev/null 2>&1; chk "① 4주기 = 0통" "3" "$(sends)"
chk "① 줄은 열린 채(닫힘 0)" "open —" "$(field state) $(field closed)"

echo "== ② desk 글 사이에 낌 → 창 안 끊김 =="
reset; mk_replies "[$(oppa "$T1" "첫 새 글"),$(desk "$DTS" "desk 보충 설명"),$(oppa "$T2" "둘째 새 글")]"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
run >/dev/null 2>&1; A2="$(lastbody)"
run >/dev/null 2>&1; chk "② desk 글 무시 · 2주기 = t2" "$T1|2|$T2" "$(printf '%s|%s|%s' "$(printf '%s' "$A2" | sed 's/.*ts=//')" "$(sends)" "$(lastbody | sed 's/.*ts=//')")"

echo "== ③ 끝 시각 경과 = 조용한 만료 =="
reset; three
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1; chk "③ 만료 주기 rc=0" 0 "$?"
chk "③ 쪽지 0통 · closed expired" "0 closed expired" "$(sends) $(field state) $(field closed)"

echo "== ④ question 줄 수동 닫기 =="
reset; mk_replies "[$(oppa "$T1" "좋아 진행")]"
: > "$SENT"; printf '{"q_ts":"1794400100.222222","kind":"question","key":"cfo-maint-card","at":%d,"deadline":%d,"state":"open"}\n' "$NOW" "$((NOW + 86400))" > "$LEDGER"
run --close cfo-maint-card --reason pane >/dev/null 2>&1; chk "④ --close rc=0" 0 "$?"
chk "④ closed manual:pane" "closed manual:pane" "$(field state) $(field closed)"
: > "$SENT"; RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1; chk "④ 24h 경과에도 쪽지 0통" "0" "$(sends)"

echo "== ⑤ 없는 키 --close =="
reset; printf '{"q_ts":"1794400200.333333","kind":"question","key":"r1764b","at":%d,"deadline":%d,"state":"open"}\n' "$NOW" "$((NOW + 86400))" > "$LEDGER"
cp "$LEDGER" "$T/ledger.before"
run --close no-such-key >"$T/o5" 2>"$T/e5"; chk "⑤ rc=3" 3 "$?"
chk "⑤ 1줄(장부 바이트 그대로)" "0 1" "$(cmp -s "$LEDGER" "$T/ledger.before" && echo 0 || echo 1) $(wc -l < "$T/e5" | tr -d ' ')"

echo "== ⑥ 기존 길 그대로 =="
reset; three
b() { ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/replies.sh" timeout $TO python3 "$CHECK" "$@" ); }
chk "⑥ --after 없는 --reply-only = REPLY-SEEN 1줄" "REPLY-SEEN parent=$QTS reply=$T1" "$(b --reply-only "$QTS" 2>/dev/null)"
chk "⑥ --after = 그 시각 뒤 첫 글" "REPLY-SEEN parent=$QTS reply=$T2" "$(b --reply-only "$QTS" --after "$T1" 2>/dev/null)"
chk "⑥ --after 가 맨 뒤면 새 글 없음 rc=3" 3 "$(b --reply-only "$QTS" --after "$T3" >/dev/null 2>&1; echo $?)"
chk "⑥ 새 글 없음 stderr = parent=<부모ts>(--reply-only 아님)" "REPLY-NONE parent=$QTS" "$(b --reply-only "$QTS" --after "$T3" 2>&1 >/dev/null | sed 's/ — .*//')"
for t in test_desk_reply_wake_r1574.sh test_desk_reply_wake_question_r1591.sh; do
  timeout $TO bash "$HERE/$t" >/dev/null 2>&1; chk "⑥ $t rc=0" 0 "$?"
done
for f in ft_desk_reply_wake.py ft_oppa_slack_check.py ft_desk_reply_thread.py; do
  cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && echo "  OK   cmp0 $f" || { echo "  FAIL cmp0 $f"; fail=1; }
done

echo "== ⑦ 조회 실패 = 판정 불가 =="
reset; three
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
B_TS="$(field notified_ts)"; echo 2 > "$T/replies.rc"
run >"$T/o7" 2>"$T/e7"; chk "⑦ 판정 불가 경로 rc=1" 1 "$?"
chk "⑦ «판정 불가» 1줄 · notified_ts 그대로 · 쪽지 0통" "1 — 0" "$(grep -c '판정 불가' "$T/e7") $B_TS $(sends)"
rm -f "$T/replies.rc"

echo "== ⑧ 열린 thread 줄이 상한(4)보다 많아도 순환해서 모두 본다 =="
reset; : > "$T/q8"
for i in 1 2 3 4 5; do run --register-thread "179440000$i.100000" "r1764-t$i" >/dev/null 2>&1; done
chk "⑧ thread 줄 5개 등록" "5" "$(wc -l < "$LEDGER" | tr -d ' ')"
for _ in 1 2 3; do RUN_REPLIES="bash $T/replies5.sh" run >/dev/null 2>&1; done
chk "⑧ 3주기 = 5줄 모두 1회 이상 조회(다섯째도 본다)" "5" "$(sort -u "$T/q8" | wc -l | tr -d ' ')"
chk "⑧ 새 글 없는 줄은 열린 채(쪽지 0)" "0 0" "$(grep -c '\"closed\"' "$LEDGER" || true) $(sends)"

mut() {  # $1 = 이름 · $2 = 파일 · $3 = 교체 스크립트(python heredoc 본문)  → $T/mut/$1 에 사본 3파일
  mkdir -p "$T/mut/$1"; cp "$TOOL" "$CHECK" "$THREAD" "$T/mut/$1"; python3 - "$T/mut/$1/$2" <<PY
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
$3
p.write_text(t, encoding="utf-8")
PY
}
echo "== 변이 M1 = --after 무시(첫 답글 고정) =="
reset; three
mut m1 ft_desk_reply_thread.py 'old = "\"--reply-only\", q, \"--after\", after]"
assert old in t
t = t.replace(old, "\"--reply-only\", q]", 1)'
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m1/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M1 1주기 = t1(정상)" "1 [오빠 새 글] $KEY ts=$T1" "$(sends) $(lastbody)"
RUN_TOOL="$T/mut/m1/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M1 2주기 = 0통(변이 적용) → ① «2주기 t2 1통» 검사가 잡는다" "1" "$(sends)"

echo "== 변이 M2 = 알림 뒤 줄 닫기 =="
reset; three
mut m2 ft_desk_reply_thread.py 'old = "up[q] = {\"notified_ts\": m.group(1), \"notified_at\": int(now)}"
assert old in t
t = t.replace(old, "up[q] = {\"notified_ts\": m.group(1), \"notified_at\": int(now), \"state\": \"closed\"}", 1)'
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m2/ft_desk_reply_wake.py" run >/dev/null 2>&1
RUN_TOOL="$T/mut/m2/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M2 2주기 = 0통(줄 닫힘) · 상태 closed → ① 검사가 잡는다" "1 closed" "$(sends) $(field state)"

echo "== 변이 M3 = 만료에 쪽지 =="
reset; three
mut m3 ft_desk_reply_thread.py 'old = "up[q] = {\"state\": \"closed\", \"closed\": \"expired\"}"
assert old in t
t = t.replace(old, "up[q] = {\"state\": \"closed\", \"closed\": \"expired\"}; h.send(h.base, h.seat.get(\"_desk\") or \"?\", \"[답글 없음 24시간] \" + key)", 1)'
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m3/ft_desk_reply_wake.py" RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1
chk "M3 만료에 쪽지 1통 → ③ «쪽지 0통» 검사가 잡는다" "1" "$(sends)"

echo "== 변이 M4 = --close 잠금 밖 쓰기·없는 키 rc0 =="
reset; printf '{"q_ts":"1794400200.333333","kind":"question","key":"r1764b","at":%d,"deadline":%d,"state":"open"}\n' "$NOW" "$((NOW + 86400))" > "$LEDGER"
mut m4 ft_desk_reply_thread.py 'old = "            print(\"감시 닫기 실패 — 열린 줄 없음: %s\" % tgt, file=sys.stderr)\n            return 3"
assert old in t
t = t.replace(old, "            print(\"닫힘 0줄 — %s\" % tgt)\n            return 0", 1)'
RUN_TOOL="$T/mut/m4/ft_desk_reply_wake.py" run --close no-such-key >/dev/null 2>&1
chk "M4 없는 키 rc=0 → ⑤ «rc=3» 검사가 잡는다" "0" "$?"

echo "== 변이 M5 = thread 순환 지움(앞 4줄 고정) =="
reset; : > "$T/q8"
mut m5 ft_desk_reply_thread.py 'old = "order = [i for i, _ in open_rows if i >= cur] + [i for i, _ in open_rows if i < cur]"
assert old in t
t = t.replace(old, "order = [i for i, _ in open_rows]", 1)'
for i in 1 2 3 4 5; do run --register-thread "179440000$i.100000" "r1764-t$i" >/dev/null 2>&1; done
for _ in 1 2 3; do RUN_TOOL="$T/mut/m5/ft_desk_reply_wake.py" RUN_REPLIES="bash $T/replies5.sh" run >/dev/null 2>&1; done
chk "M5 3주기 조회 = 4줄 → ⑧ «5줄 모두» 검사가 잡는다" "4" "$(sort -u "$T/q8" | wc -l | tr -d ' ')"

if [ "$fail" = 0 ]; then echo "ALL PASS (① ② ③ ④ ⑤ ⑥ ⑦ ⑧ · 변이 M1~M5 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
