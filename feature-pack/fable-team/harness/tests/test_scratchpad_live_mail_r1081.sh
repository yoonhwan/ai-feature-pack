#!/usr/bin/env bash
# test_scratchpad_live_mail_r1081.sh — ft-scratchpad-census.sh (r1081) 의 «LIVE 행 쪽지 갈래»: 72h 묵은 깨끗한 사본 → 그 세션 좌석 1통.
# 가짜 ps(--session-id + --name)·가짜 lsof·가짜 mbox 스텁·임시 루트·작은 실 git 저장소만 쓴다 — 실 scratchpad·실 쪽지·실 상태 파일 0 · 실 tmux 0.
# 대응표: ①R1·R6 ⓐ ②R2·R3 ⓑ ③R4·R5·R7 ⓒ ④R8 ⓓ ⑤bin·kit ⓔ · 변이 2(R4 문턱 끔 · 기록 읽기 끔)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
SUT="$HARNESS/bin/ft-scratchpad-census.sh"
KIT="$HARNESS/kit/fable-team/bin/ft-scratchpad-census.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -c user.email=a@b -c user.name=a -c advice.detachedHead=false "$@"; }
OLD="202501010000"                       # 72h 보다 훨씬 오래된 mtime(고정)
NEW="$(date -v-10H +%Y%m%d%H%M 2>/dev/null || date -d '10 hours ago' +%Y%m%d%H%M)"

MLOG="$T/mbox.log"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '#!/bin/sh\nexit 1\n' > "$T/mboxfail.sh"; chmod 755 "$T/mboxfail.sh"

# mkfix <이름> — 루트 R · 저장소 src · 빈 scratchpad 루트 · 가짜 ps/lsof. 이후 mkseat / mkcopy 로 사본을 만든다
mkfix() { F="$T/$1"; mkdir -p "$F/R/.fable-team/state" "$F/sp/proj"
  G init -q "$F/src"; ( cd "$F/src"; echo a > f; G add f; G commit -qm init )
  : > "$F/ps.txt"; printf 'p1\nn%s\n' "$F/elsewhere" > "$F/lsof.txt"; : > "$MLOG"
  MAILED="$F/R/.fable-team/state/scratchpad-mailed.tsv"; }
