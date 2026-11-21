#!/usr/bin/env bash
# test_desk_reply_reask_r2389.sh — 오빠 질문 장부 «다시 묻기» (r2389 K7 · 반례 ⑭~⑰ · 변이 M10~M12).
#   ⑭ 7시간 답 0 = _desk 1통 + reask_at · 바로 다시 = 0통 · 5시간 = 0통 · 답글 있음 = 0통
#   ⑮ 마감(24h) 지난 줄 = 기준판 닫기 그대로(닫힘 timeout + _master 1통) · 다시 묻기 0
#      (카드 ⑮ «마감 지난 줄도 다시 묻기» 는 r1574 ⓒ «닫힌 줄은 다시 알리지 않는다» · r1591 ⓐ «미응답 24h = 1통» 과
#       정면으로 부딪혀 넣지 않았다 — DA 판정 자리. 충돌 기록은 PR 본문에 있다.)
#   ⑯ 등록 0 인 [HIL] 대기 = «[다시 묻기] 등록 없는 오빠 대기» 1통 · 6시간 안 다시 0 ⑰ 발신 실패 = reask_at 안 씀 · rc≠0 · «판정 불가» 1줄
# 실 Slack · 실 mbox 0 (FT_SLACK_REPLIES_CMD·FT_MBOX_SH 스텁) · sleep 0 · 자기 재호출 0. R2389R_BIN = 시험할 bin.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2389R_BIN:-$HERE/../bin}"
TOOL="$BIN/ft_desk_reply_wake.py"; CHECK="$BIN/ft_oppa_slack_check.py"
export T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
NOW=1795300000; QTS=1795244606.826379
DESK="byz-planner-desk-pi#127"; MASTER="byz-planner-master-pi#368"
export SENT="$T/sent.tsv"; : > "$SENT"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/.fable-team/comm" "$T/bin" "$T/hil"
LEDGER="$ROOT/.fable-team/state/desk-reply-wait.jsonl"
printf '{"_label": "planner", "_master": "%s", "_desk": "%s"}\n' "$MASTER" "$DESK" > "$ROOT/.fable-team/seats-planner.json"
printf '{"_label": "cfo", "_master": "byz-cfo-master-pi#1"}\n' > "$ROOT/.fable-team/seats-cfo.json"
cat > "$T/bin/mbox.sh" <<'SH'
#!/usr/bin/env bash
[ "${SEND_FAIL:-0}" = 1 ] && { echo "mbox: 접수 실패" >&2; exit 1; }
printf '%s\t%s\n' "$2" "$4" >> "$SENT"
echo "QUEUED seq=stub"
SH
cat > "$T/bin/replies.sh" <<'SH'
#!/usr/bin/env bash
cat "$T/replies.json"
SH
python3 -c 'import json,sys; json.dump({"ok": True, "messages": [{"ts": sys.argv[1], "user": "U0C9GRFHJ", "text": "질문"}]}, open(sys.argv[2], "w"))' "$QTS" "$T/replies.json"
led() { : > "$LEDGER"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$LEDGER"; done; }
run() {  # run [env...] — 점검 1판
  ( cd "$ROOT" || exit 1
    env FT_ROOT="$ROOT" FT_NOW="$NOW" FT_MBOX_SH="$T/bin/mbox.sh" HIL_DIR="$T/hil" FT_SLACK_CHECK="$CHECK" \
        FT_SLACK_REPLIES_CMD="bash $T/bin/replies.sh" FT_SEATS_PLANNER="$ROOT/.fable-team/seats-planner.json" \
        FT_DESK_REPLY_LEDGER="$LEDGER" "$@" python3 "$TOOL" ); }
only() { [ -z "${R2389R_ONLY:-}" ] || [[ " ${R2389R_ONLY:-} " == *" $1 "* ]]; }  # 사례 하나만 돌리기
sends() { wc -l < "$SENT" 2>/dev/null | tr -d ' ' || echo 0; }
field() { python3 -c 'import json,sys
for ln in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(ln)
    if r.get("q_ts") == sys.argv[2] and r.get("reask_at") is not None:
        print("reask", r["reask_at"]); break
else: print("—")' "$LEDGER" "$QTS"; }
row() {  # row <at> [state] [deadline] [notified]
  python3 -c 'import json,sys
at, st, dl, nt = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
r = {"q_ts": sys.argv[5], "kind": "question", "key": "pr10249-approve", "at": at, "deadline": int(sys.argv[6]), "state": st}
nt and r.update(notified_ts=nt)
print(json.dumps(r, ensure_ascii=False))' "$1" "${2:-open}" "${3:-0}" "${4:-}" "$QTS" "$((NOW + 61200))"; }
: > "$ROOT/.fable-team/comm/mailbox.jsonl"

if only ⑭; then
# ── ⑭ 7시간 답 0 = 1통 + reask_at · 다시 = 0 · 5시간 = 0 · 답글 있음 = 0
led "$(row $((NOW - 25200)))"
OUT="$(run 2>/dev/null)"; RC=$?
chk "⑭ 7시간 = _desk 1통 · 본문 «[다시 묻기] … 묻고 7시간»" '[ "$RC" = 0 ] && [ "$(sends)" = 1 ] && [ "$(cut -f1 "$SENT")" = "$DESK" ] && grep -qF "[다시 묻기] pr10249-approve q_ts=$QTS 묻고 7시간 · 메인 최상위로 다시 묻고 새 ts 로 --register 1회" "$SENT"'
chk "⑭ 장부에 reask_at=지금 추가" '[ "$(field)" = "reask $NOW" ]'
OUT="$(run 2>/dev/null)"; RC=$?
chk "⑭ 바로 다시 점검 = 0통(6시간 안 두 번 0)" '[ "$(sends)" = 1 ]'
led "$(row $((NOW - 18000)))"; : > "$SENT"
OUT="$(run 2>/dev/null)"
chk "⑭ 5시간 = 0통" '[ "$(sends)" = 0 ]'
led "$(row $((NOW - 25200)) open 0 1795245607.013719)"; : > "$SENT"
OUT="$(run 2>/dev/null)"
chk "⑭ 답글 있음(notified) = 0통" '[ "$(sends)" = 0 ]'

fi
if only ⑮; then
# ── ⑮ 마감 지난 줄 = 기준판 닫기 그대로(닫힘 timeout + _master 1통) · 다시 묻기 0
led "$(python3 -c 'import json,sys; print(json.dumps({"q_ts": sys.argv[1], "kind": "question", "key": "pr10249-approve", "at": int(sys.argv[2]) - 86400, "deadline": int(sys.argv[2]) - 60, "state": "open"}))' "$QTS" "$NOW")"; : > "$SENT"
OUT="$(run 2>/dev/null)"; RC=$?
chk "⑮ 닫힘(timeout) · _master 1통 · 다시 묻기 0" '[ "$RC" = 0 ] && python3 -c "import json,sys; r=[json.loads(x) for x in open(sys.argv[1]) if json.loads(x).get(\"q_ts\")==sys.argv[2]][-1]; print(r[\"state\"], r.get(\"closed\"))" "$LEDGER" "$QTS" | grep -qx "closed timeout" && [ "$(sends)" = 1 ] && [ "$(cut -f1 "$SENT")" = "$MASTER" ] && ! grep -qF "[다시 묻기]" "$SENT"'

fi
if only ⑯; then
# ── ⑯ 장부에 등록 0 인 [HIL] 대기 = desk 1통 · 6시간 안 두 번 0
led; : > "$SENT"
python3 -c 'import json,sys
body="[HIL] 카드 대기 2 · 다음 수: 10249 오빠 approve-merge 대기\n골좌표: 1 — B2B 토스 결제 시험"
print(json.dumps({"seq": 7, "ts": "2026-11-21T15:25:00", "to": "byz-planner-master-pi#368", "from": "byz-cfo-master-pi#1", "body": body}, ensure_ascii=False))' > "$ROOT/.fable-team/comm/mailbox.jsonl"
OUT="$(run FT_NOW=1795254180 2>/dev/null)"
chk "⑯ «[다시 묻기] 등록 없는 오빠 대기 cfo · 10249 오빠 approve-merge 대기 — 질문 올리고 --register-question» 1통" '[ "$(sends)" = 1 ] && [ "$(cut -f1 "$SENT")" = "$DESK" ] && grep -qF "[다시 묻기] 등록 없는 오빠 대기 cfo · 10249 오빠 approve-merge 대기 — 질문 올리고 --register-question" "$SENT"'
OUT="$(run FT_NOW=1795254180 2>/dev/null)"
chk "⑯ 6시간 안 다시 0통" '[ "$(sends)" = 1 ]'

fi
if only ⑰; then
# ── ⑰ 발신 실패 = reask_at 안 씀 · rc≠0 · «판정 불가» 1줄
led "$(row $((NOW - 25200)))"; : > "$SENT"
OUT="$(SEND_FAIL=1 run 2>&1)"; RC=$?
chk "⑰ 실패 = rc≠0 · «판정 불가» 1줄 · reask_at 없음(다음 판 다시)" '[ "$RC" -ne 0 ] && printf "%s" "$OUT" | grep -q "^ft-desk-reply-wake 판정 불가" && [ "$(field)" = "—" ]'

fi
# ── 변이 M10~M12 (사본에서만)
mut() { rm -rf "$T/mut"; cp -R "$BIN" "$T/mut"
  python3 - "$T/mut/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 자리 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
runmut() {  # runmut <이름> <파일> <바꿀 글> <새 글> <기대 FAIL> <사례>
  mut "$1" "$2" "$3" "$4" || { bad "변이 $1 적용 실패"; return; }
  local out; out="$(R2389R_ONLY="$6" R2389R_BIN="$T/mut" bash "${BASH_SOURCE[0]:-$0}" 2>&1)"; local rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "^FAIL $5"; then ok "변이 $1 → «$5» FAIL(시험이 잡는다)"; else bad "변이 $1 → «$5» 안 잡힘(rc=$rc)"; fi; }
if [ -z "${R2389R_BIN:-}" ]; then
  runmut M10 ft_desk_reply_wake.py 'and now - last_ask(r) >= REASK_S' 'and True' "⑭ 바로 다시 점검" ⑭
  runmut M11 ft_desk_reply_wake.py '            up[rowkey(row)] = {"state": "closed", "closed": "timeout"}
            shut += 1
            continue' '            continue' "⑮ 닫힘(timeout)" ⑮
  runmut M12 ft_desk_reply_wake.py '            bad("쪽지 발신 실패 — %s 다시 묻기 0(reask_at 안 씀 · 다음 주기 재시도)" % k)
            nbad += 1
            continue' '            bad("쪽지 발신 실패 — %s 다시 묻기 0(reask_at 안 씀 · 다음 주기 재시도)" % k)
            nbad += 1' "⑰ 실패" ⑰
fi
echo "--- r2389 reask: FAIL $fail"
[ "$fail" -eq 0 ]
