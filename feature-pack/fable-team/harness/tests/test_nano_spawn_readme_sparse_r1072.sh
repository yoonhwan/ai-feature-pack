#!/usr/bin/env bash
# test_nano_spawn_readme_sparse_r1072.sh — r1072: sparse 워크트리(v65 폴더 없음)에서도 ft-nano-spawn.sh 가
#   SEATBELT-README 경로를 «좌석 열기 전» 에 풀고, 디스크에 없으면 ref(origin/main) 판 사본을 상태 폴더에 꺼내 그 경로를 쓴다.
#   ⓐ R1 sparse + ref 에 README 있음 → 경로 = <루트>/.fable-team/state/seatbelt-readme/<ref sha 12>-SEATBELT-README.md
#      · 사본 바이트 = ref 판 바이트 · _SBR_REF = ref 이름(발주문 «(ref … 판 사본)» 표기 근거)
#   ⓑ R2 일반 워크트리(README 디스크 실재) → 지금 동작(디스크 경로 · _SBR_REF 빈 값)
#   ⓒ R3 sparse + ref 에도 README 없음 → rc1 · 사본 0 · 상태 폴더 비어 있음 · 부르는 줄이 REJECT 1줄(좌석·명부·카드 손 0)
#   ⓓ R4 FT_SEATBELT_README 지정 → 지금 동작(그대로)
#   ⓔ R5 같은 ref sha 로 두 번 → 사본 1개 재사용
#   ⓕ 순서 — 해석 줄이 워크트리·tmux open·명부 등록·카드 이동 «줄보다 앞» (R3 의 «명부 행 0 · 세션 0 · 카드 이동 0» 근거)
#   변이 2: ⓧ ref 후퇴(doc_ref) 줄 삭제 → ⓐ FAIL · ⓨ 해석 줄을 명부 등록 뒤로 되돌림 → ⓕ FAIL
# 전부 mktemp — 임시 git 리포만. 실 좌석·실 워크트리·실 tmux·실 우편함 0. 실행은 함수 추출 + 줄 번호만(전체 spawn 실행은 70초 초과).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPAWN="${FT_R1072_SPAWN:-$HERE/../bin/ft-nano-spawn.sh}"   # 변이 시험은 사본 경로를 넘긴다
KIT="$HERE/../kit/fable-team/bin/ft-nano-spawn.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 사본 2개(추적본·키트) 정합 ──
bash -n "$SPAWN" && ok "bash -n 시험 대상" || bad "bash -n 시험 대상"
if [ -z "${FT_R1072_SPAWN:-}" ]; then
  bash -n "$KIT" && ok "bash -n 키트" || bad "bash -n 키트"
  cmp -s "$HERE/../bin/ft-nano-spawn.sh" "$KIT" && ok "두 사본 cmp 동일" || bad "두 사본 cmp 불일치"
fi

# ── 함수 추출(seatbelt_readme_path) + 팀 경로 라이브러리 ──
FN="$(awk '/^seatbelt_readme_path\(\) \{/,/^\}/' "$SPAWN")"
[ -n "$FN" ] && ok "seatbelt_readme_path 함수 추출" || { bad "seatbelt_readme_path 함수 없음"; echo "FAILED 1"; exit 1; }
. "$HERE/../bin/ft-team-lib.sh"
eval "$FN"

# ── 임시 리포: c1 = README 있음(origin/withreadme) · c2 = README 지움(origin/main · 디스크엔 되살림) ──
R="$T/R"; mkdir -p "$R/design/v65"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
BODY_REF='# SEATBELT — r1072 시험용 ref 판
둘째 줄: 이 바이트가 사본과 같아야 한다.
'
printf '%s' "$BODY_REF" > "$R/design/v65/SEATBELT-README.md"
git init -q -b main "$R" && G "$R" add -A && G "$R" commit -qm c1
G "$R" update-ref refs/remotes/origin/withreadme HEAD
SHA12="$(G "$R" rev-parse origin/withreadme | cut -c1-12)"
G "$R" rm -q design/v65/SEATBELT-README.md && G "$R" commit -qm c2
G "$R" update-ref refs/remotes/origin/main HEAD
G "$R" checkout -q "$(G "$R" rev-parse origin/withreadme)" -- design/v65/SEATBELT-README.md   # 디스크엔 README 있음(일반 워크트리 흉내)
STATE="$R/.fable-team/state/seatbelt-readme"

