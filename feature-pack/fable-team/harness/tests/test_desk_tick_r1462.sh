#!/usr/bin/env bash
# test_desk_tick_r1462.sh — ft-desk-tick.sh(r1462) 계약: T1 6항 출력 ≤30줄 · 마지막 줄 `결정 필요: N` · 25초 안
#   T2 한 항목 실패 = 그 항목 «판정 불가 rc=N» 1줄 · 나머지 계속 · 전체 rc1
#   T3 [완료] 쪽지 1통 · 본문 3줄 · 첫줄 [완료] 머리 · 백틱·$() 0
#   T10 결속(planner _master 없음) 전 recv 0 · 완료송신 0 · T11 전문 저장 실패 → 완료송신 0 · rc1
#   T12 실제 watcher argv(python3 -u - <bin> <좌석>)를 감시 있음으로 · T13 전체 예산 0 → 하위 명령 0 · 전 항목 rc=124
# 전부 합성(임시 루트·가짜 mbox·가짜 launchctl·가짜 ps) · 실 우편함·실 launchctl·실 세션 쓰기 0 · sleep 0.
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
PLANNER='byz-planner-master-claude#240'
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$T/root/.fable-team/seats-planner.json"

# 가짜 mbox: send = $FAKE_SENT 에 1줄 · recv = $FAKE_RECV 파일 그대로(+호출 표식 $FAKE_RECV_MARK)
cat > "$T/root/.fable-team/comm/mbox.sh" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  send) shift
        python3 - "$FAKE_SENT" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}) + "\n")
PY
        echo "QUEUED seq=1 to=$1 pending=1 doorbell=sent"; exit 0;;
  recv) [ -n "${FAKE_RECV_MARK:-}" ] && printf 'called\n' >> "$FAKE_RECV_MARK"
        [ -n "${FAKE_RECV:-}" ] && [ -f "$FAKE_RECV" ] && cat "$FAKE_RECV" || echo "SCANNED 1 mailbox(es): fake"
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
# 가짜 launchctl: $FAKE_LAUNCH_RC 면 그 rc 로 죽고 · $FAKE_LAUNCH_LOG 면 호출을 적는다(예산 시험)
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_LAUNCH_LOG:-}" ] && printf '%s\n' "$2" >> "$FAKE_LAUNCH_LOG"
[ -n "${FAKE_LAUNCH_RC:-}" ] && { echo "Could not find service" >&2; exit "$FAKE_LAUNCH_RC"; }
echo "$2"
echo "	state = not running"
case "$2" in *ft-tick) echo "	last exit code = (never exited)";; *) echo "	last exit code = 0";; esac   # KeepAlive 좌석 = 종료한 적 없음이 정상
exit 0
EOS
# 가짜 ps: 실제 watcher 의 argv(`python3 -u - <bin> <좌석>`)를 그대로 낸다 — 이름만으로 잡으면 실 watcher 를 놓친다
cat > "$T/fakebin/ps" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_PS:-}" ] && { printf '%s\n' "$FAKE_PS"; exit 0; }
exit 0
EOS
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps"   # 시험 픽스처만 실행 비트(리포 파일 0)
printf 'ts=%s stall=0 a=0 b=0 c=0 d=0 seats=1\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" \
  > "$T/root/.fable-team/comm/mailbox.log.jsonl"   # 5분 전 = 20분 미만이라 팀장 줄이 안 나와야 한다

PSLINE="4242 python3 -u - $T/root/.fable-team/bin $DESK"
export FAKE_PS="$PSLINE"
STATE_DIR_OVERRIDE=""
run() {  # 추가 env 는 export 로 준다(명령치환 안 중첩 따옴표 = 파싱 사고 방지)
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" \
      FT_DESK_TICK_MBOX="$T/root/.fable-team/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" \
      FT_DESK_TICK_STALL_LOG="$T/stall.log" FT_DESK_TICK_LOG="$T/root/.fable-team/comm/mailbox.log.jsonl" \
      FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 \
      FT_DESK_TICK_STATE_DIR="${STATE_DIR_OVERRIDE:-$T/state}" \
      FAKE_SENT="$T/sent.jsonl" bash "$S" "$DESK" 2>&1
}

