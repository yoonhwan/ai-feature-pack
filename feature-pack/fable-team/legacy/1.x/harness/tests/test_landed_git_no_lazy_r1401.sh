#!/usr/bin/env bash
# test_landed_git_no_lazy_r1401.sh — r1401: 착지 sha 조회(_ft_landed_git · ft-team-lib.sh)가 partial clone(blob:none)에서 «없는 sha» 를 원격 lazy fetch 로 받으려 7초 상한을 넘던 것 → GIT_NO_LAZY_FETCH=1 1줄.
#   사건(카드 r1401 · arch#228 실측 11-05): 카드 이동의 정본 게이트가 팩 착지 sha 를 BYZ 루트(blob:none · promisor)에 물으면 git 이 원격에서 그 객체를 받으려 한다.
#     실측: lazy 켬 13.1초 rc1(«upload-pack: not our ref») · GIT_NO_LAZY_FETCH=1 0.1초 rc1 · 있는 sha 는 0.1초 rc0 → 7초 상한 초과로 카드 이동이 «조회 실패» REJECT.
#   대역 = 로컬 bare 원격(uploadpack.allowFilter) + blob:none partial clone + «느린 upload-pack»(호출 1줄 기록 + 3초) — 실 원격 0 · 실 리포 0 · 실 라이브 쓰기 0 · timeout 70.
#   SRC=<bin 폴더> 로 옛 판(기준판)·변이를 같은 시험으로 돌린다. rc 규약은 _ft_landed_git 그대로: 0 = 로컬에 있음 · 1 = 로컬에 없음.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_TERMINAL_PROMPT=0
mkdir -p "$HOME"
BIN="$T/bin"; mkdir -p "$BIN"
cp -p "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$BIN/"
. "$BIN/ft-team-lib.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
now() { python3 -c 'import time;print(int(time.time()*1000))'; }
ms_of() { python3 -c "import time;print(int(time.time()*1000)-$1)"; }

# ── 원격(bare · 필터 허용) + 느린 upload-pack 대역 — 호출 1줄 기록 + 3초(7초 상한을 넘기게 한다)
OR="$T/origin"; UP="$T/up.sh"; UPL="$T/upcalls"
git init -q --bare "$OR"; g "$OR" config uploadpack.allowFilter true
{ echo '#!/bin/bash'; echo "echo x >> $UPL"; echo 'sleep 3'; printf 'exec %s "$@"\n' "$(git --exec-path)/git-upload-pack"; } > "$UP"; chmod 755 "$UP"
: > "$UPL"
upn() { wc -l < "$UPL" | tr -d ' '; }
# C1 = 클론 때 이미 있는 커밋 · R1 = 클론 «뒤» 원격에만 생긴 커밋(partial clone 에는 없다)
MK="$T/mk"; git init -q "$MK"; g "$MK" remote add origin "file://$OR"
g "$MK" commit -q --allow-empty -m c1; g "$MK" push -q origin HEAD:refs/heads/main; C1="$(g "$MK" rev-parse HEAD)"
PC="$T/pc"; git clone -q --filter=blob:none --no-local "file://$OR" "$PC" 2>/dev/null
g "$PC" config remote.origin.uploadpack "$UP"
PC2="$T/pc2"; git clone -q --filter=blob:none --no-local "file://$OR" "$PC2" 2>/dev/null   # N2 전용 — N1 이 (기준판에서) R1 을 끌어와도 오염 0
g "$PC2" config remote.origin.uploadpack "$UP"
g "$MK" commit -q --allow-empty -m c2; g "$MK" push -q origin HEAD:refs/heads/main; R1="$(g "$MK" rev-parse HEAD)"
PK="$T/pack"; git clone -q "file://$OR" "$PK" 2>/dev/null   # 팩 리포 꼴(전체 클론 · R1 있음)
nofetch() { GIT_NO_LAZY_FETCH=1 git -C "$PC" rev-parse --verify -q "${1}^{commit}" >/dev/null 2>&1; }

# ── N1 partial clone 에 없는 sha → rc1 · 원격 호출 0 · 1초 안 · (조회 뒤에도 로컬에 없다)
: > "$UPL"; t0="$(now)"; out="$(_ft_landed_git "$PC" "$R1")"; rc=$?; el="$(ms_of "$t0")"; n="$(upn)"
if [ "$rc" = 1 ] && [ -z "$out" ] && [ "$n" = 0 ] && [ "$el" -le 1000 ] && ! nofetch "$R1"; then ck "N1 없는 sha → rc1 · 원격 호출 ${n} · ${el}ms ≤ 1000 · 로컬에 여전히 없음" 0
else ck "N1 없는 sha → rc1 · 원격 호출 ${n} · ${el}ms" 1; fi

