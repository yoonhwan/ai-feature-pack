#!/usr/bin/env bash
# test_mbox_role_key_r1116.sh — 우편함 키 = 역할 이름(r1116 · 판정 2777 · 반례 R1~R7 동결).
# 세션 번호(#N)는 표시만 — 옛 번호·새 번호·번호 없는 역할 이름이 한 우편함 · 승계 때 인계 장치 없이 후계 첫 recv 에 보인다.
# 정본 mbox*.py·mbox*.sh 를 임시 폴더에 복사해 격리 큐(FT_MBOX_DIR)로만 돈다 — 실 큐·실 tmux(스텁)·실 명부 쓰기 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
D=byz-feature-master-claude; A=byz-feature-arch-claude   # master 이름은 master 경로 판정기(별도 문)가 걸려 이 시험 대상 밖

# roster <retired:0|1> — 같은 팀 두 역할(master·arch). retired=1 이면 master#78 → _replaced_by master#79(retire 뒤).
roster() {
  python3 - "$ENVROOT/seats/seats-feature.json" "$1" <<'PY'
import json, sys
p, retired = sys.argv[1], sys.argv[2] == "1"
d = {"_master": "byz-feature-master-claude#79",
     "byz-feature-master-claude#77": {"role": "stop-ready", "_replaced_by": "byz-feature-master-claude#78"},
     "byz-feature-master-claude#78": {"role": "master"},
     "byz-feature-master-claude#79": {"role": "master"},
     "byz-feature-arch-claude#26": {"role": "arch"}}
if retired:
    d["byz-feature-master-claude#78"] = {"role": "stop-ready", "_replaced_by": "byz-feature-master-claude#79"}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env <retired> [변이함수] — 격리 루트 + 빈 큐 · 변이는 사본에만
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"
  roster "$1"; : > "$Q"
  if [ -n "${2:-}" ]; then "$2"; fi
}
row() { printf '{"seq": %s, "ts": "2026-10-29T00:00:00", "to": "%s", "from": "x#1", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
xenv() { env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" "$@"; }
py() { OUT="$(cd "$ENVROOT" && xenv python3 "$C/mbox.py" "$@" 2>"$ENVROOT/err")"; RC=$?; ERR="$(cat "$ENVROOT/err")"; }
sh_() { OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
nread() { printf '%s\n' "$OUT" | grep -c '^READ \['; }
rows_to() { grep -c "\"to\": \"$1\"" "$Q"; }

# 변이: role_key 가 #N 을 안 뗀다 → ⓐ FAIL 이어야 한다
mut_nokey() { printf '\ndef role_key(name):\n    return name or ""\n' >> "$C/mbox_conf.py"; }

# ⓐ R1·R2·R3 — retire 전(계보 0): master#78 앞 2 · master#77(두 판 전) 1 · 번호 없는 역할 이름 1 → master#79 recv READ 4 · arch 행 보존
chk_a() {
  new_env 0 "${1:-}"; row 1 "$D#78" a1; row 2 "$D#78" a2; row 3 "$D#77" b1; row 4 "$D" c1; row 5 "$A#26" z1
  py recv "$D#79" --all; [ "$(nread)" = 4 ] && [ "$(rows_to "$A#26")" = 1 ] && [ "$(wc -l < "$Q" | tr -d ' ')" = 1 ]
}
chk_a && ok "ⓐ R1·R2·R3 retire 전 master#79 recv READ 4(#78×2·#77·역할 이름) · arch 보존" || bad "ⓐ R1~R3 :: $OUT"
chk_a mut_nokey && bad "변이(role_key 무효)가 ⓐ 에 안 잡힘" || ok "변이(role_key 가 #N 안 뗌) → ⓐ FAIL 확인"

# ⓑ R4 — 다른 역할 분리: arch#26 앞 1 → master#79 READ 0 · arch#26 은 READ 1
new_env 0; row 1 "$A#26" z1
py recv "$D#79"; [ "$(nread)" = 0 ] && [ "$(rows_to "$A#26")" = 1 ] && ok "ⓑ R4 다른 역할 쪽지 master READ 0" || bad "ⓑ R4 master :: $OUT"
py recv "$A#26"; [ "$(nread)" = 1 ] && ok "ⓑ R4 arch#26 은 자기 것 READ 1" || bad "ⓑ R4 arch :: $OUT"

# ⓑ' R3 send — 번호 없는 역할 이름으로 보내도 적재(rc0) · 현역 master#79 가 읽는다
new_env 0; sh_ send "$D" me#1 "[부팅 보고] 역할 이름 앞"
[ "$RC" = 0 ] && [ "$(rows_to "$D")" = 1 ] && ok "ⓑ' R3 역할 이름 send rc0 · 적재" || bad "ⓑ' R3 send rc=$RC :: $OUT"
py recv "$D#79"; [ "$(nread)" = 1 ] && ok "ⓑ' R3 역할 이름 앞 쪽지 → master#79 READ 1" || bad "ⓑ' R3 recv :: $OUT"

# ⓒ R5 — 상한 = 역할 합: #78 앞 9 + #79 앞 2 + 새 1 = 12 > 10 → DROPPED 2 · pending=10(역할 합)
new_env 0; for s in 1 2 3 4 5 6 7 8 9; do row "$s" "$D#78" "o$s"; done; row 10 "$D#79" n1; row 11 "$D#79" n2
py send "$D#79" me#1 "새 쪽지"
case "$OUT" in *"pending=10 "*) true;; *) false;; esac && case "$ERR" in *"DROPPED 2"*) true;; *) false;; esac \
  && [ "$(wc -l < "$Q" | tr -d ' ')" = 10 ] && ok "ⓒ R5 역할 합 12 → DROPPED 2 · pending=10" || bad "ⓒ R5 :: $OUT :: $ERR"

# ⓓ R6 — 역할 현역 0(명부의 그 역할 행이 전부 closed) → send REJECT 그대로 · 번호 없는 역할 이름도
new_env 0; printf '{"byz-cfo-master-claude#5": {"role": "closed"}}\n' > "$ENVROOT/seats/seats-cfo.json"
sh_ send byz-cfo-master-claude#5 me#1 "[부팅 보고] x"; r1=$RC; o1="$OUT"
sh_ send byz-cfo-master-claude me#1 "[부팅 보고] y"; r2=$RC
[ "$r1" = 3 ] && [ "$r2" = 3 ] && [ ! -s "$Q" ] && case "$OUT" in *'역할 현역 0'*) true;; *) false;; esac \
  && ok "ⓓ R6 역할 현역 0 → REJECT rc3(번호·역할 이름 둘 다) · 적재 0" || bad "ⓓ R6 r1=$r1 r2=$r2 :: $o1 :: $OUT"

