#!/usr/bin/env bash
# test_mbox_send_utf8_reject_r1678.sh — r1678: 본문이 UTF-8 이 아니면 가드 «맨 앞»에서 사유 1줄 + rc 3(큐 적재 0) · 판정기 고장은 rc 2(판정 불가).
# 사례 ⓐ 입구 검사 · ⓑ 경계(정상 한글 2.3KB 통과 / 끝 1바이트 잘린 3바이트 문자 거부) · ⓒ 판정기 고장 rc2 · ⓓ 빈 사유 0 · ⓔ 회귀 3파일.
# 격리 = 임시 폴더 사본(실 우편함·실 doorbell·실 pane 쓰기 0). 사례 1개 = timeout 70 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; FX="$REPO/tests/fixtures/mbox_guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"

new_env() {   # 격리 루트 1개 = 정본 사본 + ok 명부(받는이 = byz-planner-master-claude#9)
  E="$T/env.$1"; mkdir -p "$E/.fable-team/comm" "$E/.fable-team/state" "$E/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$E/.fable-team/comm/"
  cp "$FX/ok"/seats*.json "$E/seats/"; git -C "$E" init -q
}
send_b() {   # send_b <to> <body> — rc·출력 = RC·OUT
  OUT="$(cd "$E" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$E/seats/seats.json" \
    FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$E/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$E/.fable-team/comm/mbox.sh" send "$1" "me#1" "$2" 2>&1)"; RC=$?
}
queued() { local n; n="$(grep -c "\"to\": *\"$1\"" "$E/.fable-team/comm/mailbox.jsonl" 2>/dev/null || true)"; echo "${n:-0}"; }
relay_b() {   # relay_b <to> <attach> <summary>
  OUT="$(cd "$E" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$E/seats/seats.json" \
    FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$E/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$E/.fable-team/comm/mbox.sh" relay "$1" "me#1" "$2" "$3" 2>&1)"; RC=$?
}
TO='byz-planner-master-claude#9'
HEAD='[HIL] r1678 본문 인코딩 시험'
REQ='①막힌 명령: 없음'
body_hil() { printf '%s\n%s\n②막은 훅: 없음\n④선택지: 그대로·중단\n' "$HEAD" "$REQ"; }

# ── ⓐ UTF-8 입구 검사: 0xBB 단독(2026-11-11 planner 실사건 꼴) — 받는이 판정보다 먼저 막는다(명부 깨짐·받는이 무관하게 rc 3)
new_env a
BAD="$(body_hil)$(printf 'HEAD $H\xbb 끝')"
want_pos="$(printf '%s' "$BAD" | python3 -c 'import sys; b=sys.stdin.buffer.read(); print(b.index(b"\xbb"))')"
send_b "$TO" "$BAD"
case "$OUT" in *"본문이 UTF-8 이 아니다 — 바이트 위치 $want_pos"*) ok "ⓐ 사유 = 바이트 위치 $want_pos";; *) bad "ⓐ 바이트 위치 :: $OUT";; esac
case "$OUT" in *'${이름} 으로 감싸라'*) ok "ⓐ 고칠 꼴 안내";; *) bad "ⓐ 고칠 꼴 없음 :: $OUT";; esac
[ "$RC" = 3 ] && ok "ⓐ rc=3" || bad "ⓐ rc=$RC want=3"
[ "$(queued "$TO")" = 0 ] && ok "ⓐ 큐 적재 0" || bad "ⓐ 큐 적재 $(queued "$TO")"
case "$OUT" in REJECT\ *) ok "ⓐ REJECT 1줄";; *) bad "ⓐ 머리 아님 :: $OUT";; esac

# ── ⓐ-relay: relay 첨부 파일도 같은 검사(실 파일 안 씀 · 임시 사본)
new_env ar
printf '[HIL] relay 시험\n①막힌 명령: 없음\n②막은 훅: 없음\n④선택지: 그대로·중단\nBAD \273\n' > "$T/bad_attach.txt"
relay_b "$TO" "$T/bad_attach.txt" "$(body_hil)"
[ "$RC" = 3 ] && ok "ⓐ relay 첨부 rc=3" || bad "ⓐ relay 첨부 rc=$RC want=3"
case "$OUT" in *"relay 첨부가 UTF-8 이 아니다"*) ok "ⓐ relay 첨부 사유";; *) bad "ⓐ relay 첨부 사유 없음 :: $OUT";; esac
[ "$(queued "$TO")" = 0 ] && ok "ⓐ relay 큐 적재 0" || bad "ⓐ relay 큐 적재 $(queued "$TO")"

