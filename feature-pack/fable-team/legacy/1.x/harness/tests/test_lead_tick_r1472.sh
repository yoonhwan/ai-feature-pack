#!/usr/bin/env bash
# test_lead_tick_r1472.sh — ft-lead-tick.sh(r1472) 계약: 팀장 «사건 턴» 1회 = 비모델 스크립트 1회 + 결정 필요 N
#   T1 합성 명부·카드(대기 2 · 진행 1)·나노 2(1석 25분 유휴)·쪽지 2([HIL] 1)·열린 h 1 → ≤30줄 · «결정 필요: 3» · [정리] 1통(to=_report_to) · rc0
#   T2 `_master` ≠ 좌석(또는 빈칸) → recv 0 · send 0 · «결속 불일치» 1줄 · rc1
#   T3 좌석 상태 조회 실패(rc3) → «판정 불가 rc=3» 1줄 · 나머지 항목 출력 · send 함(유휴 미상) · rc1
#   T4 FT_LEAD_TICK_BUDGET=1 · 가짜 mbox sleep 2 → rc124 · send 0
#   T5 송신 규칙: N=0 ∧ .last 같음 → send 0 + «조용함» / 카드 변화 → send 1 / _report_to = 자기 → send 0 + «자기 송신 차단» rc1 / _report_to 없음 → planner _master
#   T6 test_desk_tick_r1462 rc0 · 설치기·desk 파일 origin/main 대비 diff 0
# 전부 합성(임시 루트·임시 git·가짜 mbox·가짜 ft-hil·가짜 ft-seat-status) · 실 우편함·실 좌석 쓰기 0 · sleep 0(가짜 mbox 의 T4 지연만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../bin/ft-lead-tick.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

NOW=1794103664
LEAD='byz-knowledge-master-pi#99'
REPORT='byz-harness-master-pi#270'
PLANNER='byz-planner-master-pi#310'
R="$T/root"; F="$R/.fable-team"
mkdir -p "$F/comm" "$T/hil" "$T/state" "$R/design/teams/knowledge/indices/대기" "$R/design/teams/knowledge/indices/진행"
roster() {  # roster <_master> [<_report_to>|-]
  python3 - "$F/seats-knowledge.json" "$1" "${2:--}" <<'PY'
import json, sys
d = {"_master": sys.argv[2], "_cards": "design/teams/knowledge/indices"}
if sys.argv[3] != "-": d["_report_to"] = sys.argv[3]
d["byz-knowledge-nano-a#0"] = {"role": "nano", "agent": "pi"}
d["byz-knowledge-nano-b#0"] = {"role": "nano", "agent": "pi"}
d["byz-knowledge-da-codex#3"] = {"role": "da", "agent": "codex"}
d["byz-knowledge-nano-old#0"] = {"role": "stop-ready", "agent": "pi"}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
roster "$LEAD" "$REPORT"
printf '{"_master":"%s"}\n' "$PLANNER" > "$F/seats-planner.json"
: > "$R/design/teams/knowledge/indices/대기/r1.md"; : > "$R/design/teams/knowledge/indices/대기/r2.md"; : > "$R/design/teams/knowledge/indices/진행/r3.md"
git -C "$R" init -q && git -C "$R" add design && git -C "$R" -c user.name=t -c user.email=t@t commit -qm cards \
  && git -C "$R" update-ref refs/remotes/origin/main HEAD || { echo "FAIL 합성 git"; exit 1; }

cat > "$F/comm/mbox.sh" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  send) shift
        python3 - "$FAKE_SENT" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}, ensure_ascii=False) + "\n")
PY
        echo "QUEUED seq=1 to=$1"; exit 0;;
  recv) [ -n "${FAKE_RECV_MARK:-}" ] && printf 'called\n' >> "$FAKE_RECV_MARK"
        [ -n "${FAKE_MBOX_SLEEP:-}" ] && sleep "$FAKE_MBOX_SLEEP"
        [ -n "${FAKE_RECV:-}" ] && [ -f "$FAKE_RECV" ] && cat "$FAKE_RECV" || echo "SCANNED 1 mailbox(es): fake"
        exit 0;;