# run_res [ENV=값 …] — 서브셸에서 해석 1회 · stdout = `rc=` `sbr=` `ref=` 세 줄(전역 두 값을 밖으로 꺼낸다)
run_res() {
  local -a envs=("$@") kv
  ( unset FT_SEATBELT_README FT_TEAMS_REF
    for kv in ${envs[@]+"${envs[@]}"}; do export "$kv"; done
    WT="$R"; ROOT="$R"
    seatbelt_readme_path; rc=$?
    printf 'rc=%s\nsbr=%s\nref=%s\n' "$rc" "${_SBR:-}" "${_SBR_REF:-}" )
}
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# ── ⓑ R2 일반 워크트리 = 디스크 경로(기본 ref) ──
o="$(run_res)"
[ "$(field "$o" rc)" = 0 ] && [ "$(field "$o" sbr)" = "$R/design/v65/SEATBELT-README.md" ] && [ -z "$(field "$o" ref)" ] \
  && ok "ⓑ R2 디스크 실재 → 디스크 경로(기본 ref) · 사본 0" || bad "ⓑ R2 rc=$(field "$o" rc) sbr=$(field "$o" sbr) ref=$(field "$o" ref)"

# ── ⓓ R4 FT_SEATBELT_README 지정 = 그대로 ──
o="$(run_res FT_SEATBELT_README=design/v65/SEATBELT-README.md)"
[ "$(field "$o" rc)" = 0 ] && [ "$(field "$o" sbr)" = "$R/design/v65/SEATBELT-README.md" ] && [ -z "$(field "$o" ref)" ] \
  && ok "ⓓ R4 FT_SEATBELT_README 지정 → 그대로(디스크 경로 · 사본 0)" || bad "ⓓ R4 rc=$(field "$o" rc) sbr=$(field "$o" sbr)"

# ── ⓐ R1 sparse(디스크에서 v65 폴더 지움) + ref 에 README 있음 → 상태 폴더 사본 ──
rm -rf "$R/design/v65"
o="$(run_res FT_TEAMS_REF=origin/withreadme)"
DEST="$STATE/$SHA12-SEATBELT-README.md"
[ "$(field "$o" rc)" = 0 ] && [ "$(field "$o" sbr)" = "$DEST" ] && [ "$(field "$o" ref)" = origin/withreadme ] \
  && ok "ⓐ R1 sparse + ref 판 → $SHA12 사본 경로 · _SBR_REF=origin/withreadme" || bad "ⓐ R1 rc=$(field "$o" rc) sbr=$(field "$o" sbr) ref=$(field "$o" ref)"
[ -f "$DEST" ] && ok "ⓐ 사본 파일 실재" || bad "ⓐ 사본 파일 없음: $DEST"
G "$R" show origin/withreadme:design/v65/SEATBELT-README.md > "$T/ref-body.md" 2>/dev/null
cmp -s "$T/ref-body.md" "$DEST" && ok "ⓐ 사본 바이트 = ref 판 바이트" || bad "ⓐ 사본 바이트가 ref 판과 다름"
[ "$(ls -1 "$STATE" | wc -l | tr -d ' ')" = 1 ] && ok "ⓐ 상태 폴더 파일 1개(tmp 잔여 0)" || bad "ⓐ 상태 폴더 파일 $(ls -1 "$STATE" | tr '\n' ' ')"

# ── ⓔ R5 같은 ref sha 로 두 번째 → 사본 재사용(1개) ──
o="$(run_res FT_TEAMS_REF=origin/withreadme)"
[ "$(field "$o" sbr)" = "$DEST" ] && [ "$(ls -1 "$STATE" | wc -l | tr -d ' ')" = 1 ] \
  && ok "ⓔ R5 같은 ref sha 두 번 → 사본 1개 재사용" || bad "ⓔ R5 파일 $(ls -1 "$STATE" | tr '\n' ' ')"

# ── ⓒ R3 sparse + ref 에도 README 없음 → rc1 · 사본 0 ──
rm -rf "$STATE"
o="$(run_res FT_TEAMS_REF=origin/main)"
[ "$(field "$o" rc)" = 1 ] && [ -z "$(field "$o" sbr)" ] && ok "ⓒ R3 ref 에도 없음 → rc1 · 경로 0" || bad "ⓒ R3 rc=$(field "$o" rc) sbr=$(field "$o" sbr)"
{ [ ! -d "$STATE" ] || [ "$(ls -1 "$STATE" | wc -l | tr -d ' ')" = 0 ]; } && ok "ⓒ R3 사본 0(상태 폴더 비었음)" || bad "ⓒ R3 사본이 생김: $(ls -1 "$STATE" 2>/dev/null | tr '\n' ' ')"
grep -qF 'REJECT SEATBELT-README 경로를 못 풀었다' "$SPAWN" && ok "ⓒ R3 부르는 줄이 REJECT 1줄" || bad "ⓒ R3 REJECT 줄 없음"

