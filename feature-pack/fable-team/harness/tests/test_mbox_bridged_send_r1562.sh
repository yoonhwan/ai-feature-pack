#!/usr/bin/env bash
# test_mbox_bridged_send_r1562.sh — r1562: 다른 루트 좌석에 보낸 쪽지(BRIDGED)는 보낸 쪽 mbox.sh 가
#   doorbell·inbox 적재·깨움 예산을 건드리지 않는다(받는 루트 mbox.sh 가 이미 자기 명부로 판정·주입).
#   본문 = tests/scripts/test_mbox_bridged_send_r1562.py (사례 ⓐ~ⓕ 6) · 변이 M0~M4 5종(사본 치환 → 그 시험 FAIL → 복구)
#   + 기존 mbox 시험 rc 불변(다리 4종 · 인박스 적재) + 새 시험 모드 644 · 재진입 표지 lint.
# 격리: 실 우편함·실 tmux·실 /tmp 상태·실 launchd 0 — 가짜 tmux(comm 사본 안) · 가짜 ft-inbox.sh 만.
# ★rc 는 «명령이 낸 값» 을 먼저 변수로 받는다★ — ck "…$(grep…)" $? 꼴은 $? 가 뒤 명령 rc 를 받아 실패를 PASS 로 찍는다(r1309 REWORK r1 반례 2).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="$HERE/../comm"; SC="$HERE/scripts"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
now() { date +%s; }
secs() { echo "$(( $(now) - $1 ))초"; }
cp -Rp "$COMM" "$T/comm"
run_py() {  # $1 = comm 사본 · $2 = -k 식(선택) — 로그 파일명은 호출마다 새 번호
  local c="$1" k="${2:-}" log
  n=$((n + 1)); log="$T/py-$n.log"
  if [ -n "$k" ]; then ( cd "$SC" && R1562_COMM="$c" timeout 70 pytest -q -p no:cacheprovider test_mbox_bridged_send_r1562.py -k "$k" >"$log" 2>&1 )
  else ( cd "$SC" && R1562_COMM="$c" timeout 70 pytest -q -p no:cacheprovider test_mbox_bridged_send_r1562.py >"$log" 2>&1 ); fi
  cp -p "$log" "$T/py.last.log"; return $?
}

t=$(now); run_py "$T/comm"; rc=$?
ck "ⓐ~ⓕ $(grep -Eo '[0-9]+ passed' "$T/py.last.log") $(secs "$t")" "$rc"

# 변이 — 사본의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
mutate() {  # $1 이름 $2 원문(고정 문자열) $3 바꿀 글 $4 -k(선택)
  python3 - "$T/comm/mbox.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  t=$(now); run_py "$T/comm" "${4:-}"; rc=$?; [ "$rc" -ne 0 ]; ck "변이 $1 → $(grep -Eo '[0-9]+ failed' "$T/py.last.log") FAIL $(secs "$t")" $?
  cp -p "$COMM/mbox.sh" "$T/comm/mbox.sh"
}
SEND_BLOCK='    case "$py_out" in BRIDGED*)   # ★r1562 — 다른 루트로 간 쪽지면 여기서 끝난다★(사유는 bridged_out 주석 · rsv = 이 게이트가 «예약을 실제로 했나»)
      case "$gate" in sent) if [ "${urgent}${uf}${ew}" = 000 ] && ! _wg_human_sender "$from" && case "$head" in '\''[긴급]'\''|'\''[인계]'\''|'\''[레디]'\'') false;; *) true;; esac; then rsv=1; fi;; esac
      [ -z "$SK" ] || bash "$SE" commit "$SK" --ref "bridged seq $seq" >/dev/null || true
      bridged_out "$py_out" "$gate" "${rsv:-0}"; exit 0;;
    esac'
