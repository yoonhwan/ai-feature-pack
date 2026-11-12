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
#   ⑨ 같은 q_ts 의 closed question 줄이 있어도 thread 줄은 등록된다(충돌 검사 = kind=thread 줄만) · 같은 key 재등록 중복 0 · 다른 key thread = rc3
#   ⑪ thread 줄이 있는 ts 에도 --register-question·--register(h) 는 그 갈래대로(thread 줄은 충돌 아님)
#   ⑩ 스캔·--close 는 thread 줄만 건드린다(같은 ts question 줄 state·closed·notified_ts 불변) · 변이 M6(kind 검사 지움 → ⑨) · M7(장부 갱신 q_ts만 → ⑩)
#   ⑫ 등록 «전» 글만 있는 스레드 = 쪽지 0통(기준점 = 등록 시각 · notified_ts 로 박힌다) · 다음 주기에도 옛 글 재생 0
#   ⑬ 등록 «뒤» 새 글 1개 = 1통(ts=그 글) · 그 다음 주기 0통
#   ⑭ desk 가 닫은 thread 줄을 같은 키로 다시 등록 = «새 열린 줄»(감시 0 조용히 남지 않는다 · 새 기준점)
#   ⑮ 옛 줄(기준점 없음)은 그 줄의 등록 시각(at)을 기준점으로 채택(등록~첫 점검 사이 글 유실 0)
#   ⑥ 에 --after 없는 길의 NoReply stderr 꼴(parent=<부모ts>)까지 본다(NG2)
#   변이 M1 --after 무시 · M2 알림 뒤 닫기 · M3 만료에 쪽지 · M4 --close 잠금 밖·없는 키 rc0 · M8 기준점을 스레드 q_ts 로 되돌림 · M9 닫힌 줄도 «이미 등록» 으로 봄 → 각각 잡힌다
#   격리: 임시 FT_ROOT·가짜 mbox(발신 기록)·가짜 replies(실 Slack 0)·가짜 시계 · 안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70; HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft_desk_reply_wake.py"; CHECK="$BIN/ft_oppa_slack_check.py"; THREAD="$BIN/ft_desk_reply_thread.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
NOW=1794400100; QTS=1794400000.100000; T1=1794400600.100000; T2=1794400700.100000; T3=1794400800.100000
DTS=1794400650.500000; O1=1794400020.100000; O2=1794400040.200000; N1=1794400160.600000; KEY=r1764-desk; OPPA=U0AC2JF0M7D; DESKU=U0C9GRFHJ; DESK="byz-planner-desk-pi#127"; MASTER="byz-planner-master-pi#249"
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
qstate() { python3 -c 'import json,sys;r=[json.loads(x) for x in open(sys.argv[1],encoding="utf-8") if x.strip()];q=([x for x in r if x.get("kind")!="thread"] or [{}])[0];print("%s:%s:%s"%(q.get("state","—"),q.get("closed") or "",q.get("notified_ts","")))' "$LEDGER"; }
tstate() { python3 -c 'import json,sys;r=[json.loads(x) for x in open(sys.argv[1],encoding="utf-8") if x.strip()];q=([x for x in r if x.get("kind")=="thread"] or [{}])[0];print("%s:%s:%s"%(q.get("state","—"),q.get("closed") or "",q.get("notified_ts","")))' "$LEDGER"; }
lastbody() { tail -1 "$SENT" 2>/dev/null | cut -f2; }
nopen() { python3 -c 'import json,sys;print(sum(1 for x in (json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()) if x.get("kind")=="thread" and x.get("state")!="closed"))' "$LEDGER"; }
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
chk "⑦ «판정 불가» 1줄 · notified_ts 그대로 · 쪽지 0통" "1 0 $B_TS" "$(grep -c '판정 불가' "$T/e7") $(sends) $(field notified_ts)"
rm -f "$T/replies.rc"