esac
exit 2
EOS
cat > "$T/hil/ft-hil.sh" <<'EOS'
#!/usr/bin/env bash
[ -f "$HIL_DIR/pending.txt" ] && cat "$HIL_DIR/pending.txt"; exit 0
EOS
cat > "$T/seat-status.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_STATUS_RC:-}" ] && { echo "tmux 없음" >&2; exit "$FAKE_STATUS_RC"; }
printf '%s\n' "$FAKE_STATUS"
EOS
ST_IDLE='[{"seat":"byz-knowledge-nano-a#0","pane":"IDLE","jsonl_age":1500},{"seat":"byz-knowledge-nano-b#0","pane":"BUSY","jsonl_age":30},{"seat":"byz-knowledge-da-codex#3","pane":"IDLE","jsonl_age":100},{"seat":"byz-knowledge-nano-old#0","pane":"IDLE","jsonl_age":9000}]'
ST_CALM='[{"seat":"byz-knowledge-nano-a#0","pane":"BUSY","jsonl_age":10},{"seat":"byz-knowledge-nano-b#0","pane":"BUSY","jsonl_age":30}]'
printf 'SCANNED 1 mailbox(es)\nREAD [byz-planner-master-pi#310->%s] #11 — [HIL] 오빠 결정 필요: 지식 색인 재빌드 GO 여부\nREAD [byz-knowledge-nano-a#0->%s] #12 — [회신] r9 끝\n' "$LEAD" "$LEAD" > "$T/recv2.txt"
printf 'h77 30\n' > "$T/hil/pending.txt"; printf 'to=%s\n' "$LEAD" > "$T/hil/h77.notify"

export FAKE_STATUS="$ST_IDLE" FAKE_RECV="$T/recv2.txt" FAKE_SENT="$T/sent.jsonl"
run() {
  env FT_ROOT="$R" FT_HIL_DIR="$T/hil" HIL_DIR="$T/hil" \
      FT_LEAD_TICK_MBOX="$F/comm/mbox.sh" FT_LEAD_TICK_HIL="$T/hil/ft-hil.sh" FT_LEAD_TICK_SEAT_STATUS="$T/seat-status.sh" \
      FT_LEAD_TICK_NOW="$NOW" FT_LEAD_TICK_STATE_DIR="$T/state" bash "$S" "$LEAD" 2>&1
}
sent_n() { [ -f "$T/sent.jsonl" ] && grep -c . "$T/sent.jsonl" || echo 0; }
[ -f "$S" ] || { echo "FAIL ft-lead-tick.sh 없음: $S"; echo "FAILED 1"; exit 1; }
bash -n "$S" && ok "bash -n" || bad "bash -n"

# ── T1
t0="$(date +%s)"; out="$(run)"; rc=$?; el=$(( $(date +%s) - t0 ))
n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
[ "$rc" -eq 0 ] && ok "T1 rc0" || bad "T1 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "$n" -le 30 ] && ok "T1 출력 ${n}줄 ≤30 · ${el}초" || bad "T1 출력 ${n}줄"
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 3' && ok "T1 마지막 줄 «결정 필요: 3»" || bad "T1 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
[ "$(sent_n)" = 1 ] && ok "T1 [정리] 1통" || bad "T1 send $(sent_n)통"
python3 - "$T/sent.jsonl" "$REPORT" <<'PY' && ok "T1 to=_report_to · 3줄 · 첫 줄 «카드 대기 2 · 진행 1 · 유휴 1 · 다음 수 …» · 백틱·\$( 0" || bad "T1 본문"
import json, sys
try: r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
except Exception as e: print("BAD", e); sys.exit(1)
b = r["body"]; bad = []
if r["to"] != sys.argv[2]: bad.append("to=" + r["to"])
if len(b.splitlines()) != 3: bad.append("줄수=%d" % len(b.splitlines()))
if not b.splitlines()[0].startswith("카드 대기 2 · 진행 1 · 유휴 1 · 다음 수 "): bad.append("첫줄=" + b.splitlines()[0])
if "`" in b or "$(" in b: bad.append("백틱/$(")
if bad: print("BAD", bad); sys.exit(1)
PY

# ── T2
for m in 'byz-knowledge-master-pi#98' ''; do
  rm -f "$T/sent.jsonl" "$T/mark"; roster "$m" "$REPORT"
  out="$(FAKE_RECV_MARK="$T/mark" run)"; rc=$?
  [ "$rc" -eq 1 ] && [ ! -f "$T/mark" ] && [ "$(sent_n)" = 0 ] && ok "T2 _master='$m' → recv 0 · send 0 · rc1" || bad "T2 _master='$m' rc=$rc recv=$([ -f "$T/mark" ] && echo y) send=$(sent_n)"
  printf '%s\n' "$out" | grep -q '결속 불일치' && ok "T2 «결속 불일치» 1줄" || bad "T2 줄 없음: $(printf '%s' "$out" | tr '\n' '/')"
