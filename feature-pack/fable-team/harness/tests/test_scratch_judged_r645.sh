#!/usr/bin/env bash
# test_scratch_judged_r645.sh — ft-scratch-repo.sh 의 «판정 끝남» 검사가 전 히스토리 pickaxe 를 돌지 않는지(r645).
#   ⓐ 정적: 파일에 <log … pickaxe> 꼴 0건  ⓑ 판정문에 sha8 있고 그 커밋이 AGE 지남 → rc0  ⓒ 없음 → rc1
#   ⓓ 사본 HEAD 가 main 조상 → rc0(검색 안 돎)  ⓔ 느린 grep → 7초 안에 rc1 + WARN 1줄  ⓕ grep rc≥2 → rc1 + WARN
#   ⓖ warn_many: 등록 사본 5개 + 느린 grep → 예산(기본 20초) 안에서 끝나고 «예산 초과» WARN 1줄
# 임시 git 저장소·임시 TMPDIR·가짜 git 래퍼만 쓴다 — 실 저장소·실 좌석·실 TMPDIR 0.
# SCR_SUT=<경로> 로 시험 대상을 바꿀 수 있다(고치기 전 판 = before-red 증거용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${SCR_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
REALGIT="$(command -v git)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/root"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G/.fable-team/state" "$SCR" "$TMPD" "$T/bin"
TSV="$G/.fable-team/state/scratch-repos.tsv"
git init -q -b main "$G"; mkdir -p "$G/design"; echo base > "$G/design/BASE.md"
git -C "$G" add -A && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m base
C1="$(git -C "$G" rev-list --max-parents=0 main)"
OWN=live-owner
sc() { OUT="$(env PATH="${PBIN:-$T/bin}:$PATH" FT_RES_ROOT="$G" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" \
  FT_SCRATCH_MAIN=main FT_SCRATCH_AGE_MIN=1 bash "$SUT" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
reg() { printf '%s\t%s\t%s\n' "$1" "${OWN:-live-owner}" "$(date +%s)" >> "$TSV"; }
mk_copy() { # <폴더> → 그 사본 HEAD 앞 8자
  git init -q "$1"; printf "x\n%s\n" "$1" > "$1/f.txt"; git -C "$1" add -A   # 경로를 내용에 넣어 사본마다 sha 가 다르게
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m c1; git -C "$1" rev-parse HEAD | cut -c1-8
}

# ⓐ 정적: 코드에 <git … log … pickaxe> 꼴이 남아 있으면 FAIL
if [ -z "$(grep -nE 'git[^|]*log[^|]*-S' "$SUT")" ]; then ok "ⓐ 전 히스토리 pickaxe 호출 0건"; else bad "ⓐ pickaxe 잔존: $(grep -nE 'git[^|]*log[^|]*-S' "$SUT")"; fi

P="$SCR/copy-a"; H8="$(mk_copy "$P")"; reg "$P"
printf '판정문\n세트: %s\n' "$H8" > "$G/design/VERDICT-r645.md"
git -C "$G" add -A
OLD="$(( $(date +%s) - 3600 ))"
GIT_AUTHOR_DATE="@$OLD" GIT_COMMITTER_DATE="@$OLD" git -C "$G" -c user.name=t -c user.email=t@t commit -q -m "verdict $H8"
sc --judged "$P"; { [ $RC = 0 ]; } && ok "ⓑ 판정문에 sha8 + 1시간 전 커밋(AGE 1분) → rc0" || bad "ⓑ rc=$RC [$ERR]"

P2="$SCR/copy-b"; mk_copy "$P2" >/dev/null; reg "$P2"
sc --judged "$P2"; { [ $RC = 1 ] && [ -z "$ERR" ] && [ -z "$OUT" ]; } && ok "ⓒ 판정문에 없는 sha → rc1 · WARN 0(정상 «안 끝남»)" || bad "ⓒ rc=$RC [$OUT][$ERR]"

git -C "$G" worktree add -q --detach "$SCR/wt-anc" "$C1"; OWN=other-owner reg "$SCR/wt-anc"
sc --judged "$SCR/wt-anc"; { [ $RC = 0 ]; } && ok "ⓓ 사본 HEAD 가 main 조상 → rc0(검색 경로 안 돎 · 판정문 없음)" || bad "ⓓ rc=$RC $ERR"

mkdir -p "$T/slowbin" "$T/failbin"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = grep ] && sleep 10; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/slowbin/git"
printf '#!/bin/sh\ncase "$*" in *grep*) sleep 0.2; exit 2;; esac\nexec "%s" "$@"\n' "$REALGIT" > "$T/failbin/git"
chmod 755 "$T/slowbin/git" "$T/failbin/git"
T0="$(date +%s)"; PBIN="$T/slowbin" sc --judged "$P"; EL=$(( $(date +%s) - T0 ))
{ [ $RC = 1 ] && [ "$EL" -lt 9 ] && echo "$ERR" | grep -q 'WARN ft-scratch-repo judged — 시간 초과(7s) · 판정 안 끝남'; } \
  && ok "ⓔ 느린 grep(sleep 10) → ${EL}s 안에 rc1 + 시간 초과 WARN 1줄" || bad "ⓔ rc=$RC ${EL}s [$OUT][$ERR]"
[ "$(echo "$ERR" | grep -c 'WARN ft-scratch-repo judged')" = 1 ] \
  && ok "ⓔ WARN 은 정확히 1줄" || bad "ⓔ WARN 줄 수 [$ERR]"
PBIN="$T/failbin" sc --judged "$P"; { [ $RC = 1 ] && echo "$ERR" | grep -q 'git grep 실패(rc=2) · 판정 안 끝남'; } \
  && ok "ⓕ grep rc=2 → rc1 + «git grep 실패» WARN(조용한 rc0 0)" || bad "ⓕ rc=$RC [$OUT][$ERR]"

D3="$SCR/copy-d"; mk_copy "$D3" >/dev/null; reg "$D3"
D4="$SCR/copy-e"; mk_copy "$D4" >/dev/null; reg "$D4"
T0="$(date +%s)"; PBIN="$T/slowbin" sc "$(git -C "$G" rev-parse main)" --repo "$G"; EL=$(( $(date +%s) - T0 ))
{ [ $RC = 0 ] && [ -d "$OUT" ] && [ "$EL" -le 24 ]; } \
  && ok "ⓖ 느린 grep 이어도 사본 생성 rc0 · 전체 ${EL}s ≤ 예산 20초(+worktree add)" || bad "ⓖ rc=$RC ${EL}s [$OUT][$ERR]"
echo "$ERR" | grep -q '판정 예산(20초) 초과 · 남은 사본은 판정 안 함' \
  && ok "ⓖ 남은 사본 «판정 안 함» WARN 1줄" || bad "ⓖ 예산 WARN 없음 [$ERR]"
[ "$(echo "$ERR" | grep -c '판정 예산')" = 1 ] && ok "ⓖ 예산 WARN 은 1줄" || bad "ⓖ 예산 WARN 줄 수 [$ERR]"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
