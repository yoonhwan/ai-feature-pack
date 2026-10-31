#!/usr/bin/env bash
# test_mbox_live_sibling_r1225.sh — r1225 · Issue #5402: 같은 역할 이름에 현역이 둘(arch#189 · #190)일 때 recv 가 «다른 현역 좌석 앞» 쪽지를 가져가지 않는다.
#  R1 현역 #189·#190 · to=#190 → #189 안 가져감 · #190 가져감(영수 #190 만)   R2 to=#188(은퇴 → #190) → #190 만
#  R3 번호 없는 역할 이름 → 번호 큰 현역 #190 하나만   R4 명부 못 읽음 → 역할 키 그대로 + stderr «명부 못 읽음 — 역할 키로 받음»
#  R5 현역 하나(일반 승계) → 옛·새·번호 없음·미등록 옛 번호 전부 그 좌석   R6 me 가 보낸 [인계] → 안 가져감(r1155)
#  R7 후계 #191 → 은퇴한 #189(살아 있음) 앞 [레디] → #189 가 가져감 · #190·#191 안 가져감
#  변이: claim 거르개 1조건(mine) 제거 → R1 FAIL · 키트 ft-mbox.py _rows_for 도 R1·R3·R4·R7 + 같은 변이.
# 격리: 정본 comm·키트 사본 + 가짜 명부 + 임시 우편함 + 가짜 tmux · 실 명부·실 큐·실 tmux 0 · 자기 재호출 0 · 고정 sleep 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
A=byz-zz-arch-claude; M=byz-zz-master-claude#50

roster() {   # roster <live2|r7|solo|legacy|broken> — 실 spawn 꼴 = 행마다 _replaces 키(ft-role-spawn) · legacy = 키 없는 옛 꼴(r1116 ⓐ)
  [ "$1" = broken ] && { printf '{"%s#190": ' "$A" > "$ENVROOT/seats/seats-zz.json"; return; }
  python3 - "$ENVROOT/seats/seats-zz.json" "$1" "$A" "$M" <<'PY'
import json, sys
p, kind, a, m = sys.argv[1:5]
d = {"_master": m, m: {"role": "master"},
     a + "#188": {"role": "stop-ready", "_replaced_by": a + "#190"},
     a + "#190": {"role": "arch", "_replaces": [a + "#188"]}}
if kind in ("live2", "r7"): d[a + "#189"] = {"role": "arch", "_replaces": []}
if kind == "legacy": d = {"_master": m, m: {"role": "master"}, a + "#189": {"role": "arch"}, a + "#190": {"role": "arch"}}
if kind == "r7": d[a + "#189"] = {"role": "stop-ready", "_replaced_by": a + "#191", "_replaces": []}; d[a + "#191"] = {"role": "arch", "_replaces": [a + "#189"]}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env <roster> [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"; K="$ENVROOT/kbin"
  mkdir -p "$C" "$K" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; cp "$KIT/ft-mbox.py" "$K/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; roster "$1"; : > "$Q"
  if [ -n "${2:-}" ]; then "$2"; fi
}
row() { printf '{"seq": %s, "ts": "2026-10-31T00:00:00", "to": "%s", "from": "%s", "body": "%s"}\n' "$1" "$2" "${4:-x#1}" "$3" >> "$Q"; }
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh"
  "$@" ); }
rcv() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$C/mbox.py" recv "$1" --all 2>"$ENVROOT/err")"; ERR="$(cat "$ENVROOT/err")"; }
krcv() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$K/ft-mbox.py" recv "$1" --all 2>"$ENVROOT/err")"; ERR="$(cat "$ENVROOT/err")"; }
nread() { printf '%s\n' "$OUT" | grep -c '^READ \['; }
left() { wc -l < "$Q" | tr -d ' '; }
rcpt() { local f="$C/receipts/$1.jsonl"; [ -f "$f" ] && grep -c "\"seq\": $2," "$f" || echo 0; }
mut() { sed -i '' 's/ and mine(r.get("to"))//' "$C/mbox_lineage.py"; ! grep -q 'mine(r.get("to"))' "$C/mbox_lineage.py"; }
kmut() { sed -i '' 's/ and mine(r.get("to"))//' "$K/ft-mbox.py"; ! grep -q 'mine(r.get("to"))' "$K/ft-mbox.py"; }

