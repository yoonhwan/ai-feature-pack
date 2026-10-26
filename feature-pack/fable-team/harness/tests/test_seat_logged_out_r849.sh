#!/usr/bin/env bash
# test_seat_logged_out_r849.sh — r849 로그아웃 좌석: ⓐ~ⓔ + DA⑥ r1 반례 3 + 재설계 r4 칸(ⓡ1·ⓡ1b·ⓡ3) = tests/scripts/test_seat_logged_out_r849.py · ⓕ 변이 10종(사본 bin 에서 한 곳씩 지우면 그 시험이 FAIL)
# 격리: 합성 jsonl · 가짜 명부·tmux·mbox·seat-status(임시 폴더) — 실 좌석 깨우기·ring·쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; PY="$HERE/scripts/test_seat_logged_out_r849.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_py() { (cd "$HERE/scripts" && R849_BIN="$1" pytest -q -p no:cacheprovider "$PY" ${2:+-k "$2"} >"$T/py.log" 2>&1); }

run_py "$KIT"; ck "ⓐ~ⓔ $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?

# ⓕ 변이 — 사본 bin 의 한 줄을 지우면(무력화) 그 칸 시험이 FAIL 해야 한다
cp -Rp "$KIT" "$T/bin"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL ⓕ $1 — 변이 자리 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" "$5"; [ $? -ne 0 ]; ck "ⓕ $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "LOGGEDOUT 분기 삭제" ft_seat_turn.py '        if n:
            return "LOGGEDOUT"' '        if False:
            return "LOGGEDOUT"' test_a_logged_out
mutate "칸 있으면 0통 삭제" ft_stall_scan.py 'if self.cell(seat).exists():' 'if False:' test_c_tick_notifies_team_master_once
mutate "ring 제외(로그아웃) 삭제" ft-idle-wake.sh 'if state == "LOGGEDOUT":' 'if False:' test_d_idle_wake_skips_logged_out_and_rested
mutate "ring 제외(닫기 대기) 삭제" ft-idle-wake.sh '"ft_card_rest.py"), seat]).returncode == 0:' '"ft_card_rest.py"), seat]).returncode == 99:' test_d_idle_wake_skips_logged_out_and_rested
# DA⑥ r1 반례 3 — 고친 자리를 r1 꼴로 되돌리면 그 반례 시험이 FAIL
# (r1 변이 «키에 첫 실패 시각 되살림» 은 대상 줄이 재설계 r4 에서 사라짐 — 같은 사건-식별자 부류는 아래 «키에 시작 시각 되살림» 이 잡는다)
mutate "글자 찾기 되살림" ft-idle-wake.sh 'if run(["python3", os.path.join(HERE, "ft_card_rest.py"), seat]).returncode == 0:' 'if (j := run(["bash", STATUS, "jsonl", seat])).returncode == 0 and run(["bash", os.path.join(HERE, "ft-resume-attempt.sh"), "rested", j.stdout.strip()]).returncode == 0:' test_d_idle_wake_skips_logged_out_and_rested
mutate "칸 먼저 기록" ft_stall_scan.py '                log.append(f"{stamp} act=l ERROR 발신 실패' '                _ = self.cell(seat).write_text("x")
                log.append(f"{stamp} act=l ERROR 발신 실패' test_c_send_failure_retries_next_scan
# 재설계 r4 — 칸(로그아웃 구간당 1통)을 r2 꼴(키에 시작 시각)로 되돌리거나 지움을 지우면 그 시험이 FAIL
mutate "키에 시작 시각 되살림" ft_stall_scan.py 'f"logged-out.{seat}"' 'f"logged-out.{seat}.{int(self.now)}"' test_r1_unreadable_process_start_one_notice
mutate "칸 지움 삭제" ft_stall_scan.py 'self.cell(s).unlink(missing_ok=True)' 'pass' test_r1b_relogin_then_logout_two_notices_and_unreadable_scan_keeps_cell
mutate "③ 면제 삭제" ft-nano-close.sh '"$f" --skip-logged-out 2>&1' '"$f" 2>&1' test_e_nano_close_gate
mutate "[재개] 제외 삭제" ft_api_outage.py 'c is not None and c.cause != "logged_out"}' 'c is not None}' test_api_outage_never_resumes_logged_out

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일
for n in ft_api_outage_util.py ft_api_outage.py ft_seat_turn.py ft-seat-status.sh ft_stall_scan.py ft_stall_detect.py ft_card_rest.py ft-idle-wake.sh ft-jsonl-last-ts.py ft-nano-close.sh; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
echo "FAIL=$fail"; [ "$fail" = 0 ]
