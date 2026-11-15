#!/usr/bin/env bash
# test_master_seat_route_r1657.sh — r1657 단계 1: 카드 담당 석 정하기(ft-card-number.sh seat) · master 쪽지 길(comm/mbox_seat.py · mbox.sh send) · 담당 석 칸 lint.
# 입력 = tmp 명부 json · tmp 카드 폴더 · tmp 우편함 · 실 좌석·실 명부·실 우편함 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$HERE/.."
SRC="${R1657_COMM:-$H/comm}"; NUM="${R1657_NUM:-$H/bin/ft-card-number.sh}"; LINT="$H/kit/fable-team/bin/ft-index-lint.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; t0=$SECONDS
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
M0="byz-harness-master-pi#275"; M1="byz-harness-master-1-pi#1"
roster() {   # roster <_master-1 값> → $T/seats/seats-harness.json
  mkdir -p "$T/seats"; python3 - "$T/seats/seats-harness.json" "$1" "$M0" "$M1" <<'PY'
import json, sys
p, m1, a, b = sys.argv[1:5]
json.dump({"_master": a, "_master-1": m1, a: {"role": "master", "agent": "pi"}, b: {"role": "master", "agent": "pi"},
           "byz-harness-nano-x#0": {"role": "nano", "agent": "pi"}}, open(p, "w"), ensure_ascii=False)
PY
}
card() { mkdir -p "$T/cards/$1"; { printf '# 인덱스: %s\n' "$2"; [ -z "$3" ] || printf -- '- 담당 석: %s\n' "$3"; printf '\n## 상태\n- 대기\n'; } > "$T/cards/$1/$2.md"; }
roster "$M1"; FT_CARDS_DIR="$T/cards"; export FT_CARDS_DIR
# ⓐ 담당 석 정하기 — 석 0 카드 3장(줄 없음 1 · 0 두 장) · 석 1 카드 1장 → 1 · 같은 수 → 0 · 석 1 없음 → 0
card 대기 r9101-a ""; card 대기 r9102-b 0; card 진행 r9103-c 0; card 진행 r9001-one 1
o="$(bash "$NUM" seat "$T/cards" "$T/seats/seats-harness.json")"; [ "$o" = "SEAT 1 counts=0:3,1:1" ] && ok "ⓐ 적은 석 = 1 ($o)" || bad "ⓐ 적은 석 :: $o"
card 대기 r9104-d 1; card 대기 r9105-e 1
o="$(bash "$NUM" seat "$T/cards" "$T/seats/seats-harness.json")"; [ "$o" = "SEAT 0 counts=0:3,1:3" ] && ok "ⓐ 같은 수 = 0 ($o)" || bad "ⓐ 같은 수 :: $o"
rm "$T/cards/대기/r9104-d.md" "$T/cards/대기/r9105-e.md"; card 대기 r9002-zero 0; card 대기 r9003-blank ""
# 시험 우편함(정본 comm 사본) — mbox.sh send 가 guard_check → mbox_seat.py 를 지난다
E="$T/env"; mkdir -p "$E/.fable-team/comm" "$E/.fable-team/state" "$T/stub"; cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$E/.fable-team/comm/"; git -C "$E" init -q
printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
send() { rm -f "$E/.fable-team/comm/mailbox.jsonl"; OUT="$(cd "$E" && PATH="$T/stub:$PATH" FT_SEATS_JSON="$T/seats/seats.json" FT_MBOX_DIR="$E/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 \
  bash "$E/.fable-team/comm/mbox.sh" send "$M0" "byz-harness-nano-x#0" "$1" 2>&1)"; RC=$?
  GOT="$(python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print(r[-1]["to"] if r else "-")' "$E/.fable-team/comm/mailbox.jsonl" 2>/dev/null || echo -)"; }
want() { send "$2"; [ "$RC" = 0 ] && [ "$GOT" = "$3" ] && ok "$1 → $GOT" || bad "$1 rc=$RC got=$GOT want=$3 :: $(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"; }
# ⓑ 쪽지 길
want "ⓑ r9001(담당 석 1)" "[완료] r9001 끝 · 세트: abc" "$M1"
want "ⓑ r9002(담당 석 0)" "[완료] r9002 끝 · 세트: abc" "$M0"
case "$OUT" in *"NOTE 담당 석"*) bad "ⓑ 석 0 은 NOTE 0 :: $OUT";; *) ok "ⓑ 석 0 = NOTE 0";; esac
# ⓒ 석 0 으로 가는 것
want "ⓒ 카드 참조 없음" "[완료] 끝 · 세트: abc" "$M0"
want "ⓒ 없는 카드 r9999" "[완료] r9999 끝" "$M0"
want "ⓒ 담당 석 빈 값 r9003" "[완료] r9003 끝" "$M0"
for h in "[HIL] r9001 막힘" "[부팅] r9001 세션" "[인계] r9001 넘김" "오빠 지시 r9001 이렇게"; do want "ⓒ 머리 ${h%% *}" "$h" "$M0"; done
# ⓓ 석 1 없음(_master-1 빈 값) — r9001 도 석 0 · 출력에 NOTE 0(지금과 같음)
roster ""; want "ⓓ 석 1 없음 r9001" "[완료] r9001 끝 · 세트: abc" "$M0"
case "$OUT" in *"담당 석"*) bad "ⓓ 출력 지금과 다름 :: $OUT";; *) ok "ⓓ 출력에 담당 석 줄 0";; esac
o="$(bash "$NUM" seat "$T/cards" "$T/seats/seats-harness.json")"; [ "${o:0:6}" = "SEAT 0" ] && ok "ⓓ seat = 0 ($o)" || bad "ⓓ seat :: $o"
# 칸 꼴 lint(ft-index-lint ⑯ 함수만 · 같은 awk/sed)
. <(sed -n '/^check_seat_line()/p' "$LINT"); for v in "1:0" "0:0" "x:1" "01:1" "1 (주석):1"; do bad=(); printf '# x\n- 담당 석: %s\n\n## 상태\n' "${v%:*}" > "$T/l.md"; check_seat_line "$T/l.md"
  [ "${#bad[@]}" = "${v##*:}" ] && ok "lint 담당 석 «${v%:*}» bad=${#bad[@]}" || bad "lint 담당 석 «${v%:*}» bad=${#bad[@]} want ${v##*:}"; done
bad=(); printf '# x\n\n## 상태\n' > "$T/l.md"; check_seat_line "$T/l.md"; [ "${#bad[@]}" = 0 ] && ok "lint 줄 없음 = 통과(옛 카드 = 석 0)" || bad "lint 줄 없음"
echo "RUN r1657 단계1 $((SECONDS-t0))s fail=$fail"; [ "$fail" = 0 ]
