#!/usr/bin/env bash
# test_desk_reply_wake_question_r1591.sh — h·sha 칸이 없는 오빠 질문(설계 승인 등)도 답글 감시 장부에 등록되고, 답글이 오면 planner master 1통(승인 판정 0)
#   ⓐ question_row_wakes_planner_once: --register-question <질문ts> r1590 = 장부 1줄(kind=question · h·sha 없음 · +24h) → scan = _master 1통 · 같은 답글 0통 · 24h = closed
#   ⓑ question_mode_never_prints_slack_ok: --reply-only = REPLY-SEEN 1줄(rc0) · 답글 없음 rc3 · SLACK-OK 0줄 · 기존 2인자 승인 길 rc=2 불변
#   ⓒ 기존 4시험 rc0 불변 · kit 사본 cmp0 · M1 = 질문 줄 수신자를 _desk 로 → ⓐ «받는이=_master» 검사가 잡는다
#   격리: 임시 FT_ROOT·가짜 mbox(발신 기록)·가짜 replies(실 Slack 0)·가짜 시계 · 안전선(r1041): ulimit -u+64 · timeout 70 · 자기 재호출 0
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000); ulimit -u $((NPROC + 64)) 2>/dev/null || true
TO=70; HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft_desk_reply_wake.py"; CHECK="$BIN/ft_oppa_slack_check.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
NOW=1794301443; QTS=1794300200.123456; RTS=1794300260.654321; KEY=r1590; DESK="byz-planner-desk-pi#127"; MASTER="byz-planner-master-pi#249"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"; SENT="$T/sent.tsv"; : > "$SENT"
printf '{"_master":"%s","_desk":"%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" "$2" "$4" >> "%s"\necho QUEUED\n' "$SENT" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$T/replies.json" > "$T/replies.sh"
mk_replies() {  # [답글ts] — 빈 인자면 오빠 답글 없음
  python3 - "$T/replies.json" "${1-$RTS}" "$QTS" <<'PY'
import json, sys
m = [{"ts": sys.argv[3], "user": "U0C9GRFHJ", "text": "설계 승인 부탁드립니다 — r1590 카드"}]
sys.argv[2] and m.append({"ts": sys.argv[2], "user": "U0AC2JF0M7D", "text": "좋아 진행"})
json.dump({"ok": True, "messages": m}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
mk_replies
run() { ( cd "$ROOT" || exit 1
  export FT_ROOT="$ROOT" FT_NOW="${RUN_NOW:-$NOW}" FT_MBOX_SH="$T/mbox.sh" HIL_DIR="$T/hil" FT_SLACK_CHECK="$CHECK" \
         FT_SLACK_REPLIES_CMD="bash $T/replies.sh" FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" FT_DESK_REPLY_LEDGER="$LEDGER"
  timeout $TO python3 "${RUN_TOOL:-$TOOL}" "$@" ); }
field() { python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r.get(sys.argv[2],"—"))' "$LEDGER" "$1" 2>/dev/null; }
sends() { wc -l < "$SENT" 2>/dev/null | tr -d ' ' || echo 0; }

echo "== ⓐ question_row_wakes_planner_once =="
run --register-question "$QTS" "$KEY" >/dev/null 2>&1; chk "ⓐ 등록 rc=0" 0 "$?"
chk "ⓐ 장부 1줄 · kind=question · key=r1590 · h·sha 칸 없음" "1 question r1590 — —" "$(wc -l < "$LEDGER" | tr -d ' ') $(field kind) $(field key) $(field h) $(field sha)"
chk "ⓐ 끝 시각 = 등록 + 24h" "86400" "$(python3 -c 'import json,sys;r=json.loads(open(sys.argv[1],encoding="utf-8").readline());print(r["deadline"]-r["at"])' "$LEDGER")"
run >/dev/null 2>&1; chk "ⓐ scan rc=0" 0 "$?"
chk "ⓐ 쪽지 1통 · 받는이 = _master(desk 아님)" "1 $MASTER" "$(sends) $(cut -f1 "$SENT")"
chk "ⓐ 본문 = «[오빠 새 글] r1590 ts=<답글> → 원문 확인 · 답이면 --close r1590»(r1776 A3)" "[오빠 새 글] $KEY ts=$RTS → 원문 확인 · 답이면 --close $KEY" "$(cut -f2 "$SENT")"
run >/dev/null 2>&1; chk "ⓐ 같은 답글 두 번째 주기 0통" 1 "$(sends)"
RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1; chk "ⓐ 알림 뒤 24h = 조용히 닫힘(r1776 A4ⓑ) · 오알림 0통" "1 closed timeout-notified" "$(sends) $(field state) $(field closed)"
: > "$SENT"; printf '{"q_ts":"1794300500.111111","kind":"question","key":"r1591b","at":%d,"deadline":%d,"state":"open"}\n' "$NOW" "$NOW" > "$LEDGER"
RUN_NOW=$((NOW + 86401)) run >/dev/null 2>&1; chk "ⓐ 미응답 24h = master 1통 · 닫힘(timeout 동결)" "1 closed timeout" "$(sends) $(field state) $(field closed)"

echo "== ⓑ question_mode_never_prints_slack_ok =="
b() { ( cd "$ROOT" && FT_SLACK_REPLIES_CMD="bash $T/replies.sh" timeout $TO python3 "$CHECK" "$@" ); }
OUTB="$(b --reply-only "$QTS" 2>"$T/err-b")"; chk "ⓑ 답글 있음 rc=0" 0 "$?"
chk "ⓑ 출력 = REPLY-SEEN 1줄" "REPLY-SEEN parent=$QTS reply=$RTS" "$OUTB"
chk "ⓑ 답글 있음 = SLACK-OK 0줄" "0" "$(printf '%s' "$OUTB" | grep -c SLACK-OK)"
mk_replies ""
b --reply-only "$QTS" >"$T/b2" 2>&1; chk "ⓑ 답글 없음 rc=3(판정 불가 2 아님)" 3 "$?"
chk "ⓑ 답글 없음 = SLACK-OK 0줄" "0" "$(grep -c SLACK-OK "$T/b2")"
mk_replies
b "$QTS" 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; chk "ⓑ 기존 승인 길 rc=2 불변" 2 "$?"

echo "== ⓒ 기존 시험 rc 불변 =="
for t in test_desk_reply_wake_r1574.sh test_hil_register_reply_wait_r1587.sh test_hil_oppa_thread_r1275.sh test_hil_oppa_only_r1275.sh; do
  timeout $TO bash "$HERE/$t" >/dev/null 2>&1; chk "ⓒ $t rc=0" 0 "$?"
done
for f in ft_desk_reply_wake.py ft_oppa_slack_check.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && echo "  OK   cmp0 $f" || { echo "  FAIL cmp0 $f"; fail=1; }; done

echo "== 변이 M1 = 질문 줄 수신자를 _desk 로 =="
mkdir -p "$T/mut"; cp "$TOOL" "$T/mut/m1.py"
python3 - "$T/mut/m1.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
old = 'tgt = seat.get("_master") if qn else (seat["_desk"] if "_desk" in seat else None)'
assert old in t
p.write_text(t.replace(old, 'tgt = seat.get("_desk")', 1), encoding="utf-8")
PY
rm -f "$LEDGER"; : > "$SENT"
run --register-question "$QTS" "$KEY" >/dev/null 2>&1
RUN_TOOL="$T/mut/m1.py" run >/dev/null 2>&1
if [ "$(cut -f1 "$SENT")" = "$MASTER" ]; then echo "  FAIL M1 — _desk 로 바꿨는데도 _master(시험이 약하다)"; fail=1; else echo "  OK   M1 수신자 _desk → ⓐ «받는이=_master» 검사 FAIL(실제 $(cut -f1 "$SENT"))"; fi

if [ "$fail" = 0 ]; then echo "ALL PASS (ⓐ ⓑ ⓒ · 변이 M1 · kit cmp0) — ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