RELAY_LINE='    case "$py_out" in BRIDGED*)   # r1562 — rsv 규칙은 send 절과 같다(relay 도 py 에서 send 를 탄다)
      case "$gate" in sent) if [ "${urgent}${uf}${ew}" = 000 ] && ! _wg_human_sender "$from" && case "$head" in '\''[긴급]'\''|'\''[인계]'\''|'\''[레디]'\'') false;; *) true;; esac; then rsv=1; fi;; esac
      bridged_out "$py_out" "$gate" "${rsv:-0}"; exit 0;; esac'
REFUND_LINE='  if [ "$3" = 1 ]; then wake_budget_refund "$dbto" send >/dev/null 2>&1 || true; fi'
# M0 사전 대조 = 고치기 «전» 동작(보낸 쪽이 자기 경로를 한 번 더 친다) — 두 분기를 다 빼면 그 상태가 된다
python3 - "$T/comm/mbox.sh" "$SEND_BLOCK" "$RELAY_LINE" <<'PY' || { echo "FAIL 변이 M0 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
for blk in (a, b):
    assert s.count(blk) == 1, s.count(blk)
    s = s.replace(blk, "")
open(p, "w", encoding="utf-8").write(s)
PY
t=$(now); run_py "$T/comm"; rc=$?; [ "$rc" -ne 0 ] && [ "$(grep -cE '^FAILED .*test_case_(a|b|c|e)_' "$T/py.last.log")" = 4 ]
ck "변이 M0 사전 대조 → $(grep -Eo '[0-9]+ failed' "$T/py.last.log") FAIL(ⓐⓑⓒⓔ) $(secs "$t")" $?
cp -p "$COMM/mbox.sh" "$T/comm/mbox.sh"
mutate "M1 send 분기 제거" "$SEND_BLOCK" "" "case_a or case_b"
mutate "M2 예산 되돌림 제거" "$REFUND_LINE" '  :' "case_c"
mutate "M3 relay 분기 제거" "$RELAY_LINE" "" "case_e"
# M4 = rsv 무시(arch#277 반례 그 자리): 예약이 없던 sent(--urgent · 머리 [긴급])에도 되돌림 → 보낸 쪽 장부가 줄어든다
mutate "M4 rsv 무시(예약 없는 sent 도 되돌림)" "$REFUND_LINE" '  if [ "$2" = sent ]; then wake_budget_refund "$dbto" send >/dev/null 2>&1 || true; fi' "case_c"

# ⓖ 기존 mbox 시험 rc 불변 — 다리 4종(r1309 X10 계열) · 인박스 적재
( cd "$SC" && ulimit -u 2000; R1309_BIN="$KIT" R1309_COMM="$COMM" timeout 70 pytest -q -p no:cacheprovider \
    test_roots_registry_r1309.py -k "r6 or r7 or r8 or r9" >"$T/r1.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 r1309 다리 4종 $(grep -Eo '[0-9]+ passed' "$T/r1.log")" "$rc"
( ulimit -u 2000; timeout 70 bash "$HERE/test_ft_mbox_inbox_ingest.sh" >"$T/r2.log" 2>&1 ); rc=$?
ck "ⓖ 회귀 인박스 적재 $(tail -1 "$T/r2.log")" "$rc"

# 새 시험 모드 644(실행 비트 0 — bash·pytest 로 부른다) · 재진입 표지 lint
[ "$(stat -f %Lp "$HERE/test_mbox_bridged_send_r1562.sh")" = 644 ]; ck "새 시험 모드 644(셸)" $?
[ "$(stat -f %Lp "$SC/test_mbox_bridged_send_r1562.py")" = 644 ]; ck "새 시험 모드 644(py)" $?
bash "$KIT/ft-test-reentry-lint.sh" "$SC/test_mbox_bridged_send_r1562.py" >/dev/null 2>&1; ck "재진입 표지 lint rc0" $?
bash -n "$COMM/mbox.sh"; ck "mbox.sh bash -n" $?
echo "새 시험 $(wc -l <"$SC/test_mbox_bridged_send_r1562.py" | tr -d ' ')줄 · 사례 ⓐ~ⓕ 6 + 변이 M0~M4"
echo "FAIL=$fail"; [ "$fail" = 0 ]
