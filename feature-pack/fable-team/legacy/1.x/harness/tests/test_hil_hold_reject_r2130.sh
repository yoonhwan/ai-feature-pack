#!/usr/bin/env bash
# test_hil_hold_reject_r2130.sh — r2130: --hold 로 보류한 h 는 진입 파일을 손으로 돌려도 계획 실행 0(REJECT rc 1) · 번호 재발급 0
#   카드 반례 ①~⑤ · ⑦(⑥ = 기존 tests/test_hil*.sh 재실행 · 이 파일 밖) · 변이 M1~M4(사본 · 변이마다 원본 같은 칸 대조) · bin·kit 같은 바이트 · ft-hil.sh 200줄
# 격리: 임시 HIL_DIR · 임시 HOME · HIL_CLIP=0 · 가짜 mbox.sh · 리포 밖 계획(표식 파일만 씀) — 실 /tmp/h* · 실 쪽지함 · 라이브 계획 0 · sleep 0
#   기준판 = 팩 커밋 30b81a49 bin(git archive) · R2130_BIN=<기준판 bin> 으로 돌리면 ① ③ ④ ⑤ ⑦ FAIL(Red) · ② PASS
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R2130_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; BASE=30b81a49cdd42d67b5c1ca088d61fef5022a7013
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS; WHY=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
chk() { local t="$1"; shift; if "$@"; then ok "$t"; else bad "$t — $WHY"; fi; }

C="$T/comm"; mkdir -p "$C" "$T/home" "$T/base" "$T/fsed"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
printf '#!/bin/bash\necho "sed $*" >> "%s/fsed.log"\nexit 1\n' "$T" > "$T/fsed/sed"; chmod +x "$T/fsed/sed"   # ③ 읽기 실패 주입(호출 표식 1줄 · rc 1)
git -C "$(git -C "$HERE" rev-parse --show-toplevel)" archive "$BASE" -- "$(git -C "$HERE/../bin" rev-parse --show-prefix)" 2>/dev/null | tar -x -C "$T/base" 2>/dev/null
BB="$(find "$T/base" -type d -path '*harness/bin' | head -1)"; [ -f "${BB:-/}/ft-hil.sh" ] || { echo "FAIL 기준판($BASE)을 못 꺼냄 — 판정 불가"; exit 1; }

