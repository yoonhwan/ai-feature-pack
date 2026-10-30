#!/usr/bin/env bash
# test_boot_report_head_only_r1161.sh — r1161: [부팅 보고] 분류는 첫 줄 머리 대괄호(첫 `]` 까지) 또는 첫 줄 시작만 본다.
# 본문 중간 «부팅 보고» + `]`(ft-role-spawn 첫 쪽지 [Seatbelt 역할 교체] …) 는 lint 0. 진짜 부팅 보고의 retire 검사는 그대로.
# 격리 큐(FT_MBOX_DIR) + 정본 사본 + 명부 픽스처 tests/fixtures/mbox_guard/succ_boot — 실 우편함·실 명부·doorbell(tmux 스텁) 0 · 자기 재호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; FX="$REPO/tests/fixtures/mbox_guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
MASTER='byz-harness-master-claude#33'; OLD='byz-harness-master-claude#32'; PM='byz-harness-pm-claude#1'
WANT="retire=$OLD->$MASTER rc=0"

new_env() {  # 정본 사본 + lint + 승계 명부(master#32 행 있음)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/ft-boot-report-lint.py "$ENVROOT/.fable-team/comm/"
  git -C "$ENVROOT" init -q; cp "$FX/succ_boot"/seats*.json "$ENVROOT/seats/"
}
send() {  # <body> → RC·OUT (발신 = 승계 master)
  OUT="$(cd "$ENVROOT" && env PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" \
    FT_MBOX_DIR="$ENVROOT/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENVROOT/.fable-team/comm/mbox.sh" send "$PM" "$MASTER" "$1" 2>&1)"; RC=$?
}
queued() { local n; n="$(grep -c "\"to\": *\"$PM\"" "$ENVROOT/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
R1='[Seatbelt 역할 교체] 너는 arch 후계 · ★부팅 보고를 보낸 그 턴에 CronCreate 를 건다★ · 사람 판정은 [HIL] 로 올림 · 끝'
R2='[정리] 부팅 보고 받음 · [HIL] 0'
passes() {  # <이름> <본문> — QUEUED rc0 큐 1
  new_env; send "$2"
  [ "$RC" = 0 ] && [ "$(queued)" = 1 ] && ok "$1 본문 속 «부팅 보고» → QUEUED" || bad "$1 rc=$RC q=$(queued) :: $OUT"
}
rejects() {  # <이름> <본문> — REJECT rc3 · 큐 0 · retire 칸 문구
  new_env; send "$2"
  [ "$RC" = 3 ] && [ "$(queued)" = 0 ] && case "$OUT" in *"$WANT"*) true;; *) false;; esac \
    && ok "$1 진짜 부팅 보고 retire 칸 없음 → REJECT rc3" || bad "$1 rc=$RC q=$(queued) :: $OUT"
}

passes R1 "$R1"
passes R2 "$R2"
rejects R3 '[부팅 보고] 세션=x 모델=y cron=abc12345'
rejects R4 "[$MASTER->$PM] [부팅 보고] 세션=x 모델=y cron=abc12345"
rejects R5 '부팅 보고: 세션=x 모델=y cron=abc12345'

# 변이 1: 옛 case 식(머리 대괄호 자르기 제거 · `*` 가 첫 `]` 를 넘음)으로 되돌림 → R1 이 REJECT 로 빨강
new_env; G="$ENVROOT/.fable-team/comm/mbox_guard.sh"
python3 - "$G" <<'PY'
import sys; p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = 'case "$first" in \\[*\\]*) first="${first%%]*}]";; esac; '; b = '\\[*부팅\\ 보고*\\] |'
assert a in s and b in s, "변이 대상 문자열 없음"
open(p, "w", encoding="utf-8").write(s.replace(a, "").replace(b, '\\[*부팅\\ 보고*\\]* |'))
PY
[ $? = 0 ] || bad "변이1 적용 실패"
send "$R1"
[ "$RC" = 3 ] && ok "변이1(옛 case 식) → R1 REJECT rc3 = 빨강 확인" || bad "변이1 이 R1 에 안 잡힘 rc=$RC :: $OUT"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
