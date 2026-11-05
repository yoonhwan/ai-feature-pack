#!/usr/bin/env bash
# test_hil_entry_out_stderr_r1382.sh — r1382: h 진입 파일이 계획의 stderr 도 <h>.out 에 남긴다(2>&1 | tee · rc = PIPESTATUS[0]) (카드 반례 E1~E4 · 변이 2)
# 격리: 임시 HIL_DIR · 가짜 mbox.sh(인자를 sent.log 에 적는다) · 계획 대역(stdout/stderr/exit) — 실 /tmp/h* · 실 우편함 0 · 자기 재호출 0(변이는 bin 사본 · 재진입 표지는 real_state_guard) · 고정 sleep 0
#   기준판: 2>&1 이 없는 bin 으로 돌리면 E1·E2 가 FAIL 한다(변이 1 과 같은 꼴).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R1382_BIN:-$HERE/../bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

C="$T/comm"; mkdir -p "$C" "$T/home"
printf '{"_master": "byz-planner-master-claude#1"}\n' > "$T/seats-planner.json"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
hil()  { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$b/ft-hil.sh" "$@"; }
runh() { ( cd /tmp && env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$1" ); }   # 오빠 `bash /tmp/h<N>` — 리포 밖 계획(git 밖)
plan() {  # <이름> <본문 줄들…> → 계획 파일 경로(100644 · bash 로 돈다)
  local f="$T/$1.sh.hil"; shift; { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$f"; echo "$f"
}
issue() {  # <bin> <계획> → 진입 파일 경로
  local h; h="$(hil "$1" --add "$2" 2>/dev/null)"; echo "${h#! bash }"
}

check_E() {  # <bin> → E1~E4 실패 수(0 = 통과) · 화면에 PASS/FAIL
  local b="$1" f0=$fail h o rc out sent
  HD="$T/hd-$RANDOM"; mkdir -p "$HD"
  # E1·E2 — stdout 1줄 + stderr 1줄 + exit 1
  h="$(issue "$b" "$(plan e1 'echo OUT-1' 'echo "DIE 이유-X" >&2' 'exit 1')")"; rm -f "$C/sent.log"
  o="$(runh "$h" 2>&1)"; rc=$?
  out="$(cat "$h.out" 2>/dev/null)"
  has "$out" "DIE 이유-X" "E1 .out 에 stderr 이유 줄"; has "$out" "OUT-1" "E1 .out 에 stdout 줄도"
  [ "$rc" = 1 ] && ok "E1 진입 파일 rc 1" || bad "E1 rc=$rc"
  [ "$(tail -n 1 "$h.ran" | cut -d' ' -f1)" = rc=1 ] && ok "E1 .ran 끝 rc=1" || bad "E1 .ran: $(tr '\n' '|' < "$h.ran")"
  has "$o" "DIE 이유-X" "E1 화면에도 이유 줄(오빠 화면 그대로)"
  sent="$(cat "$C/sent.log" 2>/dev/null)"; has "$sent" "rc=1 · DIE 이유-X" "E2 결과 쪽지 결과 줄 = 이유 줄"
  # E3 — 성공 h: 결과 줄이 있으면 그 줄 · stderr 경고도 .out
  h="$(issue "$b" "$(plan e3 'echo "=== 결과 === ok"' 'echo "WARN 뭔가" >&2' 'exit 0')")"; rm -f "$C/sent.log"
  runh "$h" >/dev/null 2>&1; rc=$?; out="$(cat "$h.out" 2>/dev/null)"
  [ "$rc" = 0 ] && ok "E3 rc 0" || bad "E3 rc=$rc"
  has "$out" "WARN 뭔가" "E3 .out 에 stderr 줄"; has "$out" "=== 결과 === ok" "E3 .out 에 결과 줄"
  sent="$(cat "$C/sent.log" 2>/dev/null)"; has "$sent" "rc=0 · === 결과 === ok" "E3 결과 쪽지 = «=== 결과 === ok»(지금과 같음)"
  # E4 — stderr 만 + exit 4: tee 의 rc 0 이 덮지 않는다
  h="$(issue "$b" "$(plan e4 'echo "ONLY-ERR" >&2' 'exit 4')")"; rm -f "$C/sent.log"
  runh "$h" >/dev/null 2>&1; rc=$?
  [ "$rc" = 4 ] && ok "E4 rc 4 그대로" || bad "E4 rc=$rc"
  [ "$(tail -n 1 "$h.ran" | cut -d' ' -f1)" = rc=4 ] && ok "E4 .ran 끝 rc=4" || bad "E4 .ran: $(tr '\n' '|' < "$h.ran")"
  has "$(cat "$h.out" 2>/dev/null)" "ONLY-ERR" "E4 .out 에 stderr 줄"
  return $((fail - f0))
}

echo "== E1~E4 지금 bin"; check_E "$BIN0"

echo "== bin·kit 같은 내용 · ft-hil.sh ≤200줄"
cmp -s "$BIN0/ft-hil.sh" "$HERE/../kit/fable-team/bin/ft-hil.sh" && ok "cmp0 ft-hil.sh" || bad "키트 다름 ft-hil.sh"
[ "$(wc -l < "$BIN0/ft-hil.sh")" -le 200 ] && ok "200줄 이하 ft-hil.sh" || bad "200줄 초과 ft-hil.sh"

mutant() {  # <이름> <sed 식> → 변이 bin 경로(원본과 다르면)
  local m="$T/mut-$1"; cp -R "$BIN0" "$m" && sed "$2" "$BIN0/ft-hil.sh" > "$m/ft-hil.sh"
  cmp -s "$BIN0/ft-hil.sh" "$m/ft-hil.sh" && { bad "변이 $1 사본 = 원본"; return 1; }; echo "$m"
}
mutv() { local f0=$fail out; out="$("$@" 2>&1)"; local d=$?; fail=$f0; [ "$d" -gt 0 ]; }
echo "== 변이 2 — 각 변이가 대응 칸을 FAIL 시킨다(검출)"
m="$(mutant nostderr 's/bash "\$P" "\$@" 2>&1 | tee/bash "$P" "$@" | tee/')" && { mutv check_E "$m" && ok "변이 1(2>&1 삭제) → E1·E2 FAIL 검출" || bad "변이 1 을 못 잡음"; }
m="$(mutant pipestatus 's/rc=\${PIPESTATUS\[0\]}/rc=$?/')" && { mutv check_E "$m" && ok "변이 2(PIPESTATUS[0]→\$?) → E1·E4 FAIL 검출" || bad "변이 2 를 못 잡음"; }

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