# ── T1 전부 정상 = 결정 필요 0 · 6항 출력 · ≤30줄 · 25초 안
t0="$(date +%s)"
out="$(run)"; rc=$?
el=$(( $(date +%s) - t0 ))
n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
[ "$rc" -eq 0 ] && ok "T1 전체 rc0" || bad "T1 rc=$rc out=$(printf '%s' "$out" | tr '\n' '/')"
[ "${n:-99}" -le 30 ] && ok "T1 출력 ${n}줄 ≤30" || bad "T1 출력 ${n}줄 >30"
[ "$el" -le 25 ] && ok "T1 소요 ${el}초 ≤25" || bad "T1 소요 ${el}초 >25"
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && ok "T1 마지막 줄 «결정 필요: 0»" || bad "T1 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
missing=""
for k in '^HIL 대기 0건' '^LAUNCH stall-scan ' '^LAUNCH tick ' '^LAUNCH news-planner ' '^LAUNCH news-desk ' '^STALL-SCAN ' '^INBOX-WATCH ' '^결속 OK planner ' '^쪽지 0건'; do
  printf '%s\n' "$out" | grep -q "$k" || missing="$missing $k"
done
[ -z "$missing" ] && ok "T1 ①HIL ②launch ③팀장 ④감시 ⑤결속 ⑥쪽지/완료 6항 출력" || bad "T1 항목 줄 없음:$missing"
printf '%s\n' "$out" | grep -q "^완료쪽지 → $PLANNER" && ok "T1 ⑥ planner _master 로 완료쪽지" || bad "T1 완료쪽지 줄: $(printf '%s\n' "$out" | grep '^완료쪽지' | head -1)"

# ── T3 [완료] 쪽지 = 1통 · 본문 3줄 · 첫줄 [완료] · 백틱·$() 0
cnt="$(python3 -c 'import json,sys;print(sum(1 for l in open(sys.argv[1]) if l.strip()))' "$T/sent.jsonl" 2>/dev/null || echo 0)"
[ "$cnt" = 1 ] && ok "T3 쪽지 1통" || bad "T3 쪽지 $cnt통"
python3 - "$T/sent.jsonl" "$PLANNER" <<'PY' && ok "T3 본문 3줄 · 첫줄 [완료] · 백틱·\$() 0 · planner 수신" || bad "T3 본문 위반"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
b = rows[-1]["body"]
bad = []
if len(b.splitlines()) != 3: bad.append("줄수=%d" % len(b.splitlines()))
if not b.startswith("[완료]"): bad.append("머리표 없음")
if "`" in b: bad.append("백틱")
if "$(" in b: bad.append("$(")
if rows[-1]["to"] != sys.argv[2]: bad.append("to=" + rows[-1]["to"])
if bad: print("BAD " + " ".join(bad)); sys.exit(1)
PY

# ── T2 한 항목 실패 = 그 항목 판정 불가 1줄 · 다른 항목 계속 · 전체 rc1
rm -f "$T/sent.jsonl"
export FAKE_LAUNCH_RC=3
out="$(run)"; rc=$?
unset FAKE_LAUNCH_RC
[ "$rc" -eq 1 ] && ok "T2 항목 실패 → 전체 rc1" || bad "T2 rc=$rc"
printf '%s\n' "$out" | grep -q '판정 불가 rc=3' && ok "T2 «판정 불가 rc=3» 1줄" || bad "T2 판정 불가 줄 없음"
printf '%s\n' "$out" | grep -q '^HIL 대기 0건' && ok "T2 다른 항목 계속 측정(①)" || bad "T2 ① 이 죽었다"
printf '%s\n' "$out" | grep -q '^쪽지 0건' && ok "T2 다른 항목 계속 측정(⑤)" || bad "T2 ⑤ 이 죽었다"
printf '%s\n' "$out" | tail -1 | grep -qE '^결정 필요: [1-9][0-9]*$' && ok "T2 결정 필요 N≥1" || bad "T2 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
printf '%s\n' "$out" | grep -q '^LAUNCH stall-scan state=' && bad "T2 실패한 항목에 정상 줄이 남았다" || ok "T2 실패 항목은 정상 줄을 내지 않는다"

# ── T1b 쪽지 1건 = 머리(seq·from·60자) + 결정 필요 N≥1 · 전문 사본 경로
printf 'SCANNED 1 mailbox(es)\nREAD [%s->%s] #273617 — [회신 #273610] ① 명부 등록 됨: seats-harness.json 에 네 행(role=nano) 있다\n본문 2번째 줄\n' \
  "$PLANNER" "$DESK" > "$T/recv.txt"