# ── ⓕ 순서 — 해석 줄이 워크트리/좌석/명부/카드 이동 «앞» ──
ln_of()  { grep -n "$1" "$SPAWN" | head -1 | cut -d: -f1; }
ln_fix() { grep -nF "$1" "$SPAWN" | head -1 | cut -d: -f1; }
L_RES="$(ln_of '^seatbelt_readme_path || {')"; L_FN="$(ln_of '^seatbelt_readme_path() {')"
L_WT="$(ln_of '^# ② 워크트리')"; L_OPEN="$(ln_fix '"${OPEN[@]}" >/dev/null 2>&1')"
L_DRY="$(ln_fix 'if [ "$DRY" = 1 ]; then [ "$RESEARCH" != 1 ]')"   # --dry-run 은 좌석을 열지 않는다 — 그 종료 줄 «뒤» 가 해석 자리(기존 동작 보존)
L_SEATS="$(ln_of '^python3 - "\$SEATS" "\$NAME" "\$AGENT"')"; L_MOVE="$(ln_of 'ft-index-move.sh" "\$IDX" 진행')"
[ -n "$L_RES" ] && [ -n "$L_FN" ] && [ -n "$L_WT" ] && [ -n "$L_OPEN" ] && [ -n "$L_SEATS" ] && [ -n "$L_MOVE" ] && [ -n "$L_DRY" ] \
  && ok "ⓕ 기준 줄 추출(res=$L_RES fn=$L_FN dry=$L_DRY wt=$L_WT open=$L_OPEN seats=$L_SEATS move=$L_MOVE)" || bad "ⓕ 줄 추출 실패 res=$L_RES fn=$L_FN dry=$L_DRY wt=$L_WT open=$L_OPEN seats=$L_SEATS move=$L_MOVE"
{ [ "$L_FN" -lt "$L_RES" ] && [ "$L_DRY" -lt "$L_RES" ] && [ "$L_RES" -lt "$L_WT" ] && [ "$L_RES" -lt "$L_OPEN" ] && [ "$L_RES" -lt "$L_SEATS" ] && [ "$L_RES" -lt "$L_MOVE" ]; } \
  && ok "ⓕ 해석 줄이 워크트리($L_WT)·tmux open($L_OPEN)·명부 등록($L_SEATS)·카드 이동($L_MOVE)보다 앞" \
  || bad "ⓕ 해석 줄이 뒤 — R3 에서 명부 행·세션·카드 이동이 남는다(res=$L_RES wt=$L_WT open=$L_OPEN seats=$L_SEATS move=$L_MOVE)"
BODY_LINE="$(grep '^BODY=' "$SPAWN")"
case "$BODY_LINE" in *'${_SBR_REF:+ (ref $_SBR_REF 판 사본)}'*) ok "ⓕ 발주문이 사본 표기 «(ref … 판 사본)» 를 붙인다";; *) bad "ⓕ 발주문에 사본 표기 없음";; esac
[ "$(grep -c 'ft_team_file_ref "\$WT" v65 SEATBELT-README.md' "$SPAWN")" = 1 ] && ok "ⓕ SEATBELT 경로 해석은 한 곳(두 벌 0)" || bad "ⓕ 해석이 두 곳 이상"

# ── 변이 — 사본 spawn 으로 이 시험을 다시 돌려 FAIL 을 확인(재귀 1단만) ──
if [ -z "${FT_R1072_SPAWN:-}" ]; then
  mut() { python3 - "$HERE/../bin/ft-nano-spawn.sh" "$T/mut-$1.sh" "$1" <<'PY'
import sys
src, dst, kind = sys.argv[1:4]
lines = open(src, encoding="utf-8").read().split("\n")
if kind == "noref":        # ref 후퇴(doc_ref) 줄 삭제 → ⓐ R1 rc≠0 → FAIL
    out = [l for l in lines if 'doc="$(ft_team_doc_ref' not in l]; n = 1 if len(out) == len(lines) - 1 else 0
elif kind == "late":       # 해석 줄을 «명부 등록 뒤» 로 되돌림 → ⓕ 순서 FAIL(명부 행이 남는다)
    i = next((k for k, l in enumerate(lines) if l.startswith("seatbelt_readme_path || {")), None)
    j = next((k for k, l in enumerate(lines) if l.startswith("# ⑥ 대기→진행")), None)
    if i is None or j is None or j < i: sys.exit("MUT NOT APPLIED: late")
    moved = lines.pop(i); lines.insert(j - 1, moved); out = lines; n = 1
else: sys.exit("unknown mut")
if n != 1: sys.exit("MUT NOT APPLIED: " + kind)
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY
    [ "$?" = 0 ] || { echo "MUTFAIL $1"; return 0; }
    FT_R1072_SPAWN="$T/mut-$1.sh" bash "$0" 2>&1 | grep -c '^FAIL' || true; }
  [ "$(mut noref)" -ge 1 ] && ok "변이: ref 후퇴 줄 삭제 → FAIL" || bad "변이: ref 후퇴를 없애도 통과"
  [ "$(mut late)" -ge 1 ] && ok "변이: 해석을 명부 등록 뒤로 되돌림 → FAIL" || bad "변이: 해석을 뒤로 옮겨도 통과"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
