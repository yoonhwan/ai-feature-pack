#!/usr/bin/env bash
# test_hil_entry_state_dir_r1126.sh — r1126: 진입 파일 /tmp/h<N> 이 계획 리포 공용 루트로 cd + FT_ROOT unset(리졸버 = 그 리포 LIVE_ROOT)
#   · approve-merge 는 FT_ROOT 가 LIVE_ROOT 와 어긋나면 쓰기 0 rc1 · .ran 이어 쓰기 (카드 반례 R1~R9 · 변이 3)
# 격리: 임시 리포(.fable-team/LIVE_ROOT → 임시 라이브 워크트리 · 둘 다 .fable-team/state) · 임시 HIL_DIR · 가짜 mbox.sh(sent.log)
#   실 gh·Slack·실 리포 state·실 /tmp/h* 0 · 자기 재호출 0(변이는 bin 사본을 함수로 돌린다) · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
SHA=0123456789abcdef0123456789abcdef01234567

C="$T/comm"; mkdir -p "$C" "$T/home"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" "$2" "$3" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"; printf '{"_master": "byz-planner-master-claude#1"}\n' > "$T/seats-planner.json"
R="$T/repo"; L="$T/live"
git init -q "$R" && git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git -C "$R" worktree add -q "$L" -b live 2>/dev/null || { echo "FAIL 픽스처 리포"; exit 1; }
mkdir -p "$R/.fable-team/state" "$L/.fable-team/state" "$R/.fable-team/plans"; printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"
git init -q "$T/nolive" && mkdir -p "$T/nolive/.fable-team"   # R6: 리포 안 · LIVE_ROOT 없음
mkdir -p "$T/old/.fable-team/state"                           # R8: 옛 설치 꼴(git 밖 · LIVE_ROOT 없음)

hil()  { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$b/ft-hil.sh" "$@"; }
runh() { local cwd="$1"; shift; ( cd "$cwd" && env -i HOME="$T/home" PATH="/usr/bin:/bin" "$@" ); }   # 오빠 `bash /tmp/h<N>` (env 는 인자로 준 것만)
probe() {  # <bin> <이름> [머리 줄] → 리포 안 계획: pwd · FT_ROOT · state-dir 출력(+ 머리 줄)
  { echo '#!/usr/bin/env bash'; [ -z "${3:-}" ] || echo "$3"
    echo 'echo "PWD=$(pwd -P)"; echo "FTR=${FT_ROOT-<unset>}"'; echo "echo \"SD=\$(bash '$1/ft-autonomy.sh' state-dir)\""; echo 'exit 5'; } > "$R/.fable-team/plans/$2.sh.hil"
}
approver() {  # <bin> <이름> [머리 줄] → 리포 안 계획: approve-merge 1건
  { echo '#!/usr/bin/env bash'; [ -z "${3:-}" ] || echo "$3"; echo "bash '$1/ft-autonomy.sh' approve-merge $SHA"; } > "$R/.fable-team/plans/$2.sh.hil"
}
nfiles() { find "$R/.fable-team/state" "$L/.fable-team/state" -path '*autonomy-merge-approved/*' -type f 2>/dev/null | grep -c .; }
clean_state() { rm -rf "$R/.fable-team/state" "$L/.fable-team/state" && mkdir -p "$R/.fable-team/state" "$L/.fable-team/state"; }

check_cwd_unset() {  # <bin> → R1·R2·R3 실패 수(0 = 통과) · 화면에 PASS/FAIL
  local b="$1" f0=$fail o rc h
  HD="$T/hd-$RANDOM"; mkdir -p "$HD"; probe "$b" r1; h="$(hil "$b" --add "$R/.fable-team/plans/r1.sh.hil" 2>/dev/null)"; h="${h#! bash }"
  o="$(runh /tmp bash "$h" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && ok "R1 cwd=/tmp → rc = 계획 rc(5)" || bad "R1 rc=$rc"
  has "$o" "PWD=$R" "R1 계획 안 pwd = 리포 공용 루트"; has "$o" "FTR=<unset>" "R1 FT_ROOT 없음"; has "$o" "SD=$L/.fable-team/state" "R1 state-dir = LIVE_ROOT 쪽"
  o="$(runh "$R" bash "$h" 2>/dev/null)"
  has "$o" "SD=$L/.fable-team/state" "R2 cwd=리포 루트 · FT_ROOT 없음 → 같은 state-dir"
  o="$(runh /tmp FT_ROOT="$R" bash "$h" 2>/dev/null)"
  has "$o" "FTR=<unset>" "R3 부른 env FT_ROOT=리포 루트 → 진입 파일이 지움"; has "$o" "SD=$L/.fable-team/state" "R3 state-dir = LIVE_ROOT 쪽(h209 꼴 막힘)"
  return $((fail - f0))
}

check_approve() {  # <bin> → R4·R5 실패 수
  local b="$1" f0=$fail h e rc
  HD="$T/hd-$RANDOM"; mkdir -p "$HD"; clean_state
  approver "$b" r4 "export FT_ROOT='$R'"; h="$(hil "$b" --add "$R/.fable-team/plans/r4.sh.hil" 2>/dev/null)"; h="${h#! bash }"
  e="$(runh /tmp bash "$h" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 1 ] && ok "R4 계획 머리 export FT_ROOT=리포 루트 → rc 1" || bad "R4 rc=$rc"
  has "$e" "REJECT 승인 폴더 어긋남 — FT_ROOT=$R · 라이브 루트=$L" "R4 stderr «승인 폴더 어긋남»"
  [ "$(nfiles)" = 0 ] && ok "R4 승인 파일 0(어느 폴더에도)" || bad "R4 승인 파일 $(nfiles)개"
  clean_state; approver "$b" r5 "export FT_ROOT='$L'"; h="$(hil "$b" --add "$R/.fable-team/plans/r5.sh.hil" 2>/dev/null)"; h="${h#! bash }"
  runh /tmp bash "$h" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -f "$L/.fable-team/state/autonomy-merge-approved/$SHA" ] && [ "$(nfiles)" = 1 ] && ok "R5 export FT_ROOT=LIVE_ROOT → 통과 · 파일 = 착지가 읽는 폴더" || bad "R5 rc=$rc 파일 $(nfiles)개"
  clean_state; approver "$b" r5b; h="$(hil "$b" --add "$R/.fable-team/plans/r5b.sh.hil" 2>/dev/null)"; h="${h#! bash }"
  runh /tmp FT_ROOT="$R" bash "$h" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ -f "$L/.fable-team/state/autonomy-merge-approved/$SHA" ] && [ "$(nfiles)" = 1 ] && ok "R5 머리 없음 · cwd=/tmp · 부른 env FT_ROOT=리포 → 승인 파일 = LIVE_ROOT state" || bad "R5b rc=$rc 파일 $(nfiles)개"
  return $((fail - f0))
}

