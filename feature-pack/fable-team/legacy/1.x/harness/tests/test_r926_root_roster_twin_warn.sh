#!/usr/bin/env bash
# test_r926_root_roster_twin_warn.sh — r926 r2: 자율 인터뷰 쪽지의 «명부 자리» = $ROOT 기준만 · 쌍둥이 경고가 «틀린 이동»을 시키지 않는가
#   ⓐ' FT_ROOT=A(명부 desk-A) · cwd=B(명부 desk-B) → desk-A (cwd 명부 0)
#   ⓐ'' FT_ROOT=A 작업 폴더(명부 없음) · A 의 리포 공용 루트에 명부 → 그 명부(desk-R)
#   ⓐ''' cwd 리포에 명부가 있어도 안 본다(FT_ROOT 없음 · 데이터 루트에 명부 없음) → WARN + rc1
#   ⓑ 명부가 어디에도 없음 → WARN «못 찾음(찾은 자리 2곳)» + rc1 · 역호환: 명부가 $ROOT 에만 있으면 그 명부
#   ⓒ 쌍둥이 + 루트 가지가 origin/main 을 품음 → 지금 문구(--apply 안내)   ⓓ 쌍둥이 + 안 품음 → «이동 0 · 원장은 ref 정본»
#   ⓔ 가지를 못 물어봄(origin/main 없음) → 지금 문구 + «가지 확인 못 함»   ⓓ' timeout 도구 없음 + git 대역 8초 → 1초 안 unknown · rev-list 호출 0
#   쌍둥이 시험은 stdout / stderr 를 따로 받아 «stdout = 경로 1줄» 을 단언한다(DA⑥ r1)
# 격리: 임시 리포·임시 명부(mktemp) + 대역 mbox · 대역 git · 실 상태·실 슬랙·실 mbox·외부 호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"; BASH="${BASH:-/bin/bash}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
hasnt() { ! grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d /tmp/r926.XXXXXX)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -c user.name=t -c user.email=t@t -C "$1" "${@:2}"; }
mkdir -p "$T/bin"

for f in ft-autonomy.sh ft-autonomy-level.sh ft-team-lib.sh; do "$BASH" -n "$BIN/$f"; ck "bash -n(3.2) $f" $?; done
printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s/mbox.log"\n' "$T" > "$T/bin/mbox.sh"

