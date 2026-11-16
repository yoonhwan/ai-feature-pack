#!/usr/bin/env bash
# test_desk_tick_late_send_r2137.sh — ft-desk-tick.sh ⑥ 완료쪽지 늦은 확인(r2137).
#   ① send 가 이 회차 [완료] 줄을 LOG 에 쓰고 10초 잠 → «늦은 확인 rc=124» · 판정 불가 0 · rc0 · 이 회차 줄 1개 (T1)
#   ② send 가 쓰지 않고 10초 잠 → «완료쪽지 판정 불가 rc=124» · rc1 (T1)
#   ③ LOG 에 같은 좌석·같은 받는 이의 다른 회차 줄 + ② → 판정 불가 rc=124 · rc1 (T2)
#   ④ BUDGET=12 · hil · launchctl 7초 잠 · send 6초 뒤 성공 → «완료쪽지 → (3줄)» (T3)
#   ⑤ 정상 틱 → «초:» 줄 1개 · 칸 7개 · 그 다음 줄 = 마지막 «결정 필요: N» (T4)
#   ⑥b 결속 불일치 + LOG 에 이 회차 줄 → send 0 · 늦은 확인 0 · 완료쪽지 줄 0 (T5 · 나머지 T5 = 기존 시험 재실행)
#   ⑦ 예산 0(r1462 T13) × T4 → hil·ps·send 호출 0 · «초:» 6칸 모두 «-» (DA #322039 HOLD 보정)
# 전부 합성(임시 루트 · 가짜 mbox·hil·launchctl·ps · 고정 NOW) · 실 우편함·실 launchctl·실 tmux 0.
# 잠은 시험 대상 계약(7초 상한)을 재는 가짜 명령 안에만 있다.
# env: R2137_BIN = 시험할 bin 폴더(변이 사본·기준판용) · R2137_CASES = 돌릴 사례(기본 "1 2 3 4 5 6 7")
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="${R2137_BIN:-$HERE/../bin}/ft-desk-tick.sh"
CASES=" ${R2137_CASES:-1 2 3 4 5 6 7} "
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$CASES" in *" $1 "*) return 0;; esac; return 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$S" ] || { echo "FAIL ft-desk-tick.sh 없음: $S"; exit 1; }

NOW=1794103664; NOWISO=2026-11-08T02:07:44Z
DESK='byz-planner-desk-claude#121'; PLANNER='byz-planner-master-claude#240'
R="$T/root/.fable-team"; LOG="$R/comm/mailbox.log.jsonl"
mkdir -p "$R/comm" "$T/fakebin" "$T/hil" "$T/state"
# 가짜 mbox send: FAKE_SEND = write_sleep(줄 쓰고 10초) · sleep(10초) · late6(6초 뒤 쓰고 성공) · 그 밖 = 즉시 쓰고 성공
cat > "$R/comm/mbox.sh" <<'EOS'
#!/usr/bin/env bash
w() { python3 - "$FAKE_LOG" "$1" "$2" "$3" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"seq": 9, "ts": "x", "to": sys.argv[2], "from": sys.argv[3], "body": sys.argv[4]}, ensure_ascii=False) + "\n")
PY
}
case "${1:-}" in
  send) shift; printf 'send\n' >> "$FAKE_CALLS"
        case "${FAKE_SEND:-}" in
          write_sleep) w "$1" "$2" "$3"; exec sleep 10;;
          sleep) exec sleep 10;;
          late6) sleep 6; w "$1" "$2" "$3";;
          *) w "$1" "$2" "$3";;
        esac
        echo "QUEUED seq=9 to=$1"; exit 0;;
  recv) echo "SCANNED 1 mailbox(es): fake"; exit 0;;
esac
exit 2
EOS
printf '#!/usr/bin/env bash\n[ -n "${FAKE_SLOW:-}" ] && exec sleep 7\nexit 0\n' > "$T/hil/ft-hil.sh"
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_SLOW:-}" ] && exec sleep 7
printf '%s\n\tstate = running\n\tlast exit code = 0\n' "$2"
EOS
printf '#!/usr/bin/env bash\necho "4242 python3 -u - /x %s"\n' "$DESK" > "$T/fakebin/ps"
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps"
printf 'ts=%s stall=0\n' "$NOW" > "$T/stall.log"
( cd "$T/root" && git init -q && mkdir -p design/teams/planner && printf '## 골 진행\n\n| 1 | a |\n\n## 끝\n' > design/teams/planner/PLAN-oppa-ledger.md && git add design && git -c user.email=t@t -c user.name=t commit -qm t && git update-ref refs/remotes/origin/main HEAD && git update-ref refs/remotes/origin/ops/main-base HEAD )