check_ran_append() {  # <bin> → R7 실패 수
  local b="$1" f0=$fail h n
  HD="$T/hd-$RANDOM"; mkdir -p "$HD"
  printf '#!/usr/bin/env bash\n[ -e "%s/r7.ok" ] && exit 0\ntouch "%s/r7.ok"; exit 1\n' "$T" "$T" > "$R/.fable-team/plans/r7.sh.hil"; rm -f "$T/r7.ok"
  h="$(hil "$b" --add "$R/.fable-team/plans/r7.sh.hil" 2>/dev/null)"; h="${h#! bash }"
  runh /tmp bash "$h" >/dev/null 2>&1; runh /tmp bash "$h" >/dev/null 2>&1
  n="$(grep -cE '^rc=[0-9]+ [0-9]+$' "$h.ran")"
  [ "$n" = 2 ] && grep -q '^rc=1 ' "$h.ran" && [ "$(tail -n 1 "$h.ran" | cut -d' ' -f1)" = rc=0 ] && ok "R7 두 실행 다 남음(rc=1 · rc=0 · 마지막 rc=0)" || bad "R7 .ran: $(tr '\n' '|' < "$h.ran")"
  [ "$(grep -cE '^[0-9]+$' "$h.ran")" = 2 ] && ok "R7 시작 줄 2개" || bad "R7 시작 줄 수"
  has "$(hil "$b")" "rc=0" "R7 목록 = 마지막 실행 rc=0"; [ -z "$(hil "$b" --pending)" ] && ok "R7 --pending 0(마지막 실행 끝)" || bad "R7 pending"
  return $((fail - f0))
}

echo "== ⓐ R1·R2·R3 cwd 무관 · FT_ROOT 지움 · state-dir = LIVE_ROOT"; check_cwd_unset "$BIN0"
echo "== ⓑ R4·R5 approve-merge 폴더 대조"; check_approve "$BIN0"
echo "== ⓑ R8 FT_ROOT 있음 · LIVE_ROOT 없음(옛 설치 꼴) → 지금 그대로"
o="$(env -i HOME="$T/home" PATH="/usr/bin:/bin" FT_ROOT="$T/old" bash "$BIN0/ft-autonomy.sh" approve-merge "$SHA" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -f "$T/old/.fable-team/state/autonomy-merge-approved/$SHA" ] && has "$o" "APPROVED $SHA OFF" "R8 rc0 · 승인 파일 = FT_ROOT state" || bad "R8 rc=$rc out=$o"

