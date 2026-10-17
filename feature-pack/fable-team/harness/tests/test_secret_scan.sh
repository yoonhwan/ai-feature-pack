#!/usr/bin/env bash
# test_secret_scan.sh — ft-secret-scan.sh 세션 기록 사후 스캔 (R135b ③ · 판정 1585 «위치만»)
# 격리: 임시 HOME(가짜 ~/.claude/projects·~/.codex/sessions) + 가짜 mbox · 실 세션 기록 읽기 0 · 실 /tmp/h* 읽기 0(--plans 명시). 값은 전부 가짜.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SC="$HERE/../../scripts/fable-team-bin/ft-secret-scan.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" FT_SECRET_SCAN_ROOT="$T/root" FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json"
CL="$HOME/.claude/projects/x/a.jsonl"; CX="$HOME/.codex/sessions/2026/10/17/rollout-a.jsonl"; PLAN="$T/plan.sh.hil"
LOG="$HOME/.fable-team/state/secret-scan.log"; ST="$HOME/.fable-team/state/secret-scan.state"
mkdir -p "$(dirname "$CL")" "$(dirname "$CX")" "$T/root"
printf '{"stdout":"conn postgres://u:FAKEPW1234@h/db ok"}\n{"stdout":"clean"}\n' > "$CL"
printf '{"out":"tok ghp_FAKEA1b2C3d4E5f6G7h8I9j0K1l2M3n4"}\n' > "$CX"
printf '#!/bin/bash\ngcloud secrets versions access x\n' > "$PLAN"
echo '{"_hil_route":"planner-test#1"}' > "$FT_SEATS_JSON"
cat > "$T/mbox.sh" <<'EOF'
#!/bin/bash
[ -f "$(dirname "$0")/mbox.fail" ] && exit 1
printf 'to=%s from=%s\n%s\n--\n' "$2" "$3" "$4" >> "$(dirname "$0")/mbox.rec"
EOF
fail=0; out=""; rc=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
run() { out="$(bash "$SC" "$@" 2>"$T/err")"; rc=$?; }
nomsg() { [ "$(grep -c '^to=' "$T/mbox.rec" 2>/dev/null || true)" = "$1" ]; }
novalue() { ! grep -q -e FAKEPW -e FAKEA1b2 "$@"; }

bash -n "$SC"; ck "bash -n" $?
run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'SCAN read=3 skipped=0 new=3' <<<"$out"; ck "첫 실행: 3파일 읽음 · 새 3건(url-cred · token-prefix · plan)" $?
grep -q "a.jsonl:1 url-cred" "$LOG" && grep -q "rollout-a.jsonl:1 token-prefix" "$LOG" && grep -q "plan.sh.hil:2 plan:" "$LOG"; ck "원장: 파일:줄 종류 3줄" $?
novalue "$LOG" "$T/mbox.rec" "$T/err" <<<"$out"; ck "값 0: 원장·쪽지·stderr" $?
printf '%s' "$out" | novalue /dev/stdin; ck "값 0: 표준출력" $?
nomsg 1 && grep -q 'to=planner-test#1 from=ft-secret-scan' "$T/mbox.rec" && grep -q '^\[HIL\] 비밀 기록 스캔 — 새 3건' "$T/mbox.rec"; ck "쪽지: planner 앞 [HIL] 묶음 1통(3건)" $?
run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'SCAN read=0 skipped=3 new=0' <<<"$out" && nomsg 1; ck "증분: 두 번째 실행 읽은 파일 0 · 새 쪽지 0" $?
printf '{"stdout":"PGPASSWORD=FAKEnew123"}\n' >> "$CL"
run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'SCAN read=1 skipped=2 new=1' <<<"$out" && nomsg 2; ck "바뀐 파일만 다시 읽음 · 옛 적중 재보고 0 · 새 1건 쪽지" $?
run --report
[ "$rc" = 0 ] && grep -q '^비밀 기록 스캔: 새 1건 · 마지막 실행 20' <<<"$out" && nomsg 2; ck "--report: 한 줄 · 쪽지 0 · 스캔 0" $?
cp "$ST" "$T/st.ok"; before="$(wc -l < "$LOG")"; echo '{깨짐' > "$ST"
run --plans "$PLAN"
[ "$rc" = 4 ] && grep -q 'ERROR' "$T/err" && [ "$(wc -l < "$LOG")" = "$before" ]; ck "상태 파일 손상 → ERROR rc 4 · 전수 재스캔 0 · 원장 그대로" $?
cp "$T/st.ok" "$ST"
printf '{"stdout":"tok ya29.FAKEA1b2C3d4E5f6G7h8I9j0K1"}\n' >> "$CX"; touch "$T/mbox.fail"
run --plans "$PLAN"
[ "$rc" = 5 ] && grep -q ERROR "$T/err"; ck "쪽지 실패 → ERROR rc 5" $?
rm "$T/mbox.fail"; run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'new=1' <<<"$out" && nomsg 3; ck "쪽지 실패 뒤 다음 실행이 다시 보냄(상태 미갱신)" $?
SS="$HOME/.claude/projects/x/same-sec.jsonl"  # H3 — 같은 초 안 두 번 수정(길이 같음)도 놓치지 않는다
settime() { python3 -I -c 'import os,sys; t=int(sys.argv[2]); os.utime(sys.argv[1], ns=(t, t))' "$SS" "$1"; }
# shellcheck disable=SC2016
printf '{"stdout":"PGPASSWORD=$FAKEbbb22"}\n' > "$SS"; settime 1760000000100000000
run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'SCAN read=1 skipped=3 new=0' <<<"$out"; ck "H3 준비: 자리표시자 파일 첫 읽기 · 새 0건" $?
printf '{"stdout":"PGPASSWORD=FAKEbbb222"}\n' > "$SS"; settime 1760000000600000000
run --plans "$PLAN"
[ "$rc" = 0 ] && grep -q 'SCAN read=1 skipped=3 new=1' <<<"$out" && nomsg 4; ck "H3: 같은 초 두 번째 수정도 read=1 new=1 · 쪽지 1통" $?
novalue "$LOG" "$T/mbox.rec" "$T/err"; ck "끝까지 값 0" $?
[ "$(grep -c 'Users/yoonhwan' "$T/mbox.rec" || true)" = 0 ]; ck "실 HOME 기록 읽기 0(임시 HOME 경로만)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
[ "$fail" = 0 ]