echo "== ⑧ 열린 thread 줄이 상한(4)보다 많아도 순환해서 모두 본다 =="
reset; : > "$T/q8"
for i in 1 2 3 4 5; do run --register-thread "179440000$i.100000" "r1764-t$i" >/dev/null 2>&1; done
chk "⑧ thread 줄 5개 등록" "5" "$(wc -l < "$LEDGER" | tr -d ' ')"
for _ in 1 2 3; do RUN_REPLIES="bash $T/replies5.sh" run >/dev/null 2>&1; done
chk "⑧ 3주기 = 5줄 모두 1회 이상 조회(다섯째도 본다)" "5" "$(sort -u "$T/q8" | wc -l | tr -d ' ')"
chk "⑧ 새 글 없는 줄은 열린 채(쪽지 0)" "0 0" "$(grep -c '\"closed\"' "$LEDGER" || true) $(sends)"

echo "== ⑨ 같은 ts 의 closed question 줄이 있어도 thread 줄은 등록된다 =="
reset; : > "$SENT"
printf '{"q_ts":"%s","kind":"question","key":"cfo-survey-turnkey","at":%d,"deadline":%d,"state":"closed","closed":"replied"}\n' "$QTS" "$NOW" "$((NOW + 86400))" > "$LEDGER"
run --register-thread "$QTS" "$KEY" >"$T/o9" 2>"$T/e9"; chk "⑨ 등록 rc=0(closed question 줄에 막히지 않는다)" 0 "$?"
chk "⑨ 장부 2줄 · thread 줄 open" "2 open" "$(wc -l < "$LEDGER" | tr -d ' ') $(tstate | cut -d: -f1)"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1; R9=$?; chk "⑨ 같은 key 재등록 = rc0 · 줄 안 늘어남" "0 2" "$R9 $(wc -l < "$LEDGER" | tr -d ' ')"
run --register-thread "$QTS" r1764-other >/dev/null 2>&1; chk "⑨ 다른 key thread 같은 ts = rc3(그대로)" 3 "$?"

echo "== ⑩ 스캔·--close 는 thread 줄만 건드린다 =="
three
run >/dev/null 2>&1; chk "⑩ 스캔 1통 = [오빠 새 글]" "1 [오빠 새 글] $KEY ts=$T1" "$(sends) $(lastbody)"
chk "⑩ question 줄(closed replied) 불변 · notified_ts 안 붙음" "closed:replied:" "$(qstate)"
chk "⑩ thread 줄은 열린 채 notified_ts=t1" "open::$T1" "$(tstate)"
run --close "$KEY" --reason pane >/dev/null 2>&1; chk "⑩ --close 사유키는 thread 줄만(question 줄 그대로)" "closed:manual:pane:$T1 / closed:replied:" "$(tstate) / $(qstate)"

echo "== ⑪ thread 줄이 있는 ts 에도 질문·h 등록은 그 갈래대로 된다 =="
reset; run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
run --register-question "$QTS" r1764-q >/dev/null 2>&1; chk "⑪ --register-question 같은 ts = rc0(thread 줄에 안 막힘)" 0 "$?"
reset; run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
run --register "$QTS" h77 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; chk "⑪ --register(h) 같은 ts = rc0(thread 줄에 안 막힘)" 0 "$?"

echo "== ⑫ 등록 전 옛 글은 알림 0통(기준점 = 등록 시각) =="
reset; mk_replies "[$(oppa "$O1" "등록 전 옛 글 1"),$(oppa "$O2" "등록 전 옛 글 2")]"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1; chk "⑫ 등록 rc=0" 0 "$?"
chk "⑫ 줄에 기준점(등록 시각)이 박힌다" "$NOW.000000" "$(field notified_ts)"
run >/dev/null 2>&1; chk "⑫ 1주기 = 옛 글 2개 무시 쪽지 0통" 0 "$(sends)"
run >/dev/null 2>&1; chk "⑫ 2주기 = 옛 글 재생 0통" "0 open" "$(sends) $(field state)"

