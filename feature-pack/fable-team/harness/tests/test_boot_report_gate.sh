#!/usr/bin/env bash
# test_boot_report_gate.sh — P4 r-succession-gate: [부팅 보고] 본문 게이트(retire=<구>-><후계> rc=0 · cron=<id>).
# 격리 큐(FT_MBOX_DIR) + 정본 사본 + 명부 픽스처 tests/fixtures/mbox_guard/succ_boot* — 실 큐·실 doorbell(tmux 스텁)·루트 .fable-team/ 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; FX="$REPO/tests/fixtures/mbox_guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
ARCH='byz-harness-arch-claude#33'; ARCH_OLD='byz-harness-arch-claude#32'; MASTER='byz-harness-master-claude#33'; PM='byz-harness-pm-claude#1'
PLANNER='byz-planner-master-claude#9'; NANO='byz-harness-nano-x#0'

new_env() {  # <variant> — 정본 사본 + lint + 명부 픽스처
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$ENVROOT/.fable-team/comm/"; cp "$SRC"/ft-boot-report-lint.py "$ENVROOT/.fable-team/comm/" 2>/dev/null
  git -C "$ENVROOT" init -q; mkdir -p "$ENVROOT/seats"; cp "$FX/$1"/seats*.json "$ENVROOT/seats/"
}
send_from() {  # <from> <to> <body> → RC·OUT (planner 머리 모드 reject 고정)
  OUT="$(cd "$ENVROOT" && env PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_PLANNER_HEAD_MODE=reject \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" send "$2" "$1" "$3" 2>&1)"; RC=$?
}
queued_to() { local n; n="$(grep -c "\"to\": *\"$1\"" "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
BASE='[부팅 보고] 세션=x 모델=y Serena=가'
RET="retire=$ARCH_OLD->$ARCH rc=0"

# ⓐ 승계 좌석 + retire 칸 없음 → REJECT · 큐 0 · 기대 칸 문구
new_env succ_boot; send_from "$ARCH" "$PM" "$BASE cron=abc12345"
[ "$RC" = 3 ] && [ "$(queued_to "$PM")" = 0 ] && case "$OUT" in *"retire=$ARCH_OLD->$ARCH rc=0"*) true;; *) false;; esac \
  && ok "ⓐ 승계 좌석 retire 칸 없음 → REJECT rc=3 · 큐 0 · 기대 칸 문구" || bad "ⓐ rc=$RC q=$(queued_to "$PM") :: $OUT"
# ⓑ 같은 본문 + retire 칸 → OK 큐 1행 ( -> 와 → 둘 다)
new_env succ_boot; send_from "$ARCH" "$PM" "$BASE $RET cron=abc12345"
[ "$RC" = 0 ] && [ "$(queued_to "$PM")" = 1 ] && ok "ⓑ retire 칸 있음(->) → OK 큐 1행" || bad "ⓑ rc=$RC :: $OUT"
new_env succ_boot; send_from "$ARCH" "$PM" "$BASE retire=${ARCH_OLD}→${ARCH} rc=0 cron=abc12345"
[ "$RC" = 0 ] && [ "$(queued_to "$PM")" = 1 ] && ok "ⓑ' retire 칸 있음(→) → OK" || bad "ⓑ' rc=$RC :: $OUT"
# ⓒ 구 이름이 _replaces 밖 · 후계가 발신자 아님 → REJECT 불일치
new_env succ_boot; send_from "$ARCH" "$PM" "$BASE retire=byz-harness-arch-claude#31->$ARCH rc=0 cron=abc12345"
[ "$RC" = 3 ] && case "$OUT" in *'불일치'*) true;; *) false;; esac && ok "ⓒ 구 이름 불일치 → REJECT 불일치" || bad "ⓒ rc=$RC :: $OUT"
new_env succ_boot; send_from "$ARCH" "$PM" "$BASE retire=$ARCH_OLD->byz-harness-arch-claude#34 rc=0 cron=abc12345"
[ "$RC" = 3 ] && ok "ⓒ' 후계가 발신 좌석 아님 → REJECT" || bad "ⓒ' rc=$RC :: $OUT"
# ⓓ _replaces 없는 좌석(나노·첫 개설) → 칸 없어도 OK
new_env succ_boot; send_from "$NANO" "$PM" "$BASE"
[ "$RC" = 0 ] && ok "ⓓ _replaces 없는 좌석(나노) → 칸 없어도 OK" || bad "ⓓ rc=$RC :: $OUT"
# ⓔ master/arch 는 cron= 칸 필수
new_env succ_boot; send_from "$MASTER" "$PM" "$BASE retire=byz-harness-master-claude#32->$MASTER rc=0"
[ "$RC" = 3 ] && case "$OUT" in *'cron='*) true;; *) false;; esac && ok "ⓔ master 승계 cron= 없음 → REJECT" || bad "ⓔ rc=$RC :: $OUT"
new_env succ_boot; send_from "$MASTER" "$PM" "$BASE retire=byz-harness-master-claude#32->$MASTER rc=0 cron=9f8e7d6c"
[ "$RC" = 0 ] && ok "ⓔ' master 승계 cron= 있음 → OK" || bad "ⓔ' rc=$RC :: $OUT"
# ⓕ planner 앞 [부팅 보고] 허용(D4 변경 0) — 본문이 맞으면 통과
new_env succ_boot; send_from "$ARCH" "$PLANNER" "$BASE $RET cron=abc12345"
[ "$RC" = 0 ] && [ "$(queued_to "$PLANNER")" = 1 ] && ok "ⓕ planner 앞 [부팅 보고] + 맞는 본문 → OK" || bad "ⓕ rc=$RC :: $OUT"
# ⓖ 발신 좌석 명부 파싱 실패 → 전송 + stderr WARN 1줄
new_env succ_boot_broken; send_from "$ARCH" "$PLANNER" "$BASE"
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c 'WARN 부팅 보고 lint')" = 1 ] && ok "ⓖ 명부 깨짐 → 전송 + WARN 1줄" || bad "ⓖ rc=$RC :: $OUT"
# 다른 머리는 검사 0
new_env succ_boot; send_from "$ARCH" "$PM" "일반 쪽지"
[ "$RC" = 0 ] && ok "다른 머리는 검사 0" || bad "다른 머리 rc=$RC :: $OUT"