mkseat() { printf 'claude --name %s --session-id %s --foo\n' "$2" "$1" >> "$F/ps.txt"; }   # <uuid> <좌석이름>
mkcopy() { local d="$F/sp/proj/$1/scratchpad/$2"; mkdir -p "$d"; G clone -q "$F/src" "$d"; printf '%s' "$d"; }  # <uuid> <사본이름>
aged() { find "$F/sp" -depth -exec touch -h -t "$OLD" {} + 2>/dev/null; }
run() { : > "$MLOG"; env FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" \
  FT_SP_MBOX="${MBOX:-$T/mbox.sh}" FT_SP_MAILED="$MAILED" bash "${SUT_BIN:-$SUT}" > "$F/out" 2>"$F/err"; RC=$?; }
mails() { local n; n="$(grep -c . "$MLOG" 2>/dev/null)"; echo "${n:-0}"; }

# ⓐ R1·R6 — LIVE · 깨끗 · idle 80h · 좌석 이름 있음 → 쪽지 1통 · 기록 · 사본 3개는 한 통으로 묶음
mkfix a; mkseat u-a byz-harness-master-claude#9
A1="$(mkcopy u-a c1)"; A2="$(mkcopy u-a c2)"; A3="$(mkcopy u-a c3)"; aged; run
{ [ "$RC" = 0 ] && [ "$(mails)" = 1 ] && grep -q 'byz-harness-master-claude#9|ft-scratchpad-census|' "$MLOG" \
  && grep -q '\[scratchpad 사본\] 3개' "$MLOG" && grep -q 'GiB' "$MLOG" && grep -q '앞 3:' "$MLOG" \
  && grep -q "앞 3: $A1 ; $A2 ; $A3" "$MLOG" && grep -q 'ft-scratch-repo.sh' "$MLOG" \
  && grep -q '\[scratchpad 사본 쪽지\] 1통' "$F/out"; } \
  && ok "ⓐ R1·R6 LIVE 3개 → 좌석 1통(개수·GiB·앞 3)" || bad "ⓐ rc=$RC $(cat "$MLOG") $(cat "$F/out")"
{ [ "$(grep -c . "$MAILED")" = 3 ] && [ "$(awk -F'\t' 'NR==1{print NF}' "$MAILED")" = 3 ]; } \
  && ok "ⓐ 기록 3줄(경로·HEAD·보낸 날)" || bad "ⓐ 기록 $(cat "$MAILED" 2>/dev/null)"

# ⓑ R2·R3 — 같은 사본 다음 회차는 0통 · HEAD 가 바뀌면 그 사본만 다시 1통
run
{ [ "$(mails)" = 0 ] && grep -q '\[scratchpad 사본 쪽지\] 0통 · 이미 보냄 3' "$F/out"; } \
  && ok "ⓑ R2 같은 사본 다음 회차 → 쪽지 0" || bad "ⓑ R2 $(mails)통 $(cat "$F/out")"
( cd "$A1" && G commit -q --allow-empty -m bump ); touch -h -t "$OLD" "$A1"
run
{ [ "$(mails)" = 1 ] && grep -q '\[scratchpad 사본\] 1개' "$MLOG" && grep -q "앞 3: $A1$" "$MLOG"; } \
  && ok "ⓑ R3 HEAD 바뀜 → 새 HEAD 로 1통" || bad "ⓑ R3 $(cat "$MLOG") $(cat "$F/out")"

# ⓒ R4·R5·R7 — 최근 쓰기(mtime 10h) · 미커밋 · 유일커밋 · 이름 없음은 쪽지 0
mkfix c; mkseat u-old byz-x#1
printf 'claude --session-id u-new --foo\n' >> "$F/ps.txt"        # u-new 는 살아 있지만 --name 이 없다(R7)
C_OLD="$(mkcopy u-old c1)"; C_DIRTY="$(mkcopy u-old c2)"; C_UNIQ="$(mkcopy u-old c3)"; C_NEW="$(mkcopy u-old c4)"
nmk="$(mkcopy u-new c1)"
echo x >> "$C_DIRTY/f"; ( cd "$C_UNIQ" && G checkout -q --detach && echo b > g && G add g && G commit -qm orphan )
aged; touch -h -t "$NEW" "$C_NEW/f"
run
{ [ "$RC" = 0 ] && [ "$(mails)" = 1 ] && grep -q 'byz-x#1|' "$MLOG" && grep -q '\[scratchpad 사본\] 1개' "$MLOG" && [ -d "$C_UNIQ" ] && [ -d "$C_DIRTY" ]; } \
  && ok "ⓒ R4 최근쓰기 · R5 미커밋·유일커밋 → 쪽지 0(묵은 것만 1통)" || bad "ⓒ $(cat "$MLOG") $(cat "$F/out")"
grep -q '이름 없음 1' "$F/out" && ok "ⓒ R7 --name 없음 → 요약 «이름 없음 1»" || bad "ⓒ R7 요약 $(cat "$F/out")"
# 변이 ①: 72h 문턱을 꺼 버린다 → R4 사본(10h)도 쪽지 → ⓒ FAIL
: > "$MAILED"; : > "$MLOG"
grep -v -F '[ "$(idle_of "$p" 4320)" = ">=4320" ]' "$SUT" > "$T/mut-idle.sh"
SUT_BIN="$T/mut-idle.sh" run; SUT_BIN=""
{ [ "$(mails)" = 1 ] && grep -q '\[scratchpad 사본\] 2개' "$MLOG"; } \
  && ok "변이① 72h 문턱 끔 → R4 사본도 섞여 2개 ⓒ FAIL(잡힘)" || bad "변이① 못 잡음 $(cat "$MLOG")"

# ⓓ R8 — 발신 실패 → 기록 0 + 로그 1줄 · 다음 회차 다시 1통
mkfix d; mkseat u-d byz-z#3; D1="$(mkcopy u-d c1)"; aged
MBOX="$T/mboxfail.sh" run; MBOX=""
{ [ "$RC" = 0 ] && [ ! -s "$MAILED" ] && grep -q '발신 실패' "$F/R/.fable-team/state/scratchpad-mail.log" && grep -q '\[scratchpad 사본 쪽지\] 0통' "$F/out"; } \
  && ok "ⓓ R8 발신 실패 → 기록 0 · 로그 1줄" || bad "ⓓ rc=$RC 기록=$(cat "$MAILED" 2>/dev/null) $(cat "$F/err")"
run
{ [ "$(mails)" = 1 ] && grep -q "앞 3: $D1" "$MLOG" && [ "$(grep -c . "$MAILED")" = 1 ]; } \
  && ok "ⓓ R8 다음 회차 재시도 1통" || bad "ⓓ 재시도 $(cat "$MLOG")"
# 변이 ②: 기록 읽기를 꺼 버린다 → 같은 사본에 또 쪽지 → ⓑ FAIL
sed 's/mailed_already "\$p" "\$head" && flag=1/:/' "$SUT" > "$T/mut-rec.sh"
SUT_BIN="$T/mut-rec.sh" run; SUT_BIN=""
[ "$(mails)" = 1 ] && ok "변이② 기록 읽기 끔 → 같은 사본 또 쪽지 ⓑ FAIL(잡힘)" || bad "변이② 못 잡음 $(mails)통"

# ⓕ 발신 0 모드(결과 계약 §10.6 — 켜기 전 실 루트 확인용) → 쪽지 0 · 기록 0 · 목록만
mkfix f; mkseat u-f byz-f#5; F1="$(mkcopy u-f c1)"; aged
env FT_SP_MAIL_DRY=1 FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" \
  FT_SP_MBOX="$T/mbox.sh" FT_SP_MAILED="$MAILED" bash "$SUT" > "$F/out" 2>&1; RC=$?
{ [ "$RC" = 0 ] && [ "$(mails)" = 0 ] && [ ! -s "$MAILED" ] && grep -q '발신 0\] byz-f#5 ← .*앞 3: '"$F1" "$F/out"; } \
  && ok "ⓕ 발신 0 모드 → 쪽지 0 · 기록 0 · 목록 1줄" || bad "ⓕ rc=$RC $(cat "$F/out")"

# ⓔ bin·kit 같은 내용
cmp -s "$SUT" "$KIT" && ok "ⓔ bin·kit cmp0" || bad "ⓔ bin·kit 다름"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