hil()  { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$b/ft-hil.sh" "$@"; }
runh() { ( cd /tmp && env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$@" ); }
plan() { local f="$T/$1.sh.hil"; shift; { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$f"; echo "$f"; }
fresh() { HD="$T/hd-$1"; rm -rf "$HD"; mkdir -p "$HD"; }
nsent() { cat "$C/sent.log" 2>/dev/null | wc -l | tr -d ' '; }
mkb() {  # <이름> <ft-hil.sh 출처> <ft-hil-gate.sh 출처> → 사본 bin(나머지 = BIN0 · 진입 파일은 등록한 bin 의 판정기를 부른다)
  local d="$T/b-$1"; rm -rf "$d"; cp -R "$BIN0" "$d" && cp "$2/ft-hil.sh" "$d/ft-hil.sh" && cp "$3/ft-hil-gate.sh" "$d/ft-hil-gate.sh" && echo "$d"; }
reg() {  # <bin> <칸> → HD · H(진입 파일) · PF(계획) · MARK(계획이 돌면 생기는 표식)
  fresh "$2"; MARK="$T/mark-$2"; rm -f "$MARK"
  PF="$(plan "p$2" '# ft-hil-request seat=byz-harness-desk-claude#1' "MARK=$MARK" 'set -euo pipefail' ': > "$MARK"' 'echo 계획-실행')"; H="$(hil "$1" --add "$PF" 2>/dev/null)"; H="${H#! bash }"
  [ -f "$H" ] || { WHY="등록 실패 ← $H"; return 1; }; }
blocked() {  # <out> <rc> <쪽지 수 앞> → rc 1 · «REJECT 보류 중» 1줄(좌석·사유·풀기) · 표식 0 · .ran 0 · 결과 쪽지 0
  local n; n="$(grep -c 'REJECT 보류 중' <<< "$1")"
  [ "$2" = 1 ] && [ "$n" = 1 ] && [ ! -e "$MARK" ] && [ ! -e "$H.ran" ] && [ "$(nsent)" = "$3" ] && grep -q "시험-사유 · 풀기 = ft-hil.sh --unhold ${H##*/}" <<< "$1" && return 0
  WHY="rc=$2 REJECT줄=$n 표식=$([ -e "$MARK" ] && echo 1 || echo 0) .ran=$([ -e "$H.ran" ] && echo 1 || echo 0) 쪽지 $3→$(nsent) ← ${1:0:300}"; return 1; }
hold() { hil "$1" --hold "${H##*/}" --why 시험-사유 >/dev/null 2>&1; }

c1() { local o rc s; reg "$1" 1 || return 1; hold "$1"; s="$(nsent)"; o="$(runh "$H" 2>&1)"; rc=$?; blocked "$o" "$rc" "$s"; }
c2() { local o rc s; reg "$1" 2 || return 1; hold "$1"; hil "$1" --unhold "${H##*/}" >/dev/null 2>&1; s="$(nsent)"; o="$(runh "$H" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -e "$MARK" ] && [ "$(nsent)" -gt "$s" ] && return 0; WHY="rc=$rc 표식=$([ -e "$MARK" ] && echo 1 || echo 0) 쪽지 ${s}→$(nsent) ← ${o:0:300}"; return 1; }
c3() { local o rc e m; reg "$1" 3 || return 1; hold "$1"; rm -f "$T/fsed.log"
  o="$(env -i HOME="$T/home" PATH="$T/fsed:/usr/bin:/bin" bash "$1/ft-hil-gate.sh" read "$PF" "$H" 2>"$T/e3")"; rc=$?; e="$(cat "$T/e3")"
  m="$(grep -c '\.held' "$T/fsed.log" 2>/dev/null)"; m="${m:-0}"
  [ "$m" = 0 ] && { WHY="호출 표식 0 = .held 읽기 누락(주입 실패 아님) · rc=$rc stdout ${#o}바이트"; return 1; }
  [ "$m" = 1 ] && [ "$rc" = 3 ] && [ -z "$o" ] && [ ! -e "$MARK" ] && [ "$e" = "판정 불가 — ${H##*/}.held 못 읽음(계획 실행 0)" ] && { echo "INFO ③ 주입 성공 표식 1줄: $(cat "$T/fsed.log")"; return 0; }
  WHY="표식=$m rc=$rc stdout ${#o}바이트 ← $e"; return 1; }
c4() { local o rc s b k; b="$(mkb 4 "$1" "$BB")"; reg "$b" 4 || return 1; k="$(grep -c '\$M\.held' "$H")"
  hold "$b"; s="$(nsent)"; o="$(runh "$H" 2>&1)"; rc=$?; blocked "$o" "$rc" "$s" || { WHY="held 줄 ${k}개 · $WHY"; return 1; }
  [ "$k" = 1 ] || { WHY="진입 파일 held 확인 줄 ${k}개(1 이어야)"; return 1; }; }
c5() { local o rc s b; b="$(mkb 5 "$BB" "$1")"; reg "$b" 5 || return 1
  grep -q 'ft-hil-gate.sh' "$H" && [ "$(grep -c '\$M\.held' "$H")" = 0 ] || { WHY="기준판 새 꼴 진입 파일이 아님"; return 1; }
  hold "$b"; s="$(nsent)"; o="$(runh "$H" 2>&1)"; rc=$?; blocked "$o" "$rc" "$s"; }
c7() { local o a b; fresh 7; printf '#!/usr/bin/env bash\necho 손-진입\n' > "$HD/h4"
  printf '1794839302\nrc=3 1794839312\n' > "$HD/h5.ran"; printf 'hold 1794839196 seat#1 사유\n' > "$HD/h5.held"
  a="$(cat "$HD/h5.ran" "$HD/h5.held" | shasum -a 256)"; o="$(hil "$1" --add "$(plan p7 'set -euo pipefail' 'echo 새-계획')" 2>/dev/null)"
  b="$(cat "$HD/h5.ran" "$HD/h5.held" | shasum -a 256)"
  [ "$o" = "! bash $HD/h6" ] && [ ! -e "$HD/h5" ] && [ "$a" = "$b" ] && return 0
  WHY="발급=«${o}» h5 진입 파일=$([ -e "$HD/h5" ] && echo 1 || echo 0) 표지 바이트 $([ "$a" = "$b" ] && echo 같음 || echo 바뀜)"; return 1; }

sec "① 새 꼴 h 보류 → 실행 = REJECT rc1 · 계획 0 · .ran 0 · 쪽지 0"; chk "① 보류 h 실행 막힘" c1 "$BIN0"
sec "② 보류 → 해제 → 실행 = rc0 · 계획 1"; chk "② 해제 뒤 실행" c2 "$BIN0"
sec "③ .held 읽기 실패 주입 → 판정기 rc3 · 계획 바이트 0"; chk "③ 판정 불가 rc3" c3 "$BIN0"
sec "④ 새 진입 파일 held 줄 1 · 기준판 판정기로 바꿔도 막힘"; chk "④ 진입 파일 머리 막음" c4 "$BIN0"
sec "⑤ 기준판 진입 파일 + 고친 판정기 = 막힘"; chk "⑤ 이미 나간 새 꼴 h 막힘" c5 "$BIN0"
sec "⑦ h4 · h5.ran · h5.held → 새 번호 h6"; chk "⑦ 번호 재발급 0" c7 "$BIN0"
sec "bin=kit · 줄 상한"
for f in ft-hil.sh ft-hil-gate.sh; do cmp -s "$HERE/../bin/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"; done
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" = 200 ] && ok "ft-hil.sh ${n}줄(늘지 않음)" || bad "ft-hil.sh ${n}줄 ≠200"

if [ -z "${R2130_BIN:-}" ]; then
  sec "변이 M1~M4 — 사본 칸 FAIL · 원본 같은 칸 PASS"
  mut() {  # <이름> <파일> <perl 식> <칸 함수> [<칸 함수에 줄 bin 을 바꾸는 방식>]
    local m; m="$(mkb "mut-$1" "$BIN0" "$BIN0")"; perl -0pe "$3" "$BIN0/$2" > "$m/$2"
    cmp -s "$BIN0/$2" "$m/$2" && { bad "변이 $1 주입 실패(사본 = 원본)"; return; }
    if "$4" "$m" >/dev/null; then bad "변이 $1 → $4 PASS(못 잡음)"; return; fi; local w="$WHY"
    "$4" "$BIN0" >/dev/null && ok "변이 $1 → $4 FAIL($w) · 원본 PASS" || bad "변이 $1 원본 $4 FAIL — $WHY"; }
  mut M1-gate-held ft-hil-gate.sh 's/^.*r2130 K1.*\n//m' c5
  m1="$T/b-mut-M1-gate-held"; c1 "$m1" >/dev/null && ok "변이 M1 → ① PASS 남음(K2 진입 파일 머리가 먼저 막음 = 정상)" || bad "변이 M1 → ① FAIL — $WHY"
  mut M2-entry-held ft-hil.sh 's/^.*r2130 K2.*\n//m' c4
  mut M3-any-hold ft-hil-gate.sh 's/sed -n \x27\/\[\^\[:space:\]\]\/h; \$\{x;p;\}\x27 "\$3\.held"/sed -n \x27\/^hold \/{p;q;}\x27 "\$3.held"/' c2
  mut M4-maxn-entry ft-hil.sh 's/ n="\$\{n%%\.\*\}" &&//' c7
fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