reset() {  # reset <_desk> — 결속 파일 · 빈 LOG · 호출 기록 초기화
  printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$1" > "$R/seats-planner.json"
  printf '{"ts":"2026-11-08T02:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$LOG"
  : > "$T/calls"
}
run() {
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$R/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" FT_DESK_TICK_STALL_LOG="$T/stall.log" \
      FT_DESK_TICK_LOG="$LOG" FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 FT_DESK_TICK_STATE_DIR="$T/state" \
      FAKE_LOG="$LOG" FAKE_CALLS="$T/calls" bash "$S" "$DESK" 2>&1
}
nround() { grep -c "회차: $NOWISO" "$LOG" | tr -d ' '; }
ncalls() { grep -c send "$T/calls" | tr -d ' '; }
flat() { printf '%s' "$1" | tr '\n' '/'; }

if has 1; then
  reset "$DESK"; s=$(date +%s)
  out="$(FAKE_SEND=write_sleep run)"; rc=$?
  echo "TIME ① $(( $(date +%s) - s ))s"
  printf '%s\n' "$out" | grep -qx "완료쪽지 → $PLANNER (3줄 · 늦은 확인 rc=124)" && ok "① 늦은 확인 rc=124 1줄" || bad "① 늦은 확인 줄 없음: $(flat "$out")"
  printf '%s\n' "$out" | grep -q '판정 불가' && bad "① 판정 불가 줄이 있다" || ok "① 판정 불가 0"
  [ "$rc" -eq 0 ] && ok "① rc0" || bad "① rc=$rc"
  [ "$(nround)" = 1 ] && [ "$(ncalls)" = 1 ] && ok "① 이 회차 줄 1개 · send 1회" || bad "① 회차 줄 $(nround) · send $(ncalls)"
fi

if has 2; then
  reset "$DESK"; s=$(date +%s)
  out="$(FAKE_SEND=sleep run)"; rc=$?
  echo "TIME ② $(( $(date +%s) - s ))s"
  printf '%s\n' "$out" | grep -qx '완료쪽지 판정 불가 rc=124' && ok "② 판정 불가 rc=124" || bad "② $(flat "$out")"
  printf '%s\n' "$out" | grep -q '늦은 확인' && bad "② 늦은 확인이 나왔다" || ok "② 늦은 확인 0"
  [ "$rc" -eq 1 ] && ok "② rc1" || bad "② rc=$rc"
fi

if has 3; then
  reset "$DESK"
  printf '{"seq":1,"ts":"x","to":"%s","from":"%s","body":"[완료] desk 틱\\n남은 일\\n회차: 2026-11-08T01:52:44Z · 좌석 x"}\n' "$PLANNER" "$DESK" >> "$LOG"
  printf '{"seq":2,"ts":"x","to":"%s","from":"other-desk#1","body":"[완료]\\n회차: %s"}\n' "$PLANNER" "$NOWISO" >> "$LOG"
  printf '{"seq":3,"ts":"x","to":"other-master#1","from":"%s","body":"[완료]\\n회차: %s"}\n' "$DESK" "$NOWISO" >> "$LOG"
  s=$(date +%s)
  out="$(FAKE_SEND=sleep run)"; rc=$?
  echo "TIME ③ $(( $(date +%s) - s ))s"
  printf '%s\n' "$out" | grep -qx '완료쪽지 판정 불가 rc=124' && ok "③ 다른 회차·좌석·받는 이 줄 → 판정 불가 rc=124" || bad "③ $(flat "$out")"
  [ "$rc" -eq 1 ] && ok "③ rc1" || bad "③ rc=$rc"
fi