# ── N3 로컬에 있는 sha → rc0 (지금과 같은 뜻) · 원격 호출 0
: > "$UPL"; t0="$(now)"; out="$(_ft_landed_git "$PC" "$C1")"; rc=$?; el="$(ms_of "$t0")"; n="$(upn)"
{ [ "$rc" = 0 ] && [ "$out" = "$C1" ] && [ "$n" = 0 ] && [ "$el" -le 1000 ]; } && ck "N3 로컬에 있는 sha → rc0 지정 그대로 · 원격 호출 0 · ${el}ms" 0 || ck "N3 로컬 sha → rc0" 1

# ── N2 ft_landed_repo: 카드 리포(partial clone · R1 없음)에 없고 팩 리포에 있음 → 팩 리포 rc0 · 카드 리포 조회가 원격을 부르지 않는다(1초 안)
: > "$UPL"; t0="$(now)"; out="$(ft_landed_repo "$R1" "$PC2" "$PK" "")"; rc=$?; el="$(ms_of "$t0")"; n="$(upn)"
TABX="$(printf '\t')"
if [ "$rc" = 0 ] && [ "${out%%$TABX*}" = "$PK" ] && [ "${out##*$TABX}" = "$R1" ] && [ "$n" = 0 ] && [ "$el" -le 1000 ]; then ck "N2 카드 리포 없음·팩 리포 있음 → 팩 리포 판정 · 원격 호출 ${n} · ${el}ms ≤ 1000" 0
else ck "N2 카드 리포 없음·팩 있음 → 팩 판정(원격 호출 ${n} · ${el}ms)" 1; fi

# ── N4 다른 ft_git_capped 호출(log --name-status)은 env 없이 그대로(non-lazy) · 정적 1줄
FG="$T/fakegit"; mkdir -p "$FG"
printf '#!/bin/bash\necho "env=${GIT_NO_LAZY_FETCH:-unset} ::$*" >> %s/gitcalls\nexec %s "$@"\n' "$T" "$(command -v git)" > "$FG/git"; chmod 755 "$FG/git"
: > "$T/gitcalls"
out="$(export PATH="$FG:$PATH"; ft_git_capped 7 "$PK" log --name-status -1 2>&1)"; rc=$?
lc="$(grep -c '^env=unset ::.* log ' "$T/gitcalls" 2>/dev/null | tr -d ' ')"
: > "$T/gitcalls"
out2="$(export PATH="$FG:$PATH"; _ft_landed_git "$PK" "$C1" 2>&1)"; rc2=$?
ls1="$(grep -c '^env=1 ::' "$T/gitcalls" 2>/dev/null | tr -d ' ')"
out="$out2"; rc=$rc2
{ [ "$lc" = 1 ] && [ "$ls1" -ge 1 ]; } && ck "N4 다른 ft_git_capped 호출(log)은 env 없이 1회(${lc}) · 착지 조회만 env=1(${ls1})" 0 || ck "N4 env 범위 :: log=${lc} landed=${ls1}" 1
out="$(grep -n 'GIT_NO_LAZY_FETCH' "$BIN/ft-team-lib.sh" | grep -v '^[0-9]*:[[:space:]]*#' | wc -l | tr -d ' ')"
cnt="$(grep -n 'GIT_NO_LAZY_FETCH' "$BIN/ft-team-lib.sh" | grep -v '^[0-9]*:[[:space:]]*#' | grep -cE '^[0-9]+:_ft_landed_git\(\) *\{ *GIT_NO_LAZY_FETCH=1 ' | tr -d ' ')"
{ [ "$cnt" = 1 ] && [ "$out" = 1 ]; } && ck "N4 정적: ft-team-lib.sh 에서 env 를 쓰는 «코드» 줄 1(_ft_landed_git 정의)" 0 || ck "N4 정적 줄 수 :: code=${out} def=${cnt}" 1

# ── ⓜ 오염 0 — 대역 partial clone 은 여전히 R1 없음 · 원격 호출 기록은 N1·N2 에서 0
if ! nofetch "$R1" && [ "$(upn)" = 0 ]; then ck "ⓜ 대역 오염 0(클론에 R1 유입 0 · 원격 upload-pack 호출 0)" 0; else ck "ⓜ 대역 오염 0 :: up=$(upn)" 1; fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