rm -f "$T/sent.jsonl"
export FAKE_RECV="$T/recv.txt"
out="$(run)"; rc=$?
unset FAKE_RECV
printf '%s\n' "$out" | grep -q '^쪽지 1건' && ok "T1b 쪽지 1건" || bad "T1b 쪽지 줄: $(printf '%s\n' "$out" | grep '^쪽지' | head -1)"
printf '%s\n' "$out" | grep -q "  #273617 $PLANNER " && ok "T1b 머리 = seq·from·본문 60자" || bad "T1b 머리: $(printf '%s\n' "$out" | grep '273617' | head -1)"
printf '%s\n' "$out" | grep -q '^쪽지 전문 ' && ok "T1b 전문 사본 경로 1줄" || bad "T1b 전문 경로 없음"
printf '%s\n' "$out" | tail -1 | grep -qE '^결정 필요: [1-9]' && ok "T1b 쪽지 있으면 결정 필요 ≥1" || bad "T1b 마지막 줄: $(printf '%s\n' "$out" | tail -1)"

# ── T10(반례②-a) 결속 확인 전 recv 0 — planner _master 가 없으면 우편함을 건드리지도, 완료를 보내지도 않는다
rm -f "$T/sent.jsonl" "$T/recv-called.txt"
printf '{"_desk":"%s"}\n' "$DESK" > "$T/root/.fable-team/seats-planner.json"
export FAKE_RECV_MARK="$T/recv-called.txt"
out="$(run)"; rc=$?
unset FAKE_RECV_MARK
[ "$rc" -eq 1 ] && ok "T10 결속 실패 → rc1" || bad "T10 rc=$rc"
[ -f "$T/recv-called.txt" ] && bad "T10 결속 확인 전에 recv 를 불렀다(우편함 소비 위험)" || ok "T10 결속 전 recv 0"
[ -f "$T/sent.jsonl" ] && bad "T10 결속 실패인데 완료쪽지를 보냈다" || ok "T10 결속 실패 → 완료송신 0"
printf '%s\n' "$out" | grep -q '결속 판정 불가 rc=' && ok "T10 «결속 판정 불가 rc=N» 1줄" || bad "T10 결속 줄 없음: $(printf '%s' "$out" | tr '\n' '/' | cut -c1-160)"
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$T/root/.fable-team/seats-planner.json"   # 원복

# ── T10b(반례②-2) _master 정상 + _desk «비어 있음» = 소비 권한 없음 → recv 0 · 송신 0 · rc1 (이름 접두 통과 금지)
rm -f "$T/sent.jsonl" "$T/recv-called.txt"
printf '{"_master":"%s"}\n' "$PLANNER" > "$T/root/.fable-team/seats-planner.json"
export FAKE_RECV_MARK="$T/recv-called.txt"
out="$(run)"; rc=$?
unset FAKE_RECV_MARK
[ "$rc" -eq 1 ] && ok "T10b _desk 빈칸 → rc1" || bad "T10b rc=$rc"
[ -f "$T/recv-called.txt" ] && bad "T10b _desk 빈칸인데 recv 를 불렀다(소비 권한 없음)" || ok "T10b _desk 빈칸 → recv 0"
[ -f "$T/sent.jsonl" ] && bad "T10b _desk 빈칸인데 완료쪽지를 보냈다" || ok "T10b _desk 빈칸 → 완료송신 0"
printf '%s\n' "$out" | grep -q '결속 판정 불가 rc=' && ok "T10b «결속 판정 불가 rc=N» 1줄" || bad "T10b 결속 줄 없음"
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$T/root/.fable-team/seats-planner.json"   # 원복

# ── T10c(반례②-3) _desk 가 «다른 좌석» 이면 역시 소비 권한 없음
rm -f "$T/sent.jsonl" "$T/recv-called.txt"
printf '{"_master":"%s","_desk":"ft-planner-desk-sonnet#1"}\n' "$PLANNER" > "$T/root/.fable-team/seats-planner.json"
export FAKE_RECV_MARK="$T/recv-called.txt"
out="$(run)"; rc=$?
unset FAKE_RECV_MARK
[ "$rc" -eq 1 ] && [ ! -f "$T/recv-called.txt" ] && ok "T10c _desk 불일치 → recv 0 · rc1" || bad "T10c rc=$rc recv=$([ -f "$T/recv-called.txt" ] && echo yes || echo no)"
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$T/root/.fable-team/seats-planner.json"   # 원복

