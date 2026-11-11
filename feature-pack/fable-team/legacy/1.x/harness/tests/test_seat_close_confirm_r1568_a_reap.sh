#!/usr/bin/env bash
# test_seat_close_confirm_r1568_a_reap.sh — r1682 쪼갠 ①(reap 사슬): 짝·문법 확인 + ⓐ 사슬 · ⓑⓒ 계속 남는 자식 · 변이 M1·M2·M3.
#   ⓐ 짧은 자식 1번(3세대 사슬) = reap left=0 rc0 · 남은 사슬 0 — 마지막 정지가 없으면 left≥1(M1)
#   ⓑ 계속 남는 자식 = left≥1 rc=1 ⓒ 정지 횟수 상한 3(reap-kill 3줄 · M2 면 4줄+) · M3 남은 것을 rc0
#   픽스처·도구는 test_seat_close_confirm_r1568_fixtures.sh — 이 파일은 사례만 담는다(70초 안 · 하드 룰 22)
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_seat_close_confirm_r1568_fixtures.sh"

bash -n "$REAP" && ok "bash -n ft-seat-reap.sh" || bad "bash -n $REAP"
bash -n "$CLOSE" && ok "bash -n ft-seat-close.sh" || bad "bash -n $CLOSE"
cmp -s "$REAP" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"
cmp -s "$CLOSE" "$BIN/../kit/fable-team/bin/ft-seat-close.sh" && ok "짝 cmp0 ft-seat-close.sh" || bad "짝 다름 ft-seat-close.sh"

echo "== ⓐ 짧은 자식 1번(3세대 사슬) → reap left=0 rc=0 · 남은 사슬 0 (M1 마지막 정지 빼면 left≥1)"
spawn_faux "$S" "$MKX-a" - --gen 1 --max 3 --next "$MKX-a"
chk "ⓐ픽스처 1개" "$([ -n "$(pick "$MKX-a")" ] && echo 1)" 1
out="$(bash "$REAP" "$S")"; rc=$?
chk "ⓐleft=0 rc=0" "$rc $(endline "$out")" "0 left=0 rc=0"
chk "ⓐ남은 사슬 0" "$(wait_dead "$MKX-a"; pgrep -f "$MKX-a" | wc -l | tr -d ' ')" 0
mut M1 ft-seat-reap.sh 'for _ in range(3):' 'for _ in range(2):' || bad "M1 치환 실패"
spawn_faux "$S" "$MKX-m1" - --gen 1 --max 3 --next "$MKX-m1"
out="$(bash "$TMP/mb/M1/ft-seat-reap.sh" "$S")"; rc=$?
chk "M1 마지막 정지 빼면 left≥1 rc≠0(변이 잡힘)" "$rc $([ "$(endline "$out")" != "left=0 rc=0" ] && echo caught)" "1 caught"
kill_mk "$MKX-m1"

echo "== ⓑ 계속 남는 자식 = left≥1 rc=1 · ⓒ 정지 3회 상한 · M2 상한 없으면 4줄+ · M3 남은 것을 rc0"
spawn_faux "$S" "$MKX-b" -
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" "$S")"; rc=$?
chk "ⓑleft≥1 rc=1" "$rc $(endline "$out")" "1 left=1 rc=1"
chk "ⓒreap-kill 3줄(정지 3회 상한)" "$(nkills "$out")" 3
mut M2 ft-seat-reap.sh 'for _ in range(3):' 'for _ in range(12):' || bad "M2 치환 실패"
out="$(FT_REAP_NOSIGNAL=1 bash "$TMP/mb/M2/ft-seat-reap.sh" "$S")"; rc=$?
chk "M2 상한 없으면 정지 4줄+(변이 잡힘)" "$([ "$(nkills "$out")" -ge 4 ] && echo caught)" "caught"
mut M3 ft-seat-reap.sh 'rc = 1 if left else 0' 'rc = 0' || bad "M3 치환 실패"
out="$(FT_REAP_NOSIGNAL=1 bash "$TMP/mb/M3/ft-seat-reap.sh" "$S")"; rc=$?
chk "M3 남은 것을 rc0 으로(변이 잡힘)" "$rc $(grep -qE 'left=[1-9]' <<< "$out" && echo left)" "0 left"
kill_mk "$MKX-b"

finish