# ⓔ R7 — retire 뒤(master#78 → #79): holder·ring 이 현역 master#79 · 옛 세션 #78 recv 는 «현역 아님» READ 0(현역만 recv)
new_env 1; row 1 "$D#78" late
py holder "$D#78"; h1="$OUT"; py holder "$D"; h2="$OUT"; py holder "$D#77"; h3="$OUT"
[ "$h1" = "$D#79" ] && [ "$h2" = "$D#79" ] && [ "$h3" = "$D#79" ] && ok "ⓔ R7 holder #78·역할 이름·#77 → 현역 #79" || bad "ⓔ R7 holder :: $h1 $h2 $h3"
sh_ ring "$D#78" 123; case "$OUT" in "RING $D#79 "*) ok "ⓔ R7 ring #78 → RING $D#79";; *) bad "ⓔ R7 ring :: $OUT";; esac
py recv "$D#78"; [ "$(nread)" = 0 ] && [ "$(rows_to "$D#78")" = 1 ] && case "$ERR" in *'현역 아님'*) true;; *) false;; esac \
  && ok "ⓔ 옛 세션 #78 recv = 현역 아님 WARN · READ 0 · 큐 보존" || bad "ⓔ 옛 세션 recv :: $OUT :: $ERR"
py recv "$D#79"; [ "$(nread)" = 1 ] && ok "ⓔ 후계 #79 첫 recv 에 옛 번호 앞 쪽지 READ 1" || bad "ⓔ 후계 recv :: $OUT"

# ⓕ 라이브 설치 감시 — check-drift MAP 이 바뀐 파일을 전부 센다(한쪽만 깔리면 import 오류 · 감시 밖이면 무증상)
miss=""; for f in mbox.py mbox.sh mbox_conf.py mbox_lineage.py mbox_ops.py mbox_guard.py mbox_guard.sh; do
  grep -q "\"$f|" "$SRC/check-drift.sh" || miss="$miss $f"; done
[ -z "$miss" ] && ok "ⓕ check-drift MAP 에 바뀐 7파일 전부" || bad "ⓕ MAP 누락:$miss"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
