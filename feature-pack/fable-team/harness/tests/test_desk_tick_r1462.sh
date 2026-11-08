#!/usr/bin/env bash
# test_desk_tick_r1462.sh — ft-desk-tick.sh(r1462) 계약: T1 6항 출력 ≤30줄 · 마지막 줄 `결정 필요: N` · 25초 안
#   T2 한 항목 실패 = 그 항목 «판정 불가 rc=N» 1줄 · 나머지 계속 · 전체 rc1 · T3 [완료] 쪽지 1통 · 본문 3줄 · 백틱·$() 0
#   전부 합성(임시 루트·가짜 mbox·가짜 launchctl·가짜 pgrep) · 실 우편함·실 launchctl·실 세션 쓰기 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../bin/ft-desk-tick.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-desk-tick.sh 없음: $S"; echo "FAILED 1"; exit 1; }
bash -n "$S" && ok "bash -n" || bad "bash -n"

NOW=1794103664          # 고정 시각(2026-11-08T11:07:44Z 근처) — 시계 의존 0
DESK='byz-planner-desk-claude#121'
mkdir -p "$T/root/.fable-team/comm" "$T/fakebin" "$T/hil" "$T/state"

# 가짜 명부: planner _master 하나
printf '{"_master":"byz-planner-master-claude#240","_desk":"%s"}\n' "$DESK" > "$T/root/.fable-team/seats-planner.json"

# 가짜 mbox: send = $FAKE_SENT 에 1줄 · recv = $FAKE_RECV 파일 그대로
cat > "$T/root/.fable-team/comm/mbox.sh" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  send) shift
        python3 - "$FAKE_SENT" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}) + "\n")
PY
        echo "QUEUED seq=1 to=$1 pending=1 doorbell=sent"; exit 0;;
  recv) [ -n "${FAKE_RECV:-}" ] && [ -f "$FAKE_RECV" ] && cat "$FAKE_RECV" || echo "SCANNED 1 mailbox(es): fake"
        exit 0;;
esac
exit 2
EOS
# 가짜 ft-hil.sh: --pending --each = $HIL_DIR/pending.txt 그대로
cat > "$T/hil/ft-hil.sh" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = --pending ] || continue; [ -f "$HIL_DIR/pending.txt" ] && cat "$HIL_DIR/pending.txt"; exit 0; done
exit 2
EOS
# 가짜 launchctl: $FAKE_LAUNCH_RC 가 있으면 그 rc 로 죽는다(항목 실패 시험)
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_LAUNCH_RC:-}" ] && { echo "Could not find service" >&2; exit "$FAKE_LAUNCH_RC"; }
echo "$2"
echo "	state = not running"
case "$2" in *ft-tick) echo "	last exit code = (never exited)";; *) echo "	last exit code = 0";; esac   # KeepAlive 좌석 = 종료한 적 없음이 정상(T1 이 이 꼴을 통과시키나 본다)
exit 0
EOS
# 가짜 pgrep: $FAKE_PGREP 줄을 그대로 낸다
cat > "$T/fakebin/pgrep" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_PGREP:-}" ] && { printf '%s\n' "$FAKE_PGREP"; exit 0; }
exit 1
EOS
chmod +x "$T/fakebin/launchctl" "$T/fakebin/pgrep"   # 시험 픽스처만 실행 비트(리포 파일 0)
printf 'ts=%s stall=0 a=0 b=0 c=0 d=0 seats=1\n' "$NOW" > "$T/stall.log"

run() {  # run <추가 env…> — 공통 env 로 스크립트 1회
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" \
      FT_DESK_TICK_MBOX="$T/root/.fable-team/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PGREP="$T/fakebin/pgrep" \
      FT_DESK_TICK_STALL_LOG="$T/stall.log" FT_DESK_TICK_LOG="$T/root/.fable-team/comm/mailbox.log.jsonl" \
      FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_STATE_DIR="$T/state" FT_DESK_TICK_UID=501 \
      FAKE_SENT="$T/sent.jsonl" "$@" bash "$S" "$DESK" 2>&1
}
# 팀장 쪽지 기록(5분 전 · 20분 미만이라 줄이 안 나와야 한다)
printf '{"ts":"2026-11-08T11:02:44Z","from":"byz-planner-master-claude#240","to":"x","body":"y"}\n' \
  > "$T/root/.fable-team/comm/mailbox.log.jsonl"

# ── T1 전부 정상 = 결정 필요 0 · 6항 출력 · ≤30줄 · 25초 안
t0="$(date +%s)"
out="$(run FAKE_PGREP="4242 ft-inbox-watch $DESK")"; rc=$?
el=$(( $(date +%s) - t0 ))
n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
{ [ "$rc" -eq 0 ]; } && ok "T1 전체 rc0" || bad "T1 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "${n:-99}" -le 30 ] && ok "T1 출력 ${n}줄 ≤30" || bad "T1 출력 ${n}줄 >30"
[ "$el" -le 25 ] && ok "T1 소요 ${el}초 ≤25" || bad "T1 소요 ${el}초 >25"
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && ok "T1 마지막 줄 «결정 필요: 0»" || bad "T1 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
for k in '^HIL 대기 0건' '^LAUNCH stall-scan ' '^LAUNCH tick ' '^LAUNCH news-planner ' '^LAUNCH news-desk ' '^STALL-SCAN ' '^INBOX-WATCH ' '^쪽지 0건'; do
  printf '%s\n' "$out" | grep -q "$k" || bad "T1 항목 줄 없음: $k"
