#!/usr/bin/env bash
# test_scratchpad_census_r1080.sh — ft-scratchpad-census.sh (r1080) 판정 표 · 스위치 삭제 · 예산 커서 · ft-disk-alarm 배선.
# 가짜 ps/lsof(FT_SP_PS_OUT·FT_SP_LSOF_OUT)·임시 루트·작은 실 git 저장소만 쓴다 — 실 scratchpad·실 쪽지·실 상태 파일 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
REPO="$(cd -- "$HARNESS/.." && pwd)"
SUT="$HARNESS/bin/ft-scratchpad-census.sh"
KIT="$HARNESS/kit/fable-team/bin/ft-scratchpad-census.sh"
ALARM="$HARNESS/bin/ft-disk-alarm.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -c user.email=a@b -c user.name=a -c advice.detachedHead=false "$@"; }
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"
OLD="202601010000"   # 25시간보다 오래된 mtime(고정) — «죽은 세션 · 오래된 사본» 조건

# mkfix <이름> — 루트 R · 사본 4개(깨끗 clone · linked · 미커밋 · 유일커밋) + 가짜 ps/lsof. 경로는 F_* 로 돌려준다
mkfix() { local n="$1"; F="$T/$n"; mkdir -p "$F/R/.fable-team/state"
  G init -q "$F/src"; ( cd "$F/src"; echo a > f; G add f; G commit -qm init )
  SP="$F/sp/proj"; mkdir -p "$SP/u-dead/scratchpad" "$SP/u-dirty/scratchpad" "$SP/u-uniq/scratchpad"
  G clone -q "$F/src" "$SP/u-dead/scratchpad/c1"
  G -C "$F/src" worktree add -q "$SP/u-dead/scratchpad/ln1" -b lnb
  cp -R "$SP/u-dead/scratchpad/c1" "$SP/u-dirty/scratchpad/c2"; echo x >> "$SP/u-dirty/scratchpad/c2/f"; echo y > "$SP/u-dirty/scratchpad/c2/g2"
  cp -R "$SP/u-dead/scratchpad/c1" "$SP/u-uniq/scratchpad/c3"
  ( cd "$SP/u-uniq/scratchpad/c3"; G checkout -q --detach; echo b > g; G add g; G commit -qm orphan )
  find "$SP" -depth -exec touch -h -t "$OLD" {} + 2>/dev/null
  printf -- 'python -m x --session-id u-live --foo\n' > "$F/ps.txt"
  printf 'p1\nn%s\n' "$F/elsewhere" > "$F/lsof.txt"
  F_DEAD="$SP/u-dead/scratchpad"; F_DIRTY="$SP/u-dirty/scratchpad/c2"; F_UNIQ="$SP/u-uniq/scratchpad/c3"; }