run >/dev/null 2>&1
echo "== ⑬ 등록 뒤 새 글 1개 = 1통 =="
reset; mk_replies "[$(oppa "$N1" "등록 뒤 새 글")]"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
run >/dev/null 2>&1; chk "⑬ 1주기 = 새 글 1통(받는이 _desk)" "1 $DESK" "$(sends) $(cut -f1 "$SENT")"
chk "⑬ 본문 = 새 글 ts · 줄은 열린 채" "[오빠 새 글] $KEY ts=$N1 open::$N1" "$(lastbody) $(tstate)"
run >/dev/null 2>&1; chk "⑬ 2주기 = 같은 글 반복 0통" 1 "$(sends)"

echo "== ⑭ 닫힌 thread 줄 재등록 = 새 열린 줄(감시 0 조용히 남지 않는다) =="
reset; mk_replies "[$(oppa "$O1" "등록 전 옛 글 1"),$(oppa "$O2" "등록 전 옛 글 2")]"
printf '{"q_ts":"%s","kind":"thread","key":"%s","at":%d,"deadline":%d,"state":"closed","closed":"manual:old-post-notify","notified_ts":"%s"}\n' "$QTS" "$KEY" "$NOW" "$((NOW + 86400))" "$QTS" > "$LEDGER"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1; chk "⑭ 닫힌 줄 재등록 rc=0" 0 "$?"
chk "⑭ 장부 2줄 · 열린 thread 1줄(새 줄)" "2 1" "$(wc -l < "$LEDGER" | tr -d ' ') $(nopen)"
chk "⑭ 새 줄 기준점 = 등록 시각(옛 기준점 아님)" "$NOW.000000" "$(field notified_ts)"
run >/dev/null 2>&1; chk "⑭ 첫 점검 = 옛 글 0통" 0 "$(sends)"
run >/dev/null 2>&1; chk "⑭ 다음 주기도 0통 · 열린 채" "0 open" "$(sends) $(field state)"

echo "== ⑮ 옛 줄(기준점 없음)은 그 줄의 등록 시각을 기준점으로 채택 =="
reset; mk_replies "[$(oppa "$O1" "등록 전 옛 글 1"),$(oppa "$O2" "등록 전 옛 글 2")]"
printf '{"q_ts":"%s","kind":"thread","key":"%s","at":%d,"deadline":%d,"state":"open"}\n' "$QTS" "$KEY" "$((NOW - 200))" "$((NOW + 86400))" > "$LEDGER"
run >/dev/null 2>&1; chk "⑮ at 뒤 첫 글 1통(«지금» 채택이면 0통)" "1 [오빠 새 글] $KEY ts=$O1" "$(sends) $(lastbody)"
run >/dev/null 2>&1; chk "⑮ 다음 주기 = 다음 글 1통(중복 0)" "2 [오빠 새 글] $KEY ts=$O2" "$(sends) $(lastbody)"

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
mut m2 ft_desk_reply_thread.py 'old = "up[rowkey(q)] = {\"notified_ts\": m.group(1), \"notified_at\": int(now)}"
assert old in t
t = t.replace(old, "up[rowkey(q)] = {\"notified_ts\": m.group(1), \"notified_at\": int(now), \"state\": \"closed\"}", 1)'
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m2/ft_desk_reply_wake.py" run >/dev/null 2>&1
RUN_TOOL="$T/mut/m2/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M2 2주기 = 0통(줄 닫힘) · 상태 closed → ① 검사가 잡는다" "1 closed" "$(sends) $(field state)"

echo "== 변이 M3 = 만료에 쪽지 =="
reset; three
mut m3 ft_desk_reply_thread.py 'old = "up[rowkey(q)] = {\"state\": \"closed\", \"closed\": \"expired\"}"
assert old in t
t = t.replace(old, "up[rowkey(q)] = {\"state\": \"closed\", \"closed\": \"expired\"}; h.send(h.base, h.seat.get(\"_desk\") or \"?\", \"[답글 없음 24시간] \" + key)", 1)'
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