if has 4; then
  reset "$DESK"; s=$(date +%s)
  out="$(FT_DESK_TICK_BUDGET=12 FAKE_SLOW=1 FAKE_SEND=late6 run)"; rc=$?
  el=$(( $(date +%s) - s )); echo "TIME ④ ${el}s"
  printf '%s\n' "$out" | grep -qx "완료쪽지 → $PLANNER (3줄)" && ok "④ ⑥ 몫 7초 → 6초 send 성공" || bad "④ $(flat "$out")"
  nf="$(printf '%s\n' "$out" | grep -c '판정 불가')"; [ "$nf" -ge 1 ] && [ "$rc" -eq 1 ] && ok "④ 앞 항목 판정 불가 ${nf}건 · rc1 유지" || bad "④ 판정 불가 $nf · rc=$rc"
  [ "$el" -le 13 ] && ok "④ 소요 ${el}초 ≤ 예산 12(+1)" || bad "④ 소요 ${el}초"
fi

if has 5; then
  reset "$DESK"; s=$(date +%s)
  out="$(run)"; rc=$?
  echo "TIME ⑤ $(( $(date +%s) - s ))s"
  n="$(printf '%s\n' "$out" | grep -c '^초: ')"
  sl="$(printf '%s\n' "$out" | tail -2 | head -1)"
  [ "$n" = 1 ] && ok "⑤ «초:» 줄 1개" || bad "⑤ «초:» 줄 ${n}개"
  printf '%s\n' "$sl" | grep -qE '^초: ① ([0-9]+|-) · ② ([0-9]+|-) · ③ ([0-9]+|-) · ④ ([0-9]+|-) · ⑤ ([0-9]+|-) · ⑥ ([0-9]+|-) · 전체 [0-9]+/25$' \
    && ok "⑤ 칸 7개 · 끝에서 둘째 줄: $sl" || bad "⑤ 끝에서 둘째 줄: $sl"
  printf '%s\n' "$out" | tail -1 | grep -qx '결정 필요: 0' && [ "$rc" -eq 0 ] && ok "⑤ 마지막 줄 «결정 필요: 0» · rc0" || bad "⑤ 마지막 $(printf '%s\n' "$out" | tail -1) rc=$rc"
  out="$(FT_DESK_TICK_MAX_LINES=5 run)"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 5 ] && printf '%s\n' "$out" | tail -2 | head -1 | grep -q '^초: ' && printf '%s\n' "$out" | tail -1 | grep -q '^결정 필요: ' \
    && ok "⑤ 접기 5줄 · «초:» · «결정 필요» 마지막 2줄 보존" || bad "⑤ 접기: $(flat "$out")"
fi

if has 6; then
  reset 'byz-other-desk#1'
  printf '{"seq":1,"ts":"x","to":"%s","from":"%s","body":"[완료]\\n회차: %s"}\n' "$PLANNER" "$DESK" "$NOWISO" >> "$LOG"
  out="$(FAKE_SEND=sleep run)"; rc=$?
  [ "$(ncalls)" = 0 ] && ok "⑥b 결속 불일치 → send 0" || bad "⑥b send $(ncalls)회"
  printf '%s\n' "$out" | grep -q '^완료쪽지' && bad "⑥b 완료쪽지 줄이 있다: $(flat "$out")" || ok "⑥b 늦은 확인 0 · 완료쪽지 줄 0"
  printf '%s\n' "$out" | grep -qx '결속 판정 불가 rc=9' && [ "$rc" -eq 1 ] && ok "⑥b 결속 판정 불가 rc=9 · rc1" || bad "⑥b $(flat "$out") rc=$rc"
fi

if has 7; then
  reset "$DESK"
  out="$(FT_DESK_TICK_BUDGET=0 run)"; rc=$?
  [ "$(ncalls)" = 0 ] && ok "⑦ 예산 0 → send 0" || bad "⑦ send $(ncalls)회"
  sl="$(printf '%s\n' "$out" | grep '^초: ')"
  printf '%s\n' "$sl" | grep -qE '^초: ① - · ② - · ③ - · ④ - · ⑤ - · ⑥ - · 전체 [0-9]+/0$' && ok "⑦ 실행 0 → 초 칸 6개 모두 «-»: $sl" || bad "⑦ 초 줄: $sl"
  [ "$rc" -eq 1 ] && ok "⑦ rc1" || bad "⑦ rc=$rc"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