run() { env FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" \
  FT_SP_BUDGET_SEC="${BUD:-60}" bash "${SUT_BIN:-$SUT}" > "$F/out" 2>"$F/err"; RC=$?; }
row() { grep -F "$1" "$F/R/.fable-team/state/scratchpad-census.tsv" 2>/dev/null | head -1; }
SW="$T/switchdir"; mkdir -p "$SW"

# ⓐ R1 — 죽은 세션 · 깨끗 · 25h → DEAD-SAFE · 스위치 없음 → 삭제 0 · 폴더 그대로
mkfix a; run
{ [ "$RC" = 0 ] && row "$F_DEAD/c1" | grep -q '^DEAD-SAFE' && [ -d "$F_DEAD/c1" ] && grep -q 'DEAD-SAFE 2개' "$F/out" && grep -q '삭제 0' "$F/out"; } \
  && ok "ⓐ R1 DEAD-SAFE · 스위치 없음 → 삭제 0" || bad "ⓐ rc=$RC $(cat "$F/out") $(row "$F_DEAD/c1")"
[ -s "$F/R/.fable-team/state/scratchpad-census.tsv" ] && [ "$(grep -c . "$F/R/.fable-team/state/scratchpad-census.tsv")" = 4 ] \
  && ok "ⓐ 표 4줄(탭 9칸)" || bad "ⓐ 표 $(grep -c . "$F/R/.fable-team/state/scratchpad-census.tsv" 2>/dev/null)"
[ "$(awk -F'\t' 'NR==1{print NF}' "$F/R/.fable-team/state/scratchpad-census.tsv")" = 9 ] && ok "ⓐ 줄마다 9칸" || bad "ⓐ 칸수"

# ⓑ R2 — 같은 조건 + 스위치 파일 → 로그 먼저(경로·HEAD·remote·MB) → clone 폴더 삭제 · linked worktree 목록에서 빠짐
mkfix b; mkdir -p "$F/R/.fable-team/state"; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; run
SLOG="$F/R/.fable-team/state/scratchpad-sweep.log"
{ [ "$RC" = 0 ] && [ ! -e "$F_DEAD/c1" ] && ! G -C "$F/src" worktree list | grep -q "ln1" && grep -q '삭제 2' "$F/out"; } \
  && ok "ⓑ R2 스위치 켬 → clone 폴더 삭제 · linked worktree remove" || bad "ⓑ rc=$RC $(cat "$F/out") $(G -C "$F/src" worktree list)"
{ [ "$(grep -c . "$SLOG")" = 2 ] && grep -q -F "$F_DEAD/c1" "$SLOG" && grep -q 'HEAD=' "$SLOG" && grep -q 'remote=' "$SLOG" && grep -q 'MB=' "$SLOG"; } \
  && ok "ⓑ 로그 2줄(경로·HEAD·remote·MB)" || bad "ⓑ 로그 $(cat "$SLOG" 2>/dev/null)"
# 변이 ①: 로그 쓰기를 꺼도 지워 버린다 → ⓑ 가 잡아야 한다
grep -v -F 'remote=%s' "$SUT" > "$T/mut-nolog.sh"
mkfix mb; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; SUT_BIN="$T/mut-nolog.sh" run; SUT_BIN=""
{ [ ! -e "$F_DEAD/c1" ] && [ -z "$(grep 'HEAD=' "$F/R/.fable-team/state/scratchpad-sweep.log" 2>/dev/null)" ]; } \
  && ok "변이① 로그 없이 삭제 → ⓑ FAIL(잡힘)" || bad "변이① 못 잡음"

# ⓒ R3·R4·R5·R7 — 지키는 조건은 스위치를 켜도 지우지 않는다
mkfix c
printf 'p1\nn%s\nn%s\n' "$F_DEAD/c1" "$F_DEAD/ln1" > "$F/lsof.txt"   # R7: c1·ln1 을 cwd 로 쥔 프로세스
: > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; run
{ row "$F_DEAD/c1" | grep -q 'cwd사용중' && row "$F_DIRTY" | grep -q '미커밋2' && row "$F_UNIQ" | grep -q '유일커밋'; } \
  && ok "ⓒ R7 cwd사용중 · R3 미커밋2 · R4 유일커밋" || bad "ⓒ $(cut -f1,6,7 "$F/R/.fable-team/state/scratchpad-census.tsv")"
{ [ -d "$F_DEAD/c1" ] && [ -d "$F_DIRTY" ] && [ -d "$F_UNIQ" ] && grep -q '삭제 0' "$F/out"; } && ok "ⓒ 스위치 켜도 지키는 사본 삭제 0" || bad "ⓒ 삭제 $(cat "$F/out")"
mkfix r5; touch -t "$(date -v-30M +%Y%m%d%H%M)" "$F_DEAD/c1/f" 2>/dev/null; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; run
{ row "$F_DEAD/c1" | grep -q '최근쓰기' && [ -d "$F_DEAD/c1" ]; } && ok "ⓒ R5 idle 30분 → 최근쓰기 · 삭제 0" || bad "ⓒ R5 $(row "$F_DEAD/c1")"
# 변이 ②: 유일커밋 검사를 꺼 버린다 → R4 사본을 지워 버려야 한다(잡히면 ok)
grep -v -F 'V_REASON="유일커밋"' "$SUT" > "$T/mut-uniq.sh"
mkfix mq; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; SUT_BIN="$T/mut-uniq.sh" run; SUT_BIN=""
{ [ ! -e "$F_UNIQ" ] && [ -d "$F_DIRTY" ]; } && ok "변이② 유일커밋 검사 끔 → R4 사본 삭제 ⓒ FAIL(잡힘)" || bad "변이② 못 잡음(uniq 남음)"

# ⓓ R6 — 살아 있는 세션은 LIVE · 삭제 0
mkfix d; mkdir -p "$F/sp/proj/u-live/scratchpad"; cp -R "$F_DEAD/c1" "$F/sp/proj/u-live/scratchpad/c4"
find "$F/sp" -depth -exec touch -h -t "$OLD" {} + 2>/dev/null; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"; run
{ row "$F/sp/proj/u-live/scratchpad/c4" | grep -q '^LIVE' && [ -d "$F/sp/proj/u-live/scratchpad/c4" ] && grep -q 'LIVE 1' "$F/out"; } \
  && ok "ⓓ R6 LIVE · 삭제 0" || bad "ⓓ $(row "$F/sp/proj/u-live/scratchpad/c4") $(cat "$F/out")"

# ⓔ R8 — ps 실패 또는 lsof 0줄 → «판정 불가» rc2 · 표 0 · 삭제 0
mkfix e; : > "$F/R/.fable-team/state/scratchpad-sweep.enabled"
env FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$T/nope.ps" FT_SP_LSOF_OUT="$F/lsof.txt" bash "$SUT" >"$F/out" 2>"$F/err"; RC=$?
{ [ "$RC" = 2 ] && grep -q '판정 불가' "$F/out" && [ ! -e "$F/R/.fable-team/state/scratchpad-census.tsv" ] && [ -d "$F_DEAD/c1" ]; } \
  && ok "ⓔ R8 ps 실패 → rc2 · 판정 불가 1줄 · 표 0 · 삭제 0" || bad "ⓔ rc=$RC $(cat "$F/out")"
: > "$F/lsof.txt"; env FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" bash "$SUT" >"$F/out" 2>&1; RC=$?
{ [ "$RC" = 2 ] && grep -q '판정 불가' "$F/out" && [ ! -e "$F/R/.fable-team/state/scratchpad-census.tsv" ]; } \
  && ok "ⓔ R8 lsof 0줄 → rc2 · 판정 불가" || bad "ⓔ lsof rc=$RC $(cat "$F/out")"

# ⓕ R9 — 지우기 직전 재판정에서 dirty 가 생기면 삭제 0 + 로그 «재판정 거절»
mkfix f; REALGIT="$(command -v git)"; mkdir -p "$T/fakegit"
printf '#!/bin/sh\ncase "$*" in *"status --porcelain"*) n=$(cat "%s/n" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "%s/n"; [ $n -ge 2 ] && { echo " M f"; exit 0; };; esac\nexec %s "$@"\n' "$F" "$F" "$REALGIT" > "$T/fakegit/git"; chmod 755 "$T/fakegit/git"
: > "$F/R/.fable-team/state/scratchpad-sweep.enabled"
env PATH="$T/fakegit:$PATH" FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" bash "$SUT" >"$F/out" 2>&1; RC=$?
{ [ "$RC" = 0 ] && [ -d "$F_DEAD/c1" ] && grep -q '재판정 거절' "$F/R/.fable-team/state/scratchpad-sweep.log" 2>/dev/null && grep -q '삭제 0' "$F/out"; } \
  && ok "ⓕ R9 재판정 dirty → 삭제 0 · «재판정 거절»" || bad "ⓕ rc=$RC $(cat "$F/out") $(cat "$F/R/.fable-team/state/scratchpad-sweep.log" 2>/dev/null)"

# ⓖ1 예산 0 → 외부 호출 0 · «부분 0/4» · 커서 파일 · 다음 회차가 이어 봄
mkfix g; BUD=0 run
CUR="$F/R/.fable-team/state/scratchpad-census.cursor"
{ grep -q '부분 0/4' "$F/out" && [ -s "$CUR" ] && [ -d "$F_DEAD/c1" ]; } && ok "ⓖ1 예산 0 → 부분 0/4 · 커서" || bad "ⓖ1 $(cat "$F/out")"
BUD=60 run; { grep -q 'DEAD-SAFE 2개' "$F/out" && [ ! -e "$CUR" ]; } && ok "ⓖ1 다음 회차가 커서를 이어 봄 · 커서 해소" || bad "ⓖ1 이어보기 $(cat "$F/out")"
# ⓖ2 양수 예산 · 느린 가짜 git(호출마다 2초) · 사본 4개 → 벽시계 ≤4초 · «부분 k/4»(k<4) · 커서
mkfix g2; mkdir -p "$T/slowgit"
printf '#!/bin/sh\nsleep 2\nexec git "$@"\n' > "$T/slowgit/git"; chmod 755 "$T/slowgit/git"
s=$(date +%s); BUD=3 env PATH="$T/slowgit:$PATH" FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" FT_SP_BUDGET_SEC=3 bash "$SUT" >"$F/out" 2>&1; e=$(date +%s)
dt=$((e-s)); k="$(sed -n 's/.*부분 \([0-9]*\)\/4.*/\1/p' "$F/out")"
{ [ "$dt" -le 4 ] && [ -n "$k" ] && [ "$k" -lt 4 ] && [ -s "$F/R/.fable-team/state/scratchpad-census.cursor" ]; } \
  && ok "ⓖ2 예산 3초 · 느린 git → ${dt}초 · 부분 ${k}/4 · 커서" || bad "ⓖ2 dt=$dt k='$k' $(cat "$F/out")"
# 변이 ③: 호출 상한을 «남은 예산» 대신 7초 고정 → 벽시계가 상한을 넘어야 한다(잡히면 ok)
sed 's/\[ "\$r" -gt 7 \] \&\& echo 7 || echo "\$r"/echo 7/' "$SUT" > "$T/mut-cap.sh"
s=$(date +%s); env PATH="$T/slowgit:$PATH" FT_RES_ROOT="$F/R" FT_SP_ROOT="$F/sp" FT_SP_PS_OUT="$F/ps.txt" FT_SP_LSOF_OUT="$F/lsof.txt" FT_SP_BUDGET_SEC=3 bash "$T/mut-cap.sh" >"$F/out2" 2>&1; e=$(date +%s)
dt2=$((e-s)); [ "$dt2" -gt 4 ] && ok "변이③ 호출 상한 7초 고정 → ${dt2}초(>4) ⓖ2 FAIL(잡힘)" || bad "변이③ 고정 상한이 안 잡힘 dt=$dt2"

# ⓗ ft-disk-alarm 배선 — 86400 타이머 · 요약 1통 · rc2 = 실패 1통 · 모두 0 이면 0통
MLOG="$T/mbox.log"; : > "$MLOG"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '{"_hil_route":"byz-planner-master-claude#99"}\n' > "$T/seats.json"
mkfix h; NOW=1000000
printf '#!/bin/sh\necho "[scratchpad 사본] DEAD-SAFE 2개 0.40GiB · DEAD-KEEP 1 · LIVE 0 · UNKNOWN 0 · 삭제 0"\n' > "$T/spc.sh"; chmod 755 "$T/spc.sh"
alarm() { : > "$MLOG"; env FT_RES_ROOT="$F/R" FT_DISK_FREE_GIB=60 FT_DISK_NOW=$((NOW+$1)) FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json" \
  FT_RES_WATCH_SH="$T/noop.sh" FT_SCRATCH_REPO_SH="$T/noop.sh" FT_DOCKER_REAP_SH="$T/noop.sh" FT_WT_MODE_STAMP_SH="$T/noop.sh" \
  FT_SCRATCHPAD_CENSUS_SH="$T/spc.sh" bash "$ALARM" >"$F/out" 2>&1; }
alarm 0; { [ "$(grep -c . "$MLOG")" = 1 ] && grep -q 'DEAD-SAFE 2개' "$MLOG" && grep -q 'byz-planner-master-claude#99|' "$MLOG"; } \
  && ok "ⓗ 요약 0 아님 → planner 1통" || bad "ⓗ $(cat "$MLOG")"
alarm 1000; [ "$(grep -c . "$MLOG")" = 0 ] && ok "ⓗ 하루 안 재호출 0" || bad "ⓗ 재호출 $(cat "$MLOG")"
printf '#!/bin/sh\necho "[scratchpad 사본] DEAD-SAFE 0개 0.00GiB · DEAD-KEEP 0 · LIVE 3 · UNKNOWN 0 · 삭제 0"\n' > "$T/spc0.sh"; chmod 755 "$T/spc0.sh"
FT_SCRATCHPAD_CENSUS_SH="$T/spc0.sh" :; printf '#!/bin/sh\nexit 2\n' > "$T/spcf.sh"; chmod 755 "$T/spcf.sh"
printf '#!/bin/sh\necho "판정 불가: ps 실패 또는 0줄" >&2\nexit 2\n' > "$T/spcf.sh"
alarm2() { : > "$MLOG"; env FT_RES_ROOT="$F/R" FT_DISK_FREE_GIB=60 FT_DISK_NOW=$((NOW+$1)) FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json" \
  FT_RES_WATCH_SH="$T/noop.sh" FT_SCRATCH_REPO_SH="$T/noop.sh" FT_DOCKER_REAP_SH="$T/noop.sh" FT_WT_MODE_STAMP_SH="$T/noop.sh" \
  FT_SCRATCHPAD_CENSUS_SH="$2" bash "$ALARM" >"$F/out" 2>&1; }
alarm2 90000 "$T/spc0.sh"; [ "$(grep -c . "$MLOG")" = 0 ] && ok "ⓗ 모두 0 → 쪽지 0" || bad "ⓗ 0 인데 쪽지 $(cat "$MLOG")"
alarm2 190000 "$T/spcf.sh"; { [ "$(grep -c . "$MLOG")" = 1 ] && grep -q '\[scratchpad 사본 표 실패\] rc=2' "$MLOG" && grep -q 'scratchpad-census rc=2' "$F/R/.fable-team/state/disk-alarm.log"; } \
  && ok "ⓗ rc2 → 실패 1통 + 로그(조용한 0 없음)" || bad "ⓗ 실패 $(cat "$MLOG")"

# ⓘ bin·kit 같은 내용
cmp -s "$SUT" "$KIT" && cmp -s "$ALARM" "$HARNESS/kit/fable-team/bin/ft-disk-alarm.sh" && ok "ⓘ bin·kit cmp0 (2쌍)" || bad "ⓘ bin·kit 다름"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