# R1 — 현역 둘 · to=#190 → #189 READ 0(큐 보존) · #190 READ 1 · 영수 #190 1 · #189 0
r1() { new_env live2 "${1:-}" || return 2; row 1 "$A#190" r1
  rcv "$A#189"; [ "$(nread)" = 0 ] && [ "$(left)" = 1 ] || return 1
  rcv "$A#190"; [ "$(nread)" = 1 ] && [ "$(left)" = 0 ] && [ "$(rcpt "$A#190" 1)" = 1 ] && [ "$(rcpt "$A#189" 1)" = 0 ]; }
r1 && ok "R1 to=#190 → #189 READ 0 · #190 READ 1 · 영수 #190 만" || bad "R1 :: $OUT :: $ERR"
r1 mut; [ $? = 1 ] && ok "변이(claim 거르개 mine 제거) → R1 FAIL 확인" || bad "변이가 R1 에 안 잡힘"

# R1′ — 현역 둘 다 명부 행 있음 · to=#189 → #190 READ 0(번호 큰 쪽도 남의 것 안 가져감) · #189 READ 1
new_env live2; row 1 "$A#189" r1p
rcv "$A#190"; a=$(nread); rcv "$A#189"; b=$(nread)
[ "$a" = 0 ] && [ "$b" = 1 ] && ok "R1′ to=#189 → #190 READ 0 · #189 READ 1" || bad "R1′ a=$a b=$b :: $OUT"

# ⓐ 옛 꼴(_replaces 키 없음 · r1116 ⓐ) — to=#189 → 번호 큰 #190 이 가져감(지금 규칙 그대로)
new_env legacy; row 1 "$A#189" la; rcv "$A#190"
[ "$(nread)" = 1 ] && [ "$(left)" = 0 ] && ok "ⓐ 키 없는 옛 꼴 to=#189 → #190 READ 1(r1116 그대로)" || bad "ⓐ 옛 꼴 :: $OUT"

# R2 — to=#188(은퇴 사슬 → #190)
new_env live2; row 1 "$A#188" r2
rcv "$A#189"; a=$(nread); rcv "$A#190"; b=$(nread)
[ "$a" = 0 ] && [ "$b" = 1 ] && ok "R2 to=#188 → #189 READ 0 · #190 READ 1" || bad "R2 a=$a b=$b :: $OUT"

# R3 — 번호 없는 역할 이름 → 번호 큰 현역 #190 하나만
new_env live2; row 1 "$A" r3
rcv "$A#189"; a=$(nread); rcv "$A#190"; b=$(nread)
[ "$a" = 0 ] && [ "$b" = 1 ] && ok "R3 역할 이름 → #189 READ 0 · #190 READ 1" || bad "R3 a=$a b=$b :: $OUT"

# R4 — 명부 못 읽음 → 역할 키 그대로(#189 가 #190 앞도 읽음) + stderr 1줄
new_env broken; row 1 "$A#190" r4
rcv "$A#189"
[ "$(nread)" = 1 ] && [ "$(printf '%s\n' "$ERR" | grep -c '명부 못 읽음 — 역할 키로 받음')" = 1 ] \
  && ok "R4 명부 못 읽음 → 역할 키 READ 1 · stderr 1줄" || bad "R4 :: $OUT :: $ERR"

# R5 — 현역 하나(#190) · 옛 #188 · 새 #190 · 역할 이름 · 미등록 옛 번호 #187 → 전부 #190
new_env solo; row 1 "$A#188" a; row 2 "$A#190" b; row 3 "$A" c; row 4 "$A#187" d
rcv "$A#190"; [ "$(nread)" = 4 ] && [ "$(left)" = 0 ] && ok "R5 현역 하나 → READ 4(r1116 그대로)" || bad "R5 :: $OUT"

# R6 — me 가 보낸 [인계] 는 안 가져감(r1155)
new_env live2; row 1 "$A#188" "[인계] x" "$A#190"
rcv "$A#190"; [ "$(nread)" = 0 ] && [ "$(left)" = 1 ] && ok "R6 #190 이 보낸 [인계] → #190 READ 0" || bad "R6 :: $OUT"

# R7 — #191 → 은퇴한 #189(살아 있음) 앞 [레디] → #190 안 · #191 안 · #189 가져감
new_env r7; row 1 "$A#189" "[레디] 받음" "$A#191"
rcv "$A#190"; a=$(nread); rcv "$A#191"; b=$(nread); rcv "$A#189"; c=$(nread)
[ "$a" = 0 ] && [ "$b" = 0 ] && [ "$c" = 1 ] && [ "$(rcpt "$A#189" 1)" -ge 1 ] && [ "$(rcpt "$A#190" 1)" = 0 ] \
  && ok "R7 [레디] to=#189 → #190 0 · #191 0 · #189 1(영수 #189 만)" || bad "R7 a=$a b=$b c=$c :: $OUT :: $ERR"

# 키트 ft-mbox.py _rows_for — 같은 규칙
k1() { new_env live2 "${1:-}" || return 2; row 1 "$A#190" k1
  krcv "$A#189"; [ "$(nread)" = 0 ] && [ "$(left)" = 1 ] || return 1
  krcv "$A#190"; [ "$(nread)" = 1 ] && [ "$(left)" = 0 ]; }
k1 && ok "키트 R1 to=#190 → #189 READ 0 · #190 READ 1" || bad "키트 R1 :: $OUT :: $ERR"
k1 kmut; [ $? = 1 ] && ok "키트 변이(_rows_for mine 제거) → R1 FAIL 확인" || bad "키트 변이가 R1 에 안 잡힘"
new_env live2; row 1 "$A#189" k1p; krcv "$A#190"; a=$(nread); krcv "$A#189"; b=$(nread)
[ "$a" = 0 ] && [ "$b" = 1 ] && ok "키트 R1′ to=#189 → #190 READ 0 · #189 READ 1" || bad "키트 R1′ a=$a b=$b :: $OUT"
new_env legacy; row 1 "$A#189" kla; krcv "$A#190"
[ "$(nread)" = 1 ] && ok "키트 ⓐ 키 없는 옛 꼴 to=#189 → #190 READ 1" || bad "키트 ⓐ 옛 꼴 :: $OUT"
new_env live2; row 1 "$A" k3; row 2 "$A#188" k2
krcv "$A#189"; a=$(nread); krcv "$A#190"; b=$(nread)
[ "$a" = 0 ] && [ "$b" = 2 ] && ok "키트 R2·R3 #188·역할 이름 → #190 만" || bad "키트 R2·R3 a=$a b=$b :: $OUT"
new_env broken; row 1 "$A#190" k4; krcv "$A#189"
[ "$(nread)" = 1 ] && printf '%s\n' "$ERR" | grep -q '명부 못 읽음 — 역할 키로 받음' && ok "키트 R4 명부 못 읽음 → 역할 키 · stderr" || bad "키트 R4 :: $OUT :: $ERR"
new_env r7; row 1 "$A#189" "[레디] 받음" "$A#191"
krcv "$A#190"; a=$(nread); krcv "$A#191"; b=$(nread); krcv "$A#189"; c=$(nread)
[ "$a" = 0 ] && [ "$b" = 0 ] && [ "$c" = 1 ] && ok "키트 R7 [레디] → #189 만" || bad "키트 R7 a=$a b=$b c=$c :: $OUT"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