# ── ⓑ 경계: 정상 한글 2.3KB(2194 바이트 경계 포함) = QUEUED · 끝 1바이트 잘린 3바이트 문자 = REJECT
new_env b
BIG="$(python3 -c 'import sys; sys.stdout.write("[HIL] 큰 본문\n①막힌 명령: 없음\n②막은 훅: 없음\n④선택지: 그대로·중단\n" + "가나다라마바사 " * 160)')"
blen="$(printf '%s' "$BIG" | wc -c | tr -d ' ')"
[ "$blen" -ge 2280 ] && ok "ⓑ 본문 ${blen}B (경계 2194 포함)" || bad "ⓑ 본문 ${blen}B < 2280 (경계 미포함)"
send_b "$TO" "$BIG"; [ "$RC" = 0 ] && ok "ⓑ 정상 한글 ${blen}B rc=0" || bad "ⓑ 정상 한글 ${blen}B rc=$RC :: $OUT"
[ "$(queued "$TO")" = 1 ] && ok "ⓑ QUEUED" || bad "ⓑ 큐 적재 $(queued "$TO")"
TRUNC="$(body_hil)$(printf '끝 글자 한\xea\xb0')"   # '각'(EA B0 81)의 마지막 1바이트를 자름
send_b "$TO" "$TRUNC"
[ "$RC" = 3 ] && ok "ⓑ 잘린 3바이트 문자 rc=3" || bad "ⓑ 잘린 문자 rc=$RC want=3"
case "$OUT" in *"바이트 위치"*) ok "ⓑ 잘린 문자 사유";; *) bad "ⓑ 잘린 문자 사유 없음 :: $OUT";; esac
[ "$(queued "$TO")" = 1 ] && ok "ⓑ 잘린 문자 큐 적재 0(1 유지)" || bad "ⓑ 잘린 문자 큐 적재 $(queued "$TO")"

# ── ⓒ 판정기 고장 = rc 2(판정 불가) — rc 1 은 위반일 때만
OLD="$(printf '! bash /tmp/h7')"; [ "$(printf '%s' "$OLD" | python3 "$SRC/bang_command_check.py" >/dev/null 2>&1; echo $?)" = 0 ] && ok "ⓒ 정상 입력 rc=0" || bad "ⓒ 정상 입력 rc≠0"
c_out="$(printf '%s\xbb' "$OLD" | python3 "$SRC/bang_command_check.py" 2>&1)"; c_rc=$?
[ "$c_rc" = 2 ] && ok "ⓒ 디코드 실패 rc=2" || bad "ⓒ 디코드 실패 rc=$c_rc want=2"
case "$c_out" in "판정 불가 UnicodeDecodeError"*) ok "ⓒ 판정 불가 1줄";; *) bad "ⓒ 문구 :: $c_out";; esac

# ── ⓓ 빈 사유 0: 판정기가 rc 1 + 빈 stdout 이면 가드는 «사유 없음 … 판정 불가» 로 적는다(하드 룰 20)
new_env d
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$E/.fable-team/comm/bang_command_check.py"
send_b "$TO" "$(body_hil)"
[ "$RC" = 3 ] && ok "ⓓ 빈 사유 rc=3" || bad "ⓓ 빈 사유 rc=$RC want=3"
case "$OUT" in *"REJECT 오빠 명령 줄 판정기 사유 없음 rc=1 — 판정 불가"*) ok "ⓓ 사유 없음 문구";; *) bad "ⓓ 문구 :: $OUT";; esac
empty="$(printf '%s\n' "$OUT" | grep -c '^REJECT *$' || true)"; [ "${empty:-0}" = 0 ] && ok "ⓓ 빈 사유 0" || bad "ⓓ 빈 사유 남음 :: $OUT"

# ── ⓔ 회귀 3파일 = 이 파일 밖(하드 룰 22 · test_mbox_guard.sh 하나가 41초) — RUN 줄에 rc·초로 적는다. r1678 보정 1
#    bash tests/test_mbox_guard.sh · python3 tests/scripts/test_bang_command_check.py · python3 tests/scripts/test_mbox_guard_tool_sender.py

echo "R1678 $([ "$fail" = 0 ] && echo OK || echo "FAIL=$fail")"
exit "$([ "$fail" = 0 ] && echo 0 || echo 1)"