# ── ⓐ'ⓐ''ⓐ'''ⓑ 자율 인터뷰 쪽지의 명부 자리($ROOT 기준만) ────────────────────
mk_roster() { mkdir -p "$1/.fable-team"; printf '{"_desk":"%s"}\n' "$2" > "$1/.fable-team/seats-planner.json"; }
mkrepo() { rm -rf "$1"; mkdir -p "$1"; g "$1" init -q -b main; printf 'x\n' > "$1/keep"; g "$1" add -A; g "$1" commit -qm base; }
inv() {  # <FT_ROOT|""> <cwd> → stdout+stderr · rc · $T/mbox.log
  rm -rf "$T/state"; mkdir -p "$T/state"; rm -f "$T/mbox.log"
  ( cd "$2" || return 1
    if [ -n "$1" ]; then export FT_ROOT="$1"; else unset FT_ROOT; fi
    export FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_MBOX="$T/bin/mbox.sh" FT_AUTONOMY_GOAL_TABLE=0
    unset FT_AUTONOMY_DESK
    exec "$BASH" "$BIN/ft-autonomy.sh" interview-note A1 expire 2>&1 )
}
mkrepo "$T/b"; mk_roster "$T/b" desk-B          # cwd 리포(엉뚱한 명부)
mkdir -p "$T/a"; mk_roster "$T/a" desk-A        # FT_ROOT(제 명부 · git 밖)
out="$(inv "$T/a" "$T/b")"; rc=$?
[ $rc = 0 ] && has '^INTERVIEW-SENT A1 expire' && hasnt 'INTERVIEW-SKIP' && grep -q '^desk-A|' "$T/mbox.log" && ! grep -q '^desk-B|' "$T/mbox.log"; ck "ⓐ' FT_ROOT=A · cwd=B → A 명부(desk-A)로 보낸다(cwd 명부 0)" $?
mkrepo "$T/r2"; mkdir -p "$T/r2/work"; mk_roster "$T/r2" desk-R   # FT_ROOT = 리포 안 작업 폴더(명부 없음) → 공용 루트 명부
out="$(inv "$T/r2/work" "$T/b")"; rc=$?
[ $rc = 0 ] && has '^INTERVIEW-SENT' && grep -q '^desk-R|' "$T/mbox.log" && ! grep -q '^desk-B|' "$T/mbox.log"; ck "ⓐ'' FT_ROOT=A 작업 폴더(명부 없음) → A 의 리포 공용 루트 명부" $?
mkrepo "$T/r"; mkdir -p "$T/d/.fable-team" "$T/r/.fable-team"; printf '%s\n' "$T/d" > "$T/r/.fable-team/LIVE_ROOT"   # FT_ROOT 없음 → 데이터 루트 = d(명부 없음) · cwd = r(명부 desk-B 없음 → b 만)
out="$(inv "" "$T/r")"; rc=$?
[ $rc = 1 ] && has 'WARN 자율 인터뷰 쪽지 못 보냄: planner 명부 못 찾음\(찾은 자리 2곳' && [ ! -s "$T/mbox.log" ]; ck "ⓐ''' cwd 명부는 안 본다(FT_ROOT 없음 · 데이터 루트 명부 0) → WARN rc1" $?
mkdir -p "$T/a3"
out="$(inv "$T/a3" "$T")"; rc=$?
[ $rc = 1 ] && has 'WARN 자율 인터뷰 쪽지 못 보냄: planner 명부 못 찾음\(찾은 자리 2곳: .*seats-planner\.json · <공용 루트 못 풂>/\.fable-team/seats-planner\.json\)' && hasnt 'INTERVIEW-SKIP'; ck "ⓑ 명부가 어디에도 없음 → WARN + rc1(조용한 건너뜀 0)" $?
mk_roster "$T/a3" desk-root
out="$(inv "$T/a3" "$T/b")"; rc=$?
[ $rc = 0 ] && has '^INTERVIEW-SENT' && grep -q '^desk-root|' "$T/mbox.log"; ck "ⓑ 명부가 \$ROOT 에만 있으면 옛 꼴 그대로(역호환)" $?

# ── ⓒⓓⓔⓓ' 쌍둥이 경고 문구 ─────────────────────────────────────────────────
# 옛 꼴(design/planner/) 파일 잔존 + 명단 새 꼴(design/teams/planner/) · 루트 가지 상황 3종
mk_twin() {  # <가지: contains|behind|noref>
  rm -rf "$T/w" "$T/src"; mkdir -p "$T/w/design/planner" "$T/w/design/teams/planner"
  printf '| 팀 | 폴더 |\n|---|---|\n| planner | `design/teams/planner/` | x |\n' > "$T/w/design/TEAMS.md"
  printf 'old\n' > "$T/w/design/planner/VERDICTS-1.md"; printf 'new\n' > "$T/w/design/teams/planner/README.md"
  g "$T/w" init -q -b main; g "$T/w" add -A; g "$T/w" commit -qm c1
  [ "$1" = noref ] && return 0   # origin/main 자체가 없는 리포(옛 체크아웃 꼴)
  if [ "$1" = contains ]; then g "$T/w" update-ref refs/remotes/origin/main HEAD; printf 'n\n' > "$T/w/n"  # main 을 품은 가지 = origin/main 이 HEAD 의 조상
    g "$T/w" add -A; g "$T/w" commit -qm c2
  else printf 'n\n' > "$T/w/n"; g "$T/w" add -A; g "$T/w" commit -qm c2; g "$T/w" update-ref refs/remotes/origin/main HEAD; g "$T/w" reset -q --hard HEAD~1; fi; }
