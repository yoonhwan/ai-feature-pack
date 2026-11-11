#!/usr/bin/env bash
# test_nano_spawn_readme_team_r1686.sh — r1686: ft-nano-spawn.sh 의 SEATBELT-README 해석이 «카드 팀 README 먼저 → 없을 때만 v65» 를 따른다.
#   aifp 꼴(v65 폴더 없음 · 팀 README 있음)이 통과하고, 고른 팀을 «README 출처 = <팀> <경로>» 1줄로 남긴다. 명시 FT_SEATBELT_README 는 그대로 이긴다.
# 임시 리포만 · spawn 전체 실행 0(tmux·명부·워크트리·실 상태 0) · 함수만 떼어 부른다 · 사례 70초 · 자기를 다시 부르지 않는다(재진입 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; RL="$HERE/../.."
SPAWN="$RL/harness/bin/ft-nano-spawn.sh"; KIT="$RL/harness/kit/fable-team/bin/ft-nano-spawn.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$SPAWN" && ok "bash -n 대조 대상" || bad "bash -n 실패"
cmp -s "$SPAWN" "$KIT" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
FN="$(awk '/^seatbelt_readme_path\(\) \{/,/^\}/' "$SPAWN")"
[ -n "$FN" ] && ok "seatbelt_readme_path 추출" || { bad "함수 없음"; echo "FAILED 1"; exit 1; }
. "$RL/harness/bin/ft-team-lib.sh"
G(){ git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
mk(){  # mk <이름> <팀> <팀README 0|1> <v65README 0|1> → 리포 경로
  local d="$T/$1" tm="$2"
  mkdir -p "$d/design/$tm"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$tm" "$tm" > "$d/design/TEAMS.md"
  [ "$3" = 0 ] || { printf '# %s SEATBELT-README\n' "$tm" > "$d/design/$tm/SEATBELT-README.md"; }
  [ "$4" = 0 ] || { mkdir -p "$d/design/v65"; printf '# v65 SEATBELT-README\n' > "$d/design/v65/SEATBELT-README.md"; }
  git init -q -b main "$d"; G "$d" add -A; G "$d" commit -qm init; G "$d" update-ref refs/remotes/origin/main HEAD
  printf '%s\n' "$d"; }
runsp(){  # runsp <spawn 파일> <리포> <카드팀|-> [ENV=값 …] → rc= sbr= team= ref= (서브셸 · 함수만 eval)
  local f="$1" d="$2" tm="$3"; shift 3
  ( unset FT_SEATBELT_README FT_TEAMS_REF FT_TEAM IDX; WT="$d"; ROOT="$d"
    [ "$tm" = - ] || IDX="$d/design/$tm/indices/대기/x.md"
    local kv; for kv in ${@+"$@"}; do export "$kv"; done
    eval "$(awk '/^seatbelt_readme_path\(\) \{/,/^\}/' "$f")"; seatbelt_readme_path; rc=$?
    printf 'rc=%s\nsbr=%s\nteam=%s\nref=%s\n' "$rc" "${_SBR:-}" "${_SBR_TEAM:-}" "${_SBR_REF:-}" ); }
f(){ printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# ── 사례 ⓐ~ⓔ ──
A="$(mk a aifp 1 0)"; o="$(runsp "$SPAWN" "$A" aifp)"     # aifp 꼴: v65 폴더 없음 · 팀 README 만
{ [ "$(f "$o" rc)" = 0 ] && [ "$(f "$o" sbr)" = "$A/design/aifp/SEATBELT-README.md" ] && [ "$(f "$o" team)" = aifp ]; } \
  && ok "ⓐ aifp 꼴(v65 없음) → 팀 README 경로 · 출처 팀 = aifp" || bad "ⓐ rc=$(f "$o" rc) sbr=$(f "$o" sbr) team=$(f "$o" team)"
B="$(mk b aifp 0 1)"; o="$(runsp "$SPAWN" "$B" aifp)"      # 팀 README 없음 → v65(지금 값)
{ [ "$(f "$o" rc)" = 0 ] && [ "$(f "$o" sbr)" = "$B/design/v65/SEATBELT-README.md" ] && [ "$(f "$o" team)" = v65 ]; } \
  && ok "ⓑ 팀 README 없음 → v65 README(지금과 같다)" || bad "ⓑ rc=$(f "$o" rc) sbr=$(f "$o" sbr) team=$(f "$o" team)"
C="$(mk c aifp 1 1)"; o="$(runsp "$SPAWN" "$C" aifp)"      # 둘 다 있음 → 팀 우선
{ [ "$(f "$o" sbr)" = "$C/design/aifp/SEATBELT-README.md" ] && [ "$(f "$o" team)" = aifp ]; } \
  && ok "ⓒ 둘 다 있음 → 팀 README" || bad "ⓒ sbr=$(f "$o" sbr) team=$(f "$o" team)"
o="$(runsp "$SPAWN" "$C" aifp FT_SEATBELT_README=design/v65/SEATBELT-README.md)"   # 명시값 우선
{ [ "$(f "$o" sbr)" = "$C/design/v65/SEATBELT-README.md" ] && [[ "$(f "$o" team)" == "(명시"* ]]; } \
  && ok "ⓓ FT_SEATBELT_README 명시 → 그 값(지금과 같다)" || bad "ⓓ sbr=$(f "$o" sbr) team=$(f "$o" team)"
E="$(mk e aifp 0 0)"; o="$(runsp "$SPAWN" "$E" aifp)"      # 둘 다 없음 → rc1 · 쓰기 0
{ [ "$(f "$o" rc)" = 1 ] && [ ! -d "$E/.fable-team/state/seatbelt-readme" ]; } \
  && ok "ⓔ 둘 다 없음 → rc1(부르는 쪽 REJECT) · 사본 0" || bad "ⓔ rc=$(f "$o" rc) 사본폴더=$(ls "$E/.fable-team/state" 2>/dev/null | tr '\n' ' ')"
[ "$(grep -c '^echo "README 출처 = ' "$SPAWN")" = 1 ] && ok "ⓐ 출처 줄 «README 출처 = …» 1개" || bad "ⓐ 출처 줄 0 또는 2+"
grep -q 'REJECT SEATBELT-README 경로를 못 풀었다' "$SPAWN" && ok "ⓔ REJECT 문구 그대로" || bad "ⓔ REJECT 문구 없음"

# ── 사례 ⓕ 회귀: README 사례 파일(r1072) FAIL 줄 0 — 앞 판(수정 전)과 같다 ──
n="$(bash "$HERE/test_nano_spawn_readme_sparse_r1072.sh" 2>&1 | grep -c '^FAIL')"
[ "$n" = 0 ] && ok "ⓕ 회귀 test_nano_spawn_readme_sparse_r1072.sh FAIL 0(앞 판과 같다)" || bad "ⓕ 회귀 FAIL $n 줄"

# ── 변이 2종(사본에서만) ──
mut(){ python3 - "$SPAWN" "$T/$1.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
patch1(){ python3 - "$T/$1.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mut m1 '[ "$t" != v65 ]' '[ 1 = 2 ]'          # M1: 디스크 팀 갈래를 v65 로 되돌림
patch1 m1 'for t in "$t" v65; do' 'for t in v65; do'   # M1: ref 판도 v65 로 되돌림
bash -n "$T/m1.sh" && ok "M1 bash -n rc0" || bad "M1 bash -n"
o="$(runsp "$T/m1.sh" "$A" aifp)"; o2="$(runsp "$T/m1.sh" "$C" aifp)"
{ [ "$(f "$o" rc)" = 1 ] && [ "$(f "$o2" sbr)" = "$C/design/v65/SEATBELT-README.md" ]; } \
  && ok "M1 팀 갈래 제거 → ⓐ·ⓒ FAIL(검출됨)" || bad "M1 검출 실패 rc=$(f "$o" rc) sbr=$(f "$o2" sbr)"
mut m2 'if doc="$(ft_team_file_ref "$WT" v65 SEATBELT-README.md)"; then _SBR="$doc"; _SBR_TEAM=v65; return 0; fi' ':'   # M2: v65 기본 갈래 삭제
bash -n "$T/m2.sh" && ok "M2 bash -n rc0" || bad "M2 bash -n"
o="$(runsp "$T/m2.sh" "$B" aifp)"
[ "$(f "$o" sbr)" != "$B/design/v65/SEATBELT-README.md" ] && ok "M2 v65 기본 갈래 삭제 → ⓑ FAIL(검출됨)" || bad "M2 검출 실패 sbr=$(f "$o" sbr)"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
