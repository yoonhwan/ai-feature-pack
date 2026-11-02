#!/usr/bin/env bash
# test_drift_check_landing_window_r1337.sh — 카드 r1337: 착지~설치 틈의 DIFF 를 «PENDING»(WARN rc 0)으로 내리는 갈래.
# D1~D10 + 변이 6 + 기준판(착지 전 판) D1·D8 FAIL. mktemp 만 쓴다 — 실 라이브·네트워크 0 · 자기 재호출 0 · 시계 = FT_DRIFT_NOW 고정.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_TEAMSET=0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
. "$HERE/lib/bin_source_deps.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G="git -c user.email=t@t -c user.name=t"
NOW=2000000000; export FT_DRIFT_NOW=$NOW
CUR="$SRC/ft-live-bin-drift-check.sh"
OLD="$HERE/fixtures/drift_check_pre_r1337.sh"   # 기준판 = 이 카드 착지 전 판(02294a33 의 사본 · 시험이 지금 판을 잡는지 보는 용)
[ -f "$OLD" ] || { echo "ERROR 기준판 fixture 없음: $OLD"; exit 1; }

# 작은 리포: $1=폴더. 커밋 시각은 GIT_COMMITTER_DATE(epoch). 경로 kit/bin/x (755)
commit_at() { # $1=repo $2=epoch $3=msg
  GIT_COMMITTER_DATE="$2 +0000" GIT_AUTHOR_DATE="$2 +0000" $G -C "$1" commit -q -m "$3"; }
put() { printf '%s\n' "$2" > "$1/kit/bin/$3"; chmod 755 "$1/kit/bin/$3"; }
mkrepo() { # $1=폴더 $2=c2 시각(epoch) — c1: x=A y=Y · c2: x=B
  git init -q -b main "$1"; mkdir -p "$1/kit/bin"; put "$1" A x; put "$1" Y y
  git -C "$1" add -A; commit_at "$1" $((NOW - 7200)) c1
  put "$1" B x; git -C "$1" add -A; commit_at "$1" "$2" c2; }
live() { # $1=폴더 $2=x 내용 [$3=y 내용]
  rm -rf "$1"; mkdir -p "$1"; printf '%s\n' "$2" > "$1/x"; chmod 755 "$1/x"; printf '%s\n' "${3:-Y}" > "$1/y"; chmod 755 "$1/y"; }
chk() { bash "$1" --bin "$2" --repo "$3" --ref main --path kit/bin 2>&1; }   # $1=검사 스크립트

d1() { local r="$T/d1.$RANDOM"; mkrepo "$r" $((NOW - 300)); live "$r.live" A
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?
  [ $rc -eq 0 ] && case "$o" in *"WARN 설치 대기 n=1"*"PENDING x 착지 "*" 5분 전"*) :;; *) false;; esac; }
d2() { local r="$T/d2.$RANDOM"; mkrepo "$r" $((NOW - 1200)); live "$r.live" A
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 1 ] && case "$o" in *"DIFF x"*) :;; *) false;; esac; }
d3() { local r="$T/d3.$RANDOM"; mkrepo "$r" $((NOW - 60)); live "$r.live" C
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 1 ] && case "$o" in *"DIFF x"*) :;; *) false;; esac; }
d4() { local r="$T/d4.$RANDOM"; mkrepo "$r" $((NOW - 60)); live "$r.live" A hand
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?
  [ $rc -eq 1 ] && case "$o" in *"PENDING x"*) case "$o" in *"DIFF y"*) :;; *) false;; esac;; *) false;; esac; }
