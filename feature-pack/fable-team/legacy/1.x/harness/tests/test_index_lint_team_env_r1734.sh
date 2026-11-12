#!/usr/bin/env bash
# test_index_lint_team_env_r1734.sh — ft-index-lint «직접 호출» 도 카드 팀 env 에서 골 줄을 읽는다(r1734 · r1166 규칙을 move 에서 lint 안으로).
#   반례 ①~⑦ + 변이 M1~M3(변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조). 임시 리포·임시 env 만 — 실 리포·실 명부 0 · 고정 sleep 0 · 재귀 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../kit/fable-team/bin/ft-index-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$LINT" && ok "bash -n kit ft-index-lint.sh" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
KDIR="$T/kit"; cp -a "$HERE/../kit/fable-team/bin" "$KDIR"   # 변이 사본은 이 폴더에 — 형제 도우미(ft-team-lib.sh 등)를 같은 dirname 에서 찾는다
MUTL="$KDIR/ft-index-lint-mut.sh"
export HOME="$T/home"; mkdir -p "$HOME"
unset FT_GOAL_LINES_FILE FT_TEAM FT_CARD_ADDED_MAP_FILE
H1='하네스 골 첫 줄 시험용 문장'; H2='하네스 골 둘째 줄 시험용 문장'; H3='하네스 골 셋째 줄 시험용 문장'
V1='목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.'
V2='LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.'
V3='단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.'
REPO="$T/repo"; ENV="$REPO/.fable-team/bin-harness/harness-env.sh"
mkdir -p "$REPO/design/harness/indices/진행" "$REPO/design/v65/indices/진행" "$REPO/.fable-team/bin-harness" "$REPO/src"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '%s\n%s\n%s\n' "$H1" "$H2" "$H3" > "$REPO/.fable-team/bin-harness/goal-lines-harness.txt"
printf '%s\n%s\n%s\n' "$V1" "$V2" "$V3" > "$T/goal-v65.txt"
printf '닫는 증거 정본 문장은 이 문장 전체를 복붙해야 한다.\n' > "$REPO/design/harness/GOAL-harness.md"
printf '닫는 증거 정본 문장은 이 문장 전체를 복붙해야 한다.\n' > "$REPO/design/v65/GOAL-LEDGER-v65.md"
printf 'l1\nl2\nl3\n' > "$REPO/src/t.sh"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
card() {  # <file> <g1> <g2> <g3> <ledger 상대경로>
  mkdir -p "$(dirname "$1")"
  { echo "# 인덱스: $(basename "$1" .md)"; echo "<!-- ledger: $5 -->"; echo '- 제안서: 없음 — 시험 카드'; echo '- 설치: 없음'
    echo '## 골 원문'; printf '%s\n%s\n%s\n' "$2" "$3" "$4"
    echo '## 배경'; echo '시험 카드다.'
    echo '## 계약↔시험 대응표'; echo '| 계약 | 시험 |'; echo '|---|---|'; echo '| A1 | ① |'
    echo '## 구현 범위'; echo '1. src/t.sh 수정'
    echo '## 완료 조건'; echo 'rc0.'
    echo '## 골좌표'; echo '닫는 증거 「닫는 증거 정본 문장은 이 문장 전체를 복붙해야 한다.」'
    echo '## 상태'; echo '- 시험'; } > "$1"
}
HC="$REPO/design/harness/indices/진행/h1.md"; VC="$REPO/design/v65/indices/진행/v1.md"
card "$HC" "$H1" "$H2" "$H3" design/harness/GOAL-harness.md
card "$VC" "$V1" "$V2" "$V3" design/v65/GOAL-LEDGER-v65.md
mkenv() {  # [$1=추가 줄] 팀 env 재작성 — 하위 셸 계약(⑥)용 추가 export 를 붙일 수 있다
  { echo '_R="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"'
    echo 'export FT_GOAL_LINES_FILE="$_R/.fable-team/bin-harness/goal-lines-harness.txt"'; echo 'unset _R'
    [ $# -ge 1 ] && printf '%s\n' "$1"; } > "$ENV"
}
mkenv; git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm base >/dev/null 2>&1
rm -f "$ENV"   # env 는 커밋하지 않는다 → 아래 git worktree 에는 없다(② 의 핵심)
REPO_P="$(cd "$REPO" && pwd -P)"
x() {  # x <기대rc> <설명> <grep -F 문구|-> <lint> [카드…]
  local want="$1" name="$2" pat="$3" lint="$4"; shift 4
  local out rc; out="$( cd "$REPO" && bash "$lint" "$@" 2>&1 )"; rc=$?
  [ "$rc" = "$want" ] || { bad "$name → rc=$rc(기대 $want) $out"; return 1; }
  { [ "$pat" = "-" ] || printf '%s' "$out" | grep -q -F -- "$pat"; } || { bad "$name → 문구 없음: $pat / $out"; return 1; }
  ok "$name"
}
xg() {  # xg <기대rc> <설명> <grep -F 문구> <dir> <lint> [카드…] — 실행 디렉터리 지정 · grep 문구 필수
  local want="$1" name="$2" pat="$3" dir="$4" lint="$5"; shift 5
  local out rc; out="$( cd "$dir" && bash "$lint" "$@" 2>&1 )"; rc=$?
  [ "$rc" = "$want" ] || { bad "$name → rc=$rc(기대 $want) $out"; return 1; }
  printf '%s' "$out" | grep -q -F -- "$pat" || { bad "$name → 문구 없음: $pat / $out"; return 1; }
  ok "$name"
}

# ── ① harness 카드 · env 있음 · FT_GOAL_LINES_FILE 비음 → rc0 (기준판 = 골 2·3줄 불일치 rc1) ──
mkenv
x 0 "① harness 카드 · env 있음 → OK rc0" "OK " "$LINT" "$HC"
x 0 "① 출처 INFO = 팀 harness env" "INFO 골 줄 출처 = 팀 harness env" "$LINT" "$HC"

# ── ② 같은 카드를 git worktree 경로로 → rc0 (env 는 git-common-dir 루트에서) ──
git -C "$REPO" worktree add -q "$T/wt" -b wtbranch >/dev/null 2>&1 || bad "② worktree 생성 실패"
out="$( cd "$T/wt" && bash "$LINT" "$T/wt/design/harness/indices/진행/h1.md" 2>&1 )"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q -F "$REPO_P/.fable-team/bin-harness/" && ! printf '%s' "$out" | grep -q -F "$T/wt/.fable-team" \
  && ok "② worktree 카드 → OK rc0 · env 는 git-common-dir(본 리포) 루트에서" || bad "② rc=$rc $out"

# ── ③ 명시값이 이긴다: FT_GOAL_LINES_FILE = v65 골 파일 + harness 카드 → REJECT ──
FT_GOAL_LINES_FILE="$T/goal-v65.txt" x 1 "③ 명시값이 이김 → REJECT rc1" "골 1줄 불일치" "$LINT" "$HC"

# ── ④ v65 카드 · env 없음 → 기준판과 같은 결과(rc0) ──
x 0 "④ v65 카드 → v65 기본 rc0" "INFO 골 줄 출처 = v65 기본 — 팀 v65" "$LINT" "$VC"

# ── ⑤ harness 카드 · env 파일 없음 → v65 기본 + INFO 1줄 · REJECT rc1 ──
mv "$ENV" "$T/env.off"
x 1 "⑤ env 없음 → v65 기본 + REJECT rc1" "INFO 골 줄 출처 = v65 기본 — 팀 harness env 없음" "$LINT" "$HC"
mv "$T/env.off" "$ENV"

# ── ⑥ env 가 다른 변수(ROOT)도 export → lint 의 ROOT·원장 경로 그대로(하위 셸) ──
mkenv 'export ROOT=/nonexistent-ROOT-r1734'
x 0 "⑥ env 의 ROOT 가 안 샌다 → rc0 · 원장 경로는 그대로(상대 표시)" "ledger=design/harness/GOAL-harness.md" "$LINT" "$HC"
mkenv

# ── ⑦ harness 카드 + v65 카드 한 번에 → 각자 맞는 골로 판정(OK 2줄) ──
out="$( cd "$REPO" && bash "$LINT" "$HC" "$VC" 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^OK ')" = 2 ] && ok "⑦ 두 카드 각자 골로 OK 2줄" || bad "⑦ rc=$rc $out"

# ── 변이 M1~M3 — 사본에서만 · 사례마다 원본 대조 1회 ──
c3() { ( cd "$REPO" && FT_GOAL_LINES_FILE="$T/goal-v65.txt" bash "$1" "$HC" ) >/dev/null 2>&1; }
c6() { mkenv 'export ROOT=/nonexistent-ROOT-r1734'; local out r; out="$( cd "$REPO" && bash "$1" "$HC" 2>&1 )"; r=$?; mkenv
  [ "$r" = 0 ] && printf '%s' "$out" | grep -q -F 'ledger=design/harness/GOAL-harness.md'; }
c7() { ( cd "$REPO" && bash "$1" "$HC" "$VC" ) >/dev/null 2>&1; }
rc_of() { local r; "$@" >/dev/null 2>&1; r=$?; printf '%s' "$r"; }
mkmut() {  # mkmut <출력> <그 줄 정규식> <새 줄 전체> — 맞는 줄이 정확히 1개가 아니면 실패(3)
  python3 - "$LINT" "$1" "$2" "$3" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines(True)
pat = re.compile(sys.argv[3]); hit = [i for i, l in enumerate(lines) if pat.search(l)]
if len(hit) != 1: print("MUT-LINE-COUNT %d" % len(hit)); sys.exit(3)
lines[hit[0]] = sys.argv[4] + "\n"
open(sys.argv[2], "w", encoding="utf-8").write("".join(lines))
PY
}
mut() {  # mut <이름> <사례함수> <원본 기대 rc> <옛 줄 정규식> <새 줄> — 변이 = 사례 결과가 갈린다(FAIL 로 잡힘)
  local name="$1" cf="$2" want="$3" mf="$MUTL" rb ro
  if ! mkmut "$mf" "$4" "$5"; then bad "$name 변이 줄을 못 찾음"; return; fi
  rb="$(rc_of "$cf" "$mf")"; ro="$(rc_of "$cf" "$LINT")"
  [ "$ro" = "$want" ] && ok "$name 원본 대조: 같은 사례 rc=$ro" || bad "$name 원본 대조 rc=$ro(기대 $want)"
  [ "$rb" != "$want" ] && ok "$name 변이 → rc=$rb (원본 $want) = FAIL 로 잡힘" || bad "$name 변이가 안 잡힘(rc=$rb)"
}
mut M1 c3 1 '^  if \[ -z "\$g" \] && \[ -n "\$t" \]' '  if [ -n "$t" ] && [ "$t" != v65 ]; then r="$(git -C "$(dirname -- "$f")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; r="${r%/.git}"; e="$r/.fable-team/bin-$t/$t-env.sh"'
mut M2 c6 0 'read -r GOAL1; read -r GOAL2' '  _e="$ROOT/.fable-team/bin-harness/harness-env.sh"; [ -f "$_e" ] && . "$_e"; { read -r GOAL1; read -r GOAL2; read -r GOAL3; } < <(goal_lines_for "$f")'
mut M3 c7 0 'read -r GOAL1; read -r GOAL2' '  [ -n "${GOAL1:-}" ] || { read -r GOAL1; read -r GOAL2; read -r GOAL3; } < <(goal_lines_for "$f")'

echo "fail=$fail"; [ "$fail" = 0 ]