done
printf '%s\n' "$out" | grep -q '^HIL 대기 0건' && printf '%s\n' "$out" | grep -q '^INBOX-WATCH ' && printf '%s\n' "$out" | grep -q '^쪽지 0건' \
  && ok "T1 ①HIL ②launch ③팀장 ④감시 ⑤쪽지 ⑥완료 6항 출력" || bad "T1 6항 누락"
printf '%s\n' "$out" | grep -q '^완료쪽지 → byz-planner-master-claude#240' && ok "T1 ⑥ planner _master 로 완료쪽지" || bad "T1 완료쪽지 줄: $(printf '%s\n' "$out" | grep '^완료쪽지' | head -1)"

# ── T3 [완료] 쪽지 = 1통 · 본문 3줄 · 백틱·$() 0
cnt="$(python3 -c 'import json,sys;print(sum(1 for l in open(sys.argv[1]) if l.strip()))' "$T/sent.jsonl" 2>/dev/null || echo 0)"
[ "$cnt" = 1 ] && ok "T3 쪽지 1통" || bad "T3 쪽지 $cnt통"
python3 - "$T/sent.jsonl" <<'PY' && ok "T3 본문 3줄 · 백틱·\$() 0 · planner 수신" || bad "T3 본문 위반"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
b = rows[-1]["body"]
bad = []
if len(b.splitlines()) != 3: bad.append("줄수=%d" % len(b.splitlines()))
if "`" in b: bad.append("백틱")
if "$(" in b: bad.append("$(")
if rows[-1]["to"] != "byz-planner-master-claude#240": bad.append("to=" + rows[-1]["to"])
if bad: print("BAD " + " ".join(bad)); sys.exit(1)
PY

# ── T2 한 항목 실패 = 그 항목 판정 불가 1줄 · 다른 항목 계속 · 전체 rc1
rm -f "$T/sent.jsonl"
out="$(run FAKE_LAUNCH_RC=3 FAKE_PGREP="4242 ft-inbox-watch $DESK")"; rc=$?
[ "$rc" -eq 1 ] && ok "T2 항목 실패 → 전체 rc1" || bad "T2 rc=$rc"
printf '%s\n' "$out" | grep -q '판정 불가 rc=3' && ok "T2 «판정 불가 rc=3» 1줄" || bad "T2 판정 불가 줄 없음"
printf '%s\n' "$out" | grep -q '^HIL 대기 0건' && ok "T2 다른 항목 계속 측정(①)" || bad "T2 ① 이 죽었다"
printf '%s\n' "$out" | grep -q '^쪽지 0건' && ok "T2 다른 항목 계속 측정(⑤)" || bad "T2 ⑤ 이 죽었다"
printf '%s\n' "$out" | tail -1 | grep -qE '^결정 필요: [1-9][0-9]*$' && ok "T2 결정 필요 N≥1" || bad "T2 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
printf '%s\n' "$out" | grep -q '^LAUNCH stall-scan state=' && bad "T2 실패한 항목에 정상 줄이 남았다" || ok "T2 실패 항목은 정상 줄을 내지 않는다"

# ── T1b 쪽지 1건 = 머리(seq·from·60자) + 결정 필요 N≥1 · 전문 사본 경로
printf 'SCANNED 1 mailbox(es)\nREAD [byz-planner-master-claude#240->%s] #273617 — [회신 #273610] ① 명부 등록 됨: seats-harness.json 에 네 행(role=nano) 있다\n본문 2번째 줄\n' "$DESK" > "$T/recv.txt"
rm -f "$T/sent.jsonl"
out="$(run FAKE_PGREP="4242 ft-inbox-watch $DESK" FAKE_RECV="$T/recv.txt")"; rc=$?
printf '%s\n' "$out" | grep -q '^쪽지 1건' && ok "T1b 쪽지 1건" || bad "T1b 쪽지 줄: $(printf '%s\n' "$out" | grep '^쪽지' | head -1)"
printf '%s\n' "$out" | grep -q '  #273617 byz-planner-master-claude#240 ' && ok "T1b 머리 = seq·from·본문 60자" || bad "T1b 머리: $(printf '%s\n' "$out" | grep '#273617' | head -1)"
printf '%s\n' "$out" | grep -q '^쪽지 전문 ' && ok "T1b 전문 사본 경로 1줄" || bad "T1b 전문 경로 없음"
printf '%s\n' "$out" | tail -1 | grep -qE '^결정 필요: [1-9]' && ok "T1b 쪽지 있으면 결정 필요 ≥1" || bad "T1b 마지막 줄: $(printf '%s\n' "$out" | tail -1)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