echo "== 변이 M6 = 충돌 검사를 kind·state 무관(q_ts 만) =="
reset; : > "$SENT"
printf '{"q_ts":"%s","kind":"question","key":"cfo-survey-turnkey","at":%d,"deadline":%d,"state":"closed","closed":"replied"}\n' "$QTS" "$NOW" "$((NOW + 86400))" > "$LEDGER"
mut m6 ft_desk_reply_thread.py 'old = "r.get(\"q_ts\") == row[\"q_ts\"] and r.get(\"kind\") == \"thread\" and r.get(\"state\") != \"closed\""
assert old in t
t = t.replace(old, "r.get(\"q_ts\") == row[\"q_ts\"]", 1)'
RUN_TOOL="$T/mut/m6/ft_desk_reply_wake.py" run --register-thread "$QTS" "$KEY" >/dev/null 2>&1; R6=$?
chk "M6 같은 ts 등록 rc=3 → ⑨ «rc=0» 검사가 잡는다" "3" "$R6"

echo "== 변이 M7 = 장부 갱신을 q_ts 로만 고름(thread↔question 섬임) =="
reset; : > "$SENT"; three
printf '{"q_ts":"%s","kind":"question","key":"cfo-survey-turnkey","at":%d,"deadline":%d,"state":"closed","closed":"replied"}\n' "$QTS" "$NOW" "$((NOW + 86400))" > "$LEDGER"
run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
mut m7 ft_desk_reply_wake.py 'old = "            u = up.get(rowkey(r)) or up.get(r.get(\"q_ts\"))"
assert old in t
t = t.replace(old, "            u = up.get((\"thread\", r.get(\"q_ts\"))) or up.get(r.get(\"q_ts\"))", 1)'
RUN_TOOL="$T/mut/m7/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M7 question 줄에 notified_ts 가 붙음 → ⑩ «불변» 검사가 잡는다" "closed:replied:$T1" "$(qstate)"

echo "== 변이 M8 = 기준점을 스레드 q_ts 로 되돌림(옛 글 재생) =="
reset; mk_replies "[$(oppa "$O1" "등록 전 옛 글 1"),$(oppa "$O2" "등록 전 옛 글 2")]"
mut m8 ft_desk_reply_thread.py 'old = "\"notified_ts\": \"%.6f\" % now"
assert old in t
t = t.replace(old, "\"notified_ts\": a[0] if a else \"\"", 1)'
RUN_TOOL="$T/mut/m8/ft_desk_reply_wake.py" run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m8/ft_desk_reply_wake.py" run >/dev/null 2>&1
chk "M8 옛 글 1통 → ⑫ «0통» 검사가 잡는다" 1 "$(sends)"

echo "== 변이 M9 = 닫힌 줄도 «이미 등록» 으로 봄 =="
reset; mk_replies "[$(oppa "$O1" "등록 전 옛 글 1")]"
printf '{"q_ts":"%s","kind":"thread","key":"%s","at":%d,"deadline":%d,"state":"closed","closed":"manual:old-post-notify"}\n' "$QTS" "$KEY" "$NOW" "$((NOW + 86400))" > "$LEDGER"
mut m9 ft_desk_reply_thread.py 'old = " and r.get(\"state\") != \"closed\""
assert old in t
t = t.replace(old, "", 1)'
RUN_TOOL="$T/mut/m9/ft_desk_reply_wake.py" run --register-thread "$QTS" "$KEY" >/dev/null 2>&1
chk "M9 재등록이 «이미 등록» rc0 · 열린 줄 0 → ⑭ «열린 thread 1줄» 검사가 잡는다" "0" "$(nopen)"

if [ "$fail" = 0 ]; then echo "ALL PASS (① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮ · 변이 M1~M9 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