echo "== ⓒ R6 리포 안 · LIVE_ROOT 없음 → 판정 불가 rc3 · 계획 실행 0"
HD="$T/hd-r6"; mkdir -p "$HD"; printf '#!/usr/bin/env bash\ntouch "%s/r6.ran-plan"\n' "$T" > "$T/nolive/r6.sh.hil"
h="$(hil "$BIN0" --add "$T/nolive/r6.sh.hil" 2>/dev/null)"; h="${h#! bash }"; rm -f "$C/sent.log"; e="$(runh /tmp bash "$h" 2>&1 >/dev/null)"; rc=$?
[ "$rc" = 3 ] && ok "R6 rc 3" || bad "R6 rc=$rc"; has "$e" "판정 불가 — 계획 $T/nolive/r6.sh.hil 의 리포($T/nolive)에 .fable-team/LIVE_ROOT 없음" "R6 stderr 판정 불가 1줄"
[ ! -e "$T/r6.ran-plan" ] && ok "R6 계획 실행 0" || bad "R6 계획이 실행됨"; [ "$(tail -n 1 "$h.ran" | cut -d' ' -f1)" = rc=3 ] && ok "R6 .ran rc=3 기록" || bad "R6 .ran: $(cat "$h.ran")"
grep -q "ft-hil-${h##*/}" "$C/sent.log" 2>/dev/null && ok "R6 결과 쪽지 그대로(r1117)" || bad "R6 결과 쪽지 없음"

echo "== ⓒ R9 --cmd 계획(git 밖) → 지금처럼(cd·unset 0) + INFO"
HD="$T/hd-r9"; mkdir -p "$HD"; h="$(hil "$BIN0" --cmd 'echo "PWD=$(pwd -P) FTR=${FT_ROOT-<unset>}"; exit 4' 2>/dev/null)"; h="${h#! bash }"
o="$(runh /tmp FT_ROOT=/x/y bash "$h" 2>"$T/e9")"; rc=$?
[ "$rc" = 4 ] && ok "R9 rc = 계획 rc(4)" || bad "R9 rc=$rc"; has "$o" "PWD=$(cd /tmp && pwd -P) FTR=/x/y" "R9 cd 0 · FT_ROOT 그대로"
[ "$(grep -c 'INFO 리포 밖 계획 — cd 0' "$T/e9")" = 1 ] && ok "R9 stderr INFO 1줄" || bad "R9 stderr: $(cat "$T/e9")"

echo "== ⓓ R7 .ran 이어 쓰기"; check_ran_append "$BIN0"

echo "== ⓔ bin·kit 같은 내용 · ft-hil.sh ≤200줄"
for f in ft-hil.sh ft-autonomy.sh ft_hil_pending.py; do cmp -s "$BIN0/$f" "$HERE/../kit/fable-team/bin/$f" && ok "cmp0 $f" || bad "키트 다름 $f"; done
for f in ft-hil.sh ft-autonomy.sh; do [ "$(wc -l < "$BIN0/$f")" -le 200 ] && ok "200줄 이하 $f" || bad "200줄 초과 $f"; done

mutant() {  # <이름> <파일> <sed 식> → 변이 bin 경로(원본과 다르면)
  local m="$T/mut-$1"; cp -R "$BIN0" "$m" && sed "$3" "$BIN0/$2" > "$m/$2"
  cmp -s "$BIN0/$2" "$m/$2" && { bad "변이 $1 사본 = 원본"; return 1; }; echo "$m"
}
echo "== 변이 3 — 각 변이가 대응 칸을 FAIL 시킨다(검출)"
mutv() { local f0=$fail out; out="$("$@" 2>&1)"; local d=$?; fail=$f0; [ "$d" -gt 0 ]; }
m="$(mutant unset ft-hil.sh 's/; then unset FT_ROOT; else/; then :; else/')" && { mutv check_cwd_unset "$m" && ok "변이 1(unset 삭제) → R3 FAIL 검출" || bad "변이 1 을 못 잡음"; }
m="$(mutant guard ft-autonomy.sh 's/  live_match || exit 1; lock;/  lock;/')" && { mutv check_approve "$m" && ok "변이 2(폴더 대조 삭제) → R4 FAIL 검출" || bad "변이 2 를 못 잡음"; }
m="$(mutant append ft-hil.sh 's/^date +%s >> "\$M.ran"$/date +%s > "$M.ran"/')" && { mutv check_ran_append "$m" && ok "변이 3(>>→>) → R7 FAIL 검출" || bad "변이 3 을 못 잡음"; }

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