done
roster "$LEAD" "$REPORT"

# ── T3
rm -f "$T/sent.jsonl"
out="$(FAKE_STATUS_RC=3 run)"; rc=$?
[ "$rc" -eq 1 ] && ok "T3 rc1" || bad "T3 rc=$rc"
printf '%s\n' "$out" | grep -q '판정 불가 rc=3' && ok "T3 «판정 불가 rc=3»" || bad "T3 판정 불가 줄 없음"
printf '%s\n' "$out" | grep -q '^카드 대기 2 · 진행 1' && printf '%s\n' "$out" | grep -q '^쪽지 2건' && ok "T3 나머지 항목 출력" || bad "T3 나머지: $(printf '%s' "$out" | tr '\n' '/')"
[ "$(sent_n)" = 1 ] && grep -q '유휴 미상' "$T/sent.jsonl" && ok "T3 send 1 · 유휴 미상" || bad "T3 send=$(sent_n) $(cat "$T/sent.jsonl" 2>/dev/null)"

# ── T4
rm -f "$T/sent.jsonl"
t0="$(date +%s)"; out="$(FT_LEAD_TICK_BUDGET=1 FAKE_MBOX_SLEEP=2 run)"; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 124 ] && ok "T4 rc124 (${el}초)" || bad "T4 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "$(sent_n)" = 0 ] && ok "T4 send 0" || bad "T4 send $(sent_n)"

# ── T5
rm -rf "$T/state" "$T/sent.jsonl"; mkdir -p "$T/state"; : > "$T/hil/pending.txt"
export FAKE_STATUS="$ST_CALM"; unset FAKE_RECV
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sent_n)" = 1 ] && printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && ok "T5a N=0 첫 회(.last 없음) → send 1" || bad "T5a rc=$rc send=$(sent_n) $(printf '%s' "$out" | tr '\n' '/')"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sent_n)" = 1 ] && ok "T5b N=0 ∧ 무변화 → send 0 · rc0" || bad "T5b rc=$rc send=$(sent_n)"
grep -q '조용함' "$T/state/$LEAD.last" 2>/dev/null && ok "T5b .last «조용함 ts»" || bad "T5b .last: $(cat "$T/state/$LEAD.last" 2>/dev/null)"
: > "$R/design/teams/knowledge/indices/대기/r4.md"
git -C "$R" add design && git -C "$R" -c user.name=t -c user.email=t@t commit -qm r4 && git -C "$R" update-ref refs/remotes/origin/main HEAD
out="$(run)"; rc=$?
[ "$(sent_n)" = 2 ] && tail -1 "$T/sent.jsonl" | grep -q '카드 대기 3' && ok "T5c N=0 인데 카드 변화 → send 1" || bad "T5c send=$(sent_n)"
roster "$LEAD" "$LEAD"
out="$(run)"; rc=$?
[ "$rc" -eq 1 ] && [ "$(sent_n)" = 2 ] && printf '%s\n' "$out" | grep -q '자기 송신 차단' && ok "T5d _report_to=자기 → send 0 · «자기 송신 차단» · rc1" || bad "T5d rc=$rc send=$(sent_n)"
roster "$LEAD" -; rm -rf "$T/state"; mkdir -p "$T/state"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && tail -1 "$T/sent.jsonl" | grep -q "\"to\": \"$PLANNER\"" && ok "T5e _report_to 없음 → planner _master" || bad "T5e rc=$rc $(tail -1 "$T/sent.jsonl")"

# ── T6
bash "$HERE/test_desk_tick_r1462.sh" >/dev/null 2>&1 && ok "T6 test_desk_tick_r1462 rc0" || bad "T6 desk 시험 실패"
B="$HERE/.."
if git -C "$B" rev-parse --verify -q origin/main >/dev/null; then
  git -C "$B" diff --quiet origin/main -- bin/ft-tick-install.sh bin/ft-desk-tick.sh kit/fable-team/bin/ft-tick-install.sh kit/fable-team/bin/ft-desk-tick.sh \
    && ok "T6 설치기·desk 파일 diff 0" || bad "T6 설치기·desk 파일이 바뀌었다"
else bad "T6 origin/main 판정 불가"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