tw() {  # stdout=경로 1줄 · stderr=WARN · out = 둘 다(문구 검사용)
  : > "$T/o"; : > "$T/e"
  ( cd "$T/w" && env -u FT_TEAMS_MD -u FT_TEAMS_REF FT_REPO_ROOT="$T/w" "$BASH" -c '. "$1"; ft_team_root planner' _ "$BIN/ft-team-lib.sh" >"$T/o" 2>"$T/e" ); rc=$?
  out="$(printf '%s\n' "$(cat "$T/o")"; printf '%s\n' "$(cat "$T/e")")"; }
path_only() { [ "$(cat "$T/o")" = "$T/w/design/teams/planner" ] && [ "$(wc -l < "$T/o" | tr -d ' ')" = 1 ]; }
mk_twin contains; tw
[ $rc = 0 ] && has 'WARN 옛 꼴 잔존 1파일 — ft-team-move.sh --apply planner' && hasnt '이동 0' && path_only; ck "ⓒ 가지가 main 을 품음 → 지금 문구 그대로(--apply) · stdout = 경로 1줄" $?
mk_twin behind; tw
[ $rc = 0 ] && has 'WARN 옛 꼴 잔존 1파일 — 데이터 루트 가지가 main 보다 1 뒤 · 이동 0 · 원장은 ref 정본' && hasnt '\-\-apply' && path_only; ck "ⓓ 가지가 main 을 안 품음 → «이동 0 · 원장은 ref 정본»(--apply 0) · stdout = 경로 1줄" $?
mk_twin noref; tw
[ $rc = 0 ] && has 'ft-team-move.sh --apply planner' && has '가지 확인 못 함' && path_only; ck "ⓔ origin/main 없음 → 지금 문구 + «가지 확인 못 함» · stdout = 경로 1줄" $?
printf 'x\n' > "$T/w/design/planner/b"; out="$( cd "$T/w" && env FT_REPO_ROOT="$T/w" "$BASH" -c '. "$1"; ft_team_root planner' _ "$BIN/ft-team-lib.sh" 2>&1 )"; rc=$?
[ $rc = 0 ] && has 'WARN 옛 꼴 잔존 2파일'; ck "ⓔ 파일 수는 그대로 센다(2파일)" $?
# ⓓ' timeout·gtimeout 이 PATH 에 없음 + git 대역(rev-list 만 8초 잠) → 1초 안 unknown · rev-list 호출 0
mk_twin behind; rm -rf "$T/pbin"; mkdir -p "$T/pbin"; rm -f "$T/git.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/git.log"\ncase "$*" in *rev-list*) sleep 8;; esac\nexit 0\n' "$T" > "$T/pbin/git"; chmod +x "$T/pbin/git"
t0="$(date +%s)"
( cd "$T/w" && PATH="$T/pbin:/usr/bin:/bin:/usr/sbin:/sbin" env -u FT_TEAMS_MD -u FT_TEAMS_REF FT_REPO_ROOT="$T/w" "$BASH" -c '. "$1"; ft_team_root planner' _ "$BIN/ft-team-lib.sh" >"$T/o" 2>"$T/e" ); rc=$?
t1="$(date +%s)"; out="$(printf '%s\n' "$(cat "$T/o")"; printf '%s\n' "$(cat "$T/e")")"
if [ $rc = 0 ] && has '가지 확인 못 함' && path_only && [ $(( t1 - t0 )) -le 1 ] && { [ ! -f "$T/git.log" ] || ! grep -q 'rev-list' "$T/git.log"; }; then
  ck "ⓓ' timeout 도구 없음 → 1초 안 «가지 확인 못 함» · rev-list 호출 0($(( t1 - t0 ))s)" 0
else ck "ⓓ' timeout 도구 없음 → 1초 안 «가지 확인 못 함» · rev-list 호출 0($(( t1 - t0 ))s)" 1; fi

# ── 짝 사본 cmp0 (설치 대조 = master) ────────────────────────────────────────
for f in ft-autonomy-level.sh ft-team-lib.sh; do cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 짝 cmp0 $f" $?; done
echo "── r926 fail=$fail"
[ "$fail" = 0 ]
