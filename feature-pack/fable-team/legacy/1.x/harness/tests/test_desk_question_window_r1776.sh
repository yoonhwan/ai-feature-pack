#!/usr/bin/env bash
# test_desk_question_window_r1776.sh — r1776: desk 질문 감시가 다음 질문 앞에서 창을 끊고(--stop-at) · 오빠 새 글은 알림만 · 줄은 --close 로 닫는다
#   ① 한 스레드 Q1→Q2→오빠 U(무관)→오빠 A2 · scan 1회 = Q1 알림 0 · Q2 = U 1통 · 두 줄 열림
#   ② 이어서 scan 1회 = Q2 = A2 1통(--after U) · Q1 0 · 두 줄 열림
#   ③ 실사건: Q · U · A → scan 2회 = 2통(U·A) · --close gcloud-relogin 뒤 scan = 0통 · closed manual:cli
#   ④ notified 질문 줄 끝 시각 경과 = 쪽지 0 · closed timeout-notified / open 질문 줄 경과 = [답글 없음 24시간] 1통 · closed timeout
#   ⑤ desk 정정 글(장부에 없는 ts)이 Q 와 오빠 답 사이 = 창 안 끊김 · 다른 스레드 질문 ts(장부에 있음)도 경계 아님 · 1통
#   ⑥ --stop-at·--after 순서 무관 · --stop-at 없는 길 = 기존 출력 · 승인 길(sha)+--stop-at = rc2 usage · SLACK-OK 0
#   변이(사본에서만 · 변이마다 원본 같은 사례 1회 더): M1 --stop-at 무시→① · M2 --after 빠짐→② · M3 REPLY-SEEN 닫음→③ · M4 notified 경과에도 24h 쪽지→④ · M5 같은 작성자 글로 끊기→⑤
#   격리: 임시 FT_ROOT·가짜 mbox(발신 기록)·가짜 replies(FT_SLACK_TS 별 JSON · 실 Slack 0)·FT_NOW 고정 · sleep 0 · 안전선(r1041): ulimit -u+64 · timeout 70
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70; HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft_desk_reply_wake.py"; CHECK="$BIN/ft_oppa_slack_check.py"; THREAD="$BIN/ft_desk_reply_thread.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
NOW=1794500100; OPPA=U0AC2JF0M7D; DESKU=U0C9GRFHJ; DESK="byz-planner-desk-pi#127"; MASTER="byz-planner-master-pi#249"
R=1794500000.000001; Q1=1794500010.100000; Q2=1794500020.200000; U=1794500030.300000; A2=1794500040.400000
C=1794500015.500000; QX=1794500025.600000; SHA=0123456789abcdef0123456789abcdef01234567
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"; SENT="$T/sent.tsv"; : > "$SENT"
printf '{"_master":"%s","_desk":"%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" "$2" "$4" >> "%s"\necho QUEUED\n' "$SENT" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\nf="%s/rep-$FT_SLACK_TS.json"; [ -f "$f" ] || f="%s/rep.json"; cat "$f"\n' "$T" "$T" > "$T/replies.sh"
cat > "$T/thread.py" <<'PY'
import json, sys
rows = [l.rstrip("\n").split("|", 2) for l in sys.stdin if l.strip()]
root = rows[0][0]
m = [{"ts": t, "user": u, "text": x} | ({} if t == root else {"thread_ts": root}) for t, u, x in rows]
json.dump({"ok": True, "messages": m}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
thread() { python3 "$T/thread.py" "$T/$1.json"; }  # $1 = 파일(rep 또는 rep-<ts>) · stdin 줄 = ts|user|text · 첫 줄 = 루트
qrow() { printf '{"q_ts":"%s","kind":"question","key":"%s","at":%d,"deadline":%d,"state":"%s"%s}\n' "$1" "$2" "$NOW" "${4:-$((NOW + 86400))}" "${3:-open}" "${5:-}"; }
run() { ( cd "$ROOT" || exit 1
  export FT_ROOT="$ROOT" FT_NOW="${RUN_NOW:-$NOW}" FT_MBOX_SH="$T/mbox.sh" HIL_DIR="$T/hil" FT_SLACK_CHECK="${RUN_CHECK:-$CHECK}" \
         FT_SLACK_REPLIES_CMD="bash $T/replies.sh" FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" FT_DESK_REPLY_LEDGER="$LEDGER"
  timeout $TO python3 "${RUN_TOOL:-$TOOL}" "$@" ); }
b() { ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/replies.sh" timeout $TO python3 "${RUN_CHECK:-$CHECK}" "$@" ); }
st() { python3 -c 'import json,sys;r={x["key"]:x for x in (json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip())}[sys.argv[2]];print("%s:%s"%(r.get("state"),r.get("closed") or ""))' "$LEDGER" "$1" 2>/dev/null || echo err; }
sends() { wc -l < "$SENT" | tr -d ' '; }
bodies() { cut -f2 "$SENT" | sed 's/ → .*//' | tr '\n' '|'; }
reset() { rm -f "$T"/rep*.json "$LEDGER" "$LEDGER.cursor" "$LEDGER.thread.cursor"; : > "$SENT"; }

# 사례 = 함수 1개 → 결과 1줄(원본·변이가 같은 함수를 쓴다)
c1() { reset
  thread rep <<EOF
$R|$DESKU|CFO 스레드
$Q1|$DESKU|[질문] gcloud 재로그인 해 주실 수 있나요
$Q2|$DESKU|[질문] DA 판정 올려도 되나요
$U|$OPPA|DA 요청: 이거 먼저 봐줘
$A2|$OPPA|네 올려
EOF
  { qrow "$Q1" q1-key; qrow "$Q2" q2-key; } > "$LEDGER"
  run >/dev/null 2>&1; echo "$(sends) $(bodies) $(st q1-key) $(st q2-key)"; }
E1="1 [오빠 새 글] q2-key ts=$U| open: notified:"
c2() { c1 >/dev/null; : > "$SENT"; run >/dev/null 2>&1; echo "$(sends) $(bodies) $(st q1-key) $(st q2-key)"; }
E2="1 [오빠 새 글] q2-key ts=$A2| open: notified:"
c3() { reset
  thread rep <<EOF
$Q1|$DESKU|[질문] gcloud 재로그인 부탁드립니다
$U|$OPPA|DA 요청: r1770 봐줘
$A2|$OPPA|로그인완료
EOF
  qrow "$Q1" gcloud-relogin > "$LEDGER"
  run >/dev/null 2>&1; run >/dev/null 2>&1; local n2; n2="$(sends) $(bodies) $(st gcloud-relogin)"
  run --close gcloud-relogin >/dev/null 2>&1; run >/dev/null 2>&1; echo "$n2 / $(sends) $(st gcloud-relogin)"; }
E3="2 [오빠 새 글] gcloud-relogin ts=$U|[오빠 새 글] gcloud-relogin ts=$A2| notified: / 2 closed:manual:cli"
c4() { reset; thread rep <<EOF
$Q1|$DESKU|[질문] 하나
EOF
  { qrow "$Q1" n-key notified "$NOW" ",\"notified_ts\":\"$U\""; qrow "$Q2" o-key open "$NOW"; } > "$LEDGER"
  RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1; echo "$(sends) $(bodies) $(st n-key) $(st o-key)"; }
E4="1 [답글 없음 24시간] o-key ts=$Q2| closed:timeout-notified closed:timeout"
c5() { reset
  thread rep <<EOF
$Q1|$DESKU|[질문] 배포 창 열어도 되나요
$C|$DESKU|정정: 위 질문의 창은 내일 아침 기준
$A2|$OPPA|응 열어
EOF
  thread "rep-$QX" <<EOF
$QX|$DESKU|[질문] 다른 스레드 질문
EOF
  { qrow "$Q1" q-key; qrow "$QX" x-key; } > "$LEDGER"
  run >/dev/null 2>&1; echo "$(sends) $(bodies) $(st q-key) $(st x-key)"; }
E5="1 [오빠 새 글] q-key ts=$A2| notified: open:"

echo "== ① 한 스레드 질문 2개 + 무관 글 =="
chk "① Q1 0통 · Q2 = U 1통(받는이 _master) · 두 줄 열림" "$E1" "$(c1)"
chk "① 받는이 = _master · 본문 끝 = 원문 확인·--close 안내" "$MASTER	[오빠 새 글] q2-key ts=$U → 원문 확인 · 답이면 --close q2-key" "$(cat "$SENT")"
echo "== ② 이어지는 scan = --after =="
chk "② Q2 = A2 1통 · Q1 0통 · 두 줄 열림" "$E2" "$(c2)"
echo "== ③ 실사건 재연(gcloud-relogin) =="
chk "③ 2통(U·A) · --close 뒤 0통 · closed manual:cli" "$E3" "$(c3)"
echo "== ④ 끝 시각 =="
chk "④ notified = 쪽지 0 · timeout-notified / open = 24h 1통 · timeout" "$E4" "$(c4)"
echo "== ⑤ desk 정정 글·다른 스레드 질문 ts = 경계 아님 =="
chk "⑤ 창 안 끊김 · A 1통" "$E5" "$(c5)"

echo "== ⑥ 파서 =="
c1 >/dev/null
chk "⑥ --stop-at 없는 길 = 기존 출력(첫 오빠 글)" "REPLY-SEEN parent=$Q1 reply=$U" "$(b --reply-only "$Q1" 2>/dev/null)"
chk "⑥ --stop-at Q2 = 창 안 오빠 글 0 → rc3" 3 "$(b --reply-only "$Q1" --stop-at "$Q2" >/dev/null 2>&1; echo $?)"
chk "⑥ --after 뒤 --stop-at(앞선 ts 는 무시)" "REPLY-SEEN parent=$Q2 reply=$A2" "$(b --reply-only "$Q2" --after "$U" --stop-at "$Q1" 2>/dev/null)"
chk "⑥ --stop-at 뒤 --after(순서 무관)" "REPLY-SEEN parent=$Q2 reply=$A2" "$(b --reply-only "$Q2" --stop-at "$Q1,$QX" --after "$U" 2>/dev/null)"
reset; thread rep <<EOF
$Q1|$DESKU|[질문] PR 승인? head $SHA
$U|$OPPA|네
EOF
O6="$(b "$Q1" "$SHA" --stop-at "$Q2" 2>"$T/e6")"; R6=$?
chk "⑥ 승인 길 + --stop-at = rc2 · SLACK-OK 0 · usage" "2 0 1" "$R6 $(printf '%s' "$O6" | grep -c SLACK-OK) $(grep -c usage "$T/e6")"
chk "⑥ 승인 길(--stop-at 없음)은 그대로 SLACK-OK" "SLACK-OK $SHA parent=$Q1 reply=$U" "$(b "$Q1" "$SHA" 2>/dev/null)"
for f in ft_desk_reply_wake.py ft_oppa_slack_check.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && echo "  OK   cmp0 $f" || { echo "  FAIL cmp0 $f"; fail=1; }; done

echo "== 변이(사본에서만 · 원본 대조) =="
mut() {  # $1 이름 · $2 파일 · $3 원문 · $4 바꿀 글 → $T/mut/$1 에 bin 사본 3파일
  mkdir -p "$T/mut/$1"; cp "$TOOL" "$CHECK" "$THREAD" "$T/mut/$1/"
  python3 - "$T/mut/$1/$2" "$3" "$4" <<'PY' || echo "  FAIL $1 변이 대상 없음"
import pathlib, sys
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
t = p.read_text(encoding="utf-8")
assert old in t, old
p.write_text(t.replace(old, new, 1), encoding="utf-8")
PY
}
mcase() {  # $1 이름 · $2 사례 함수 · $3 기대(원본)
  local got orig; got="$(RUN_TOOL="$T/mut/$1/ft_desk_reply_wake.py" RUN_CHECK="$T/mut/$1/ft_oppa_slack_check.py" $2)"; orig="$($2)"
  if [ "$got" != "$3" ] && [ "$orig" = "$3" ]; then echo "  OK   $1 → $2 FAIL(변이 «${got}») · 원본 PASS"; else echo "  FAIL $1 검출 실패 — 변이[${got}] 원본[${orig}]"; fail=1; fi; }
mut M1 ft_oppa_slack_check.py 'brk = sorted(x for x in stops if x > parent and x in seen)' 'brk = []'
mcase M1 c1 "$E1"
mut M2 ft_desk_reply_wake.py ' + (["--after", row["notified_ts"]] if row.get("notified_ts") else [])' ''
mcase M2 c2 "$E2"
mut M3 ft_desk_reply_wake.py '"state": "notified"}  # r1776' '"state": "closed", "closed": "replied"}  # r1776'
mcase M3 c3 "$E3"
mut M4 ft_desk_reply_wake.py 'if qn and row.get("state") == "notified":' 'if False:'
mcase M4 c4 "$E4"
mut M5 ft_oppa_slack_check.py 'brk = sorted(x for x in stops if x > parent and x in seen)' 'brk = [x for x, txt in mine if x > parent]'
mcase M5 c5 "$E5"

if [ "$fail" = 0 ]; then echo "ALL PASS (①~⑥ · 변이 M1~M5 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄 — ${SECONDS}s"; exit 1