d5() { local r="$T/d5.$RANDOM"; mkrepo "$r" $((NOW - 60)); live "$r.live" B
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 0 ] && case "$o" in "OK ref=main@"*) :;; *) false;; esac; }
d6() { local r="$T/d6.$RANDOM"; mkrepo "$r" $((NOW - 60)); put "$r" N z; git -C "$r" add -A; commit_at "$r" $((NOW - 30)) c3; live "$r.live" B
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 1 ] && case "$o" in *"MISSING z"*) :;; *) false;; esac; }
d7() { local r="$T/d7.$RANDOM" s="$T/d7stub"; mkrepo "$r" $((NOW - 300)); live "$r.live" A
  mkdir -p "$s"; local rg; rg="$(command -v git)"
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = log ] && exit 1; done\nexec "%s" "$@"\n' "$rg" > "$s/git"; chmod +x "$s/git"
  local o rc; o="$(PATH="$s:$PATH" chk "$1" "$r.live" "$r")"; rc=$?
  [ $rc -eq 3 ] && case "$o" in *ERROR*) case "$o" in *PENDING*) false;; *) :;; esac;; *) false;; esac; }
d9mk() { local r="$1"; git init -q -b main "$r"; mkdir -p "$r/kit/bin"; put "$r" A x; put "$r" Y y
  git -C "$r" add -A; commit_at "$r" $((NOW - 7200)) c0
  git -C "$r" checkout -q -b feat; put "$r" C x; git -C "$r" add -A; commit_at "$r" $((NOW - 200)) c1
  put "$r" B x; git -C "$r" add -A; commit_at "$r" $((NOW - 150)) c2
  git -C "$r" checkout -q main; put "$r" Z y; git -C "$r" add -A; commit_at "$r" $((NOW - 100)) cm   # main 이 앞서 가야 --no-ff 병합 커밋 M
  GIT_COMMITTER_DATE="$((NOW - 60)) +0000" $G -C "$r" merge -q --no-ff feat -m M >/dev/null 2>&1; }
d9() { local r="$T/d9.$RANDOM"; d9mk "$r"; live "$r.live" C Z
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 1 ] || return 1; case "$o" in *"DIFF x"*) :;; *) return 1;; esac
  live "$r.live2" A Z; o="$(chk "$1" "$r.live2" "$r")"; rc=$?; [ $rc -eq 0 ] && case "$o" in *"PENDING x"*) :;; *) false;; esac; }
d10() { local r="$T/d10.$RANDOM"; mkrepo "$r" $((NOW + 1800)); live "$r.live" A
  local o rc; o="$(chk "$1" "$r.live" "$r")"; rc=$?; [ $rc -eq 1 ] && case "$o" in *"DIFF x"*) :;; *) false;; esac; }