# ⓗ fix1: 승계 판별 = 이름 X#N 이고 명부에 X#N-1 행 존재(후계 행·_replaces 무관) — retire 를 안 돌린 승계도 막는다
new_env succ_boot_noretire; send_from "$ARCH" "$PM" "$BASE cron=abc12345"
[ "$RC" = 3 ] && [ "$(queued_to "$PM")" = 0 ] && case "$OUT" in *"retire=$ARCH_OLD->$ARCH rc=0"*) true;; *) false;; esac \
  && ok "ⓗ1 후계 행 없음 + #N-1 행 있음 + 칸 없음 → REJECT 칸 없음" || bad "ⓗ1 rc=$RC :: $OUT"
new_env succ_boot_noretire; send_from "$ARCH" "$PM" "$BASE $RET cron=abc12345"
[ "$RC" = 3 ] && case "$OUT" in *'명부 미반영'*'ft-seat-retire.sh'*) true;; *) false;; esac \
  && ok "ⓗ2 칸은 있는데 구 행 _replaced_by 미반영 → REJECT 명부 미반영" || bad "ⓗ2 rc=$RC :: $OUT"
new_env succ_boot_noretire; cp "$FX/succ_boot/seats-harness.json" "$ENVROOT/seats/seats-harness.json"; send_from "$ARCH" "$PM" "$BASE $RET cron=abc12345"
[ "$RC" = 0 ] && [ "$(queued_to "$PM")" = 1 ] && ok "ⓗ3 retire 실행 뒤(명부 갱신) + 칸 → OK" || bad "ⓗ3 rc=$RC :: $OUT"

# 변이 1: 가드의 lint 호출 제거 → ⓐ 빨강(REJECT 가 사라져 rc=0)
new_env succ_boot; sed -i '' 's/^  _guard_boot_lint "\$2".*$/  true/' "$ENVROOT/.fable-team/comm/mbox_guard.sh"
send_from "$ARCH" "$PM" "$BASE cron=abc12345"
[ "$RC" = 0 ] && ok "변이1(lint 호출 제거) → ⓐ 빨강 확인(rc=0)" || bad "변이1 이 ⓐ 에 안 잡힘 rc=$RC :: $OUT"
# 변이 2: lint 의 _replaces 대조 제거 → ⓒ 빨강
new_env succ_boot; sed -i '' 's/old not in cands or //' "$ENVROOT/.fable-team/comm/ft-boot-report-lint.py"
send_from "$ARCH" "$PM" "$BASE retire=byz-harness-arch-claude#31->$ARCH rc=0 cron=abc12345"
# fix1 뒤 구 행 _replaced_by 대조가 2차 방어라 rc 는 3 으로 남는다 — ⓒ 의 «불일치» 문구가 사라진 것으로 빨강을 본다
case "$OUT" in *'불일치'*) bad "변이2 가 ⓒ 에 안 잡힘 rc=$RC :: $OUT";; *) ok "변이2(구 이름 대조 제거) → ⓒ 빨강 확인(불일치 문구 소멸 rc=$RC)";; esac
# 변이 3: 이름(#N-1 행) 판별 제거 → ⓗ1 빨강
new_env succ_boot_noretire; sed -i '' 's/\[prev\] if prev_row else \[\]/[]/' "$ENVROOT/.fable-team/comm/ft-boot-report-lint.py"
send_from "$ARCH" "$PM" "$BASE cron=abc12345"
[ "$RC" = 0 ] && ok "변이3(이름 판별 제거) → ⓗ1 빨강 확인(rc=0)" || bad "변이3 이 ⓗ1 에 안 잡힘 rc=$RC :: $OUT"
# 변이 4: 명부 _replaced_by 대조 제거 → ⓗ2 빨강
new_env succ_boot_noretire; sed -i '' 's/ or old_row.get("_replaced_by") != a.me//' "$ENVROOT/.fable-team/comm/ft-boot-report-lint.py"
send_from "$ARCH" "$PM" "$BASE $RET cron=abc12345"
[ "$RC" = 0 ] && ok "변이4(명부 미반영 대조 제거) → ⓗ2 빨강 확인(rc=0)" || bad "변이4 가 ⓗ2 에 안 잡힘 rc=$RC :: $OUT"

# 문법·크기
bash -n "$SRC/mbox_guard.sh" 2>/dev/null && ok "bash -n mbox_guard.sh" || bad "bash -n mbox_guard.sh"
python3 -m py_compile "$SRC/ft-boot-report-lint.py" 2>/dev/null && ok "py_compile lint" || bad "py_compile lint"
n="$(wc -l < "$SRC/ft-boot-report-lint.py" 2>/dev/null || echo 999)"; [ "$n" -le 80 ] && ok "lint ≤80줄($n)" || bad "lint 줄수 $n"
n="$(wc -l < "$SRC/mbox_guard.sh")"; [ "$n" -le 200 ] && ok "mbox_guard.sh ≤200줄($n)" || bad "mbox_guard.sh 줄수 $n"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