# ── T11(반례②-b) 전문 사본 저장 실패 = 판정 불가 · rc1 · 완료송신 0
rm -f "$T/sent.jsonl"
printf 'nope\n' > "$T/notadir"   # 부모가 파일 이라 mkdir -p 가 실패한다
export FAKE_RECV="$T/recv.txt"
STATE_DIR_OVERRIDE="$T/notadir/sub"
out="$(run)"; rc=$?
STATE_DIR_OVERRIDE=""; unset FAKE_RECV
[ "$rc" -eq 1 ] && ok "T11 저장 실패 → rc1" || bad "T11 rc=$rc"
printf '%s\n' "$out" | grep -q '쪽지 저장 판정 불가 rc=' && ok "T11 «쪽지 저장 판정 불가» 1줄" || bad "T11 저장 실패 줄 없음: $(printf '%s' "$out" | tr '\n' '/' | cut -c1-160)"
[ -f "$T/sent.jsonl" ] && bad "T11 저장 실패인데 완료쪽지를 보냈다" || ok "T11 저장 실패 → 완료송신 0"

# ── T12(반례③) 실제 watcher argv(python3 -u - <bin> <좌석>)를 감시 있음으로 본다
rm -f "$T/sent.jsonl"
out="$(run)"; rc=$?
printf '%s\n' "$out" | grep -q '^INBOX-WATCH 4242 .*감시 중' && ok "T12 python3 -u - argv → 감시 중" || bad "T12 사용: $(printf '%s\n' "$out" | grep '^INBOX-WATCH')"
printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && ok "T12 감시 있음이면 결정 필요 0" || bad "T12 마지막 줄: $(printf '%s\n' "$out" | tail -1)"
export FAKE_PS="4242 python3 -u - /other/place.py"
out="$(run)"; rc=$?
export FAKE_PS="$PSLINE"
printf '%s\n' "$out" | grep -q '^INBOX-WATCH 없음' && ok "T12 남의 좌석 watcher 는 감시 아님" || bad "T12 오탐: $(printf '%s\n' "$out" | grep '^INBOX-WATCH')"
export FAKE_PS="4242 /opt/homebrew/Cellar/python@3.14/3.14.0/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python -u - $T/root/.fable-team/bin $DESK"
out="$(run)"; rc=$?
export FAKE_PS="$PSLINE"
printf '%s\n' "$out" | grep -q '^INBOX-WATCH 4242 .*감시 중' && ok "T12 이 Mac 실제 argv(Python.app -u - <bin> <좌석>)도 감시 중" || bad "T12 실제 argv 미탑지: $(printf '%s\n' "$out" | grep '^INBOX-WATCH')"

# ── T13(반례⑤) 전체 예산 0 = 어떤 하위 명령도 안 돌리고 전 항목 판정 불가 rc=124 · rc1
rm -f "$T/launch.log" "$T/sent.jsonl"
export FAKE_LAUNCH_LOG="$T/launch.log" FT_DESK_TICK_BUDGET=0
out="$(run)"; rc=$?
unset FAKE_LAUNCH_LOG FT_DESK_TICK_BUDGET
[ "$rc" -eq 1 ] && ok "T13 예산 0 → rc1" || bad "T13 rc=$rc"
[ -f "$T/launch.log" ] && bad "T13 예산 0 인데 launchctl 을 불렀다" || ok "T13 예산 0 → 하위 명령 0"
n124="$(printf '%s\n' "$out" | grep -c '판정 불가 rc=124')"
[ "${n124:-0}" -ge 6 ] && ok "T13 «판정 불가 rc=124» ${n124}줄 ≥6" || bad "T13 124 줄 ${n124}개"
printf '%s\n' "$out" | tail -1 | grep -qE '^결정 필요: ([6-9]|[1-9][0-9]+)$' && ok "T13 결정 필요 ≥6" || bad "T13 마지막 줄: $(printf '%s\n' "$out" | tail -1)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