# D8: 키트 꼴 리포(검사 스크립트 $1 포함) + 설치 꼴 라이브 → spawn --dry-run·close 가 WARN 줄을 찍고 REJECT 하지 않는다
d8() { local base="$T/d8.$RANDOM" KP="harness/kit/fable-team/bin" o1 o2
  local seed="$base/seed" clone="$base/clone" live="$base/.fable-team/bin"
  git init -q -b main "$seed"; mkdir -p "$seed/$KP"
  local f; for f in ft-harness-root.sh ft-name-lint.sh ft-nano-spawn.sh ft-nano-close.sh ft-tick.sh ft-resource-gate.sh ft_teamset.py ft_team_lib.py ft_spawn_queue.py; do cp -p "$SRC/$f" "$seed/$KP/$f"; done
  cp -p "$1" "$seed/$KP/ft-live-bin-drift-check.sh"; chmod 755 "$seed/$KP/ft-live-bin-drift-check.sh"
  copy_source_deps "$SRC" "$seed/$KP" || return 1
  printf '#!/bin/sh\necho A\n' > "$seed/$KP/a.sh"; chmod 755 "$seed/$KP/a.sh"
  git -C "$seed" add -A; commit_at "$seed" $((NOW - 7200)) c1
  printf '#!/bin/sh\necho B\n' > "$seed/$KP/a.sh"; git -C "$seed" add -A; commit_at "$seed" $((NOW - 300)) c2
  git clone -q "$seed" "$clone" 2>/dev/null   # origin = seed (push 0)
  mkdir -p "$live"; for f in "$clone/$KP"/*; do cp -p "$f" "$live/"; done; printf '#!/bin/sh\necho A\n' > "$live/a.sh"
  mkdir -p "$base/fk"; printf '#!/bin/sh\necho byz-x-master-claude#1\n' > "$base/fk/tmm"; chmod +x "$base/fk/tmm"   # r975: spawn 은 드리프트 검사 «앞»에서 보고 대상을 tmm ls 로 푼다 — 가짜 tmm
  o1="$(cd "$clone" && PATH="$base/fk:$PATH" FT_HARNESS_ROOT="$clone/harness" FT_NANO_PREFIX=zz- bash "$live/ft-nano-spawn.sh" design/x/indices/대기/none.md --dry-run 2>&1)"
  o2="$(cd "$clone" && FT_HARNESS_ROOT="$clone/harness" FT_NANO_PREFIX=zz- bash "$live/ft-nano-close.sh" other-seat --result x --recv 1 2>&1)"
  [ -z "${R1337_DEBUG:-}" ] || { echo "--- spawn"; echo "$o1"; echo "--- close"; echo "$o2"; } >&2
  case "$o1" in *"REJECT 라이브 도구가"*) return 1;; esac; case "$o2" in *"REJECT 라이브 도구가"*) return 1;; esac
  case "$o1" in *"WARN 설치 대기"*"PENDING a.sh"*) :;; *) return 1;; esac; case "$o2" in *"WARN 설치 대기"*"PENDING a.sh"*) :;; *) return 1;; esac; }

for f in "$CUR"; do bash -n "$f" && ok "bash -n 검사 스크립트" || bad "bash -n 검사 스크립트"; done
t0=$SECONDS
for n in 1 2 3 4 5 6 7 9 10 8; do "d$n" "$CUR" && ok "D$n" || bad "D$n"; done
echo "# 현재판 단계 ${SECONDS}s(시작 $t0)"

# 기준판(착지 전): D1·D8 은 FAIL 이어야 한다(기준값 = 지금 판은 착지 직후 1분에도 DRIFT rc 1)
d1 "$OLD" && bad "기준판 D1 이 PASS — 시험이 지금 판을 못 잡음" || ok "기준판 D1 FAIL(기대)"
d8 "$OLD" && bad "기준판 D8 이 PASS — 시험이 지금 판을 못 잡음" || ok "기준판 D8 FAIL(기대)"

# 변이: 줄 하나씩 꺾은 사본 → 짝 시험이 FAIL 해야 한다 (꺾임이 실제로 적용됐는지 cmp 로 먼저 확인)
mut() { # $1=번호 $2=짝 시험 $3=원문 $4=대체
  local m="$T/mut$1.sh"; python3 -I -c '
import sys
s=open(sys.argv[1],encoding="utf-8").read()
if sys.argv[3] not in s: sys.exit(3)
open(sys.argv[5],"w",encoding="utf-8").write(s.replace(sys.argv[3],sys.argv[4],1))' "$CUR" "$1" "$3" "$4" "$m" || { bad "변이 $1 적용 실패(원문 없음)"; return; }
  cmp -s "$CUR" "$m" && { bad "변이 $1 가 판을 안 바꿈"; return; }
  "$2" "$m" && bad "변이 $1 이 살아남음 — $2 가 못 잡음" || ok "변이 $1 → $2 FAIL(기대)"; }
mut 1 d3  '[ "$prev" = "$3" ] || return 1' ':'
mut 2 d2  '{ [ "$age" -ge 0 ] && [ "$age" -le $((PW * 60)) ]; } || return 1' '{ [ "$age" -ge 0 ]; } || return 1'
mut 3 d4  'if [ -z "$items" ]; then  # r1337' 'if [ -n "$pends" ]; then  # r1337'
mut 4 d1  'echo "WARN 설치 대기 n=' 'echo "OK 설치 대기 n='
mut 5 d9  'log -1 --first-parent --format' 'log -1 --format'
mut 6 d10 '[ "$age" -ge 0 ] && ' ''

echo "--- 증거: 단계별 초 = 총 ${SECONDS}s"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
