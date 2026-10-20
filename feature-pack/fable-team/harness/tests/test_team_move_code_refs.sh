#!/usr/bin/env bash
# test_team_move_code_refs.sh — R587 팀 폴더 이동 «코드·시험의 옛 경로» 검사 (카드 시험 ⓐ~ⓓ · arch 112 실측)
#   ⓐ 이동 뒤 --verify 가 코드·시험 안 옛 경로 design/<팀>/ 을 ERR 로 짚는다(지금 판 = ERR 0 → FAIL)
#   ⓑ archive·evidence·CLOSEOUT 등 «기록» 안 옛 경로는 셈 밖 (ERR 도 WARN 도 0)
#   ⓒ 이동 전 --plan 에 `BEFORE <팀> code-ref <n>` 줄 + blockers 에 n
#   ⓓ 옛 경로 0 이면 VERIFY ERR=0 그대로 rc0
# 임시 리포·가짜 tmux·가짜 lsof 만 쓴다 — 실제 리포·seats·tmux 세션·press 는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()   { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:350}";; *) ok "$3";; esac; }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 기대 «$2» 실제 «$1»"; }

mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "${FAKE_PANES:-/nonexistent}" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
esac
EOF
cat > "$T/fake/lsof" <<'EOF'
#!/usr/bin/env bash
printf 'p1\ncfake\nn/dev/null\n'
[ -s "${FAKE_LSOF:-/nonexistent}" ] && while read -r c p n; do printf 'p%s\nc%s\nn%s\n' "$p" "$c" "$n"; done < "${FAKE_LSOF}"
exit 0
EOF
chmod +x "$T/fake/tmux" "$T/fake/lsof"
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── 픽스처: 팀 1(x) · 명단·팀셋 표 2·README 지도·코드 1·시험 1 ───────────────
mkteam() {  # <폴더> <팀>
  mkdir -p "$1/indices/진행"; : > "$1/indices/.gitkeep"
  printf '# %s\n정본 위치: design/%s/README.md\n## 파일 지도\n| 경로 | 뜻 |\n|---|---|\n| `README.md` | 지도 |\n| `indices/` | 카드 |\n' "$2" "$2" > "$1/README.md"
}
mkrepo() {  # <리포> <꼴 1|2> — x 팀 하나
  local R="$1" form="$2" p="design/x/"; [ "$form" = 2 ] && p="design/teams/x/"
  mkdir -p "$R/design" "$R/.fable-team/state" "$R/.baton" "$R/.worktrees" "$R/tests" "$R/scripts"
  git -C "$R" init -q -b main
  printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| x | `%s` | byz-x-master-claude | 현역 |\n' "$p" > "$R/design/TEAMS.md"
  printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n| x | 3 |\n' > "$R/design/TEAMSET.md"
  case "$form" in 1) mkteam "$R/design/x" x;; 2) mkteam "$R/design/teams/x" x;; esac
  printf '.worktrees/\n.fable-team/\n.baton/\n' > "$R/.gitignore"
  printf 'P = "design/x/README.md"\n' > "$R/tests/test_x.py"
  printf '#!/usr/bin/env bash\necho design/x/README.md\n' > "$R/scripts/y.sh"
}
TM() { FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" "$@" 2>&1; }

REPO="$T/repo"; mkrepo "$REPO" 1; GITC "$REPO" add -A >/dev/null 2>&1; GITC "$REPO" commit -q -m init

echo "== ⓒ 이동 전 --plan: BEFORE code-ref 2 + blockers 에 셈"
out="$(TM --plan x)"; rc=$?
eq "$rc" 0 "ⓒ plan rc0"
has "$out" "BEFORE x code-ref 2" "ⓒ BEFORE x code-ref 2(tests/test_x.py · scripts/y.sh)"
has "$out" "PLAN-END blockers=2" "ⓒ blockers 에 code-ref 2 가 들어간다"

echo "== ⓐ 이동 뒤 --verify: 코드·시험 옛 경로 = ERR(기록은 셈 밖)"
out="$(TM --apply x)"; rc=$?
eq "$rc" 0 "ⓐ apply x rc0"
mkdir -p "$REPO/design/teams/x/archive" "$REPO/design/teams/x/evidence"
printf '옛 경로 기록: design/x/README.md\n' > "$REPO/design/teams/x/archive/old.md"
printf '옛 경로 증거: design/x/README.md\n' > "$REPO/design/teams/x/evidence/old.txt"
printf '옛 경로 마감: design/x/README.md\n' > "$REPO/design/teams/x/CLOSEOUT.md"
GITC "$REPO" add -A >/dev/null 2>&1; GITC "$REPO" commit -q -m "기록 3종"
out="$(TM --verify x)"; rc=$?
eq "$rc" 1 "ⓐ verify rc1(ERR>0)"
has "$out" "ERR x 코드 옛 경로 design/x/ : tests/test_x.py:1" "ⓐ ERR tests/test_x.py:1"
has "$out" "ERR x 코드 옛 경로 design/x/ : scripts/y.sh:2" "ⓐ ERR scripts/y.sh:2"
has "$out" "VERIFY ERR=2" "ⓐ VERIFY ERR=2(코드·시험 2파일)"
hasnt "$out" "archive/old.md" "ⓑ archive 기록은 셈 밖(ERR·WARN 0)"
hasnt "$out" "evidence/old.txt" "ⓑ evidence 기록은 셈 밖"
hasnt "$out" "CLOSEOUT.md" "ⓑ CLOSEOUT 기록은 셈 밖"

echo "== ⓑ code_refs 직접 호출 — 기록 폴더 제외 · 히트 = (경로, 줄)"
refs="$(FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" python3 -I -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import ft_team_move as m
print(json.dumps(m.code_refs(m.make_ctx(), "x")))' "$SRC" 2>&1)"
eq "$refs" '[["scripts/y.sh", 2], ["tests/test_x.py", 1]]' "ⓑ code_refs = 코드·시험 2건(기록 3종 제외) · 경로 정렬"

echo "== ⓓ 옛 경로 0 이면 VERIFY ERR=0 그대로"
R2="$T/repo2"; mkrepo "$R2" 2
rm -rf "$R2/tests" "$R2/scripts"
printf '# x\n정본 위치: design/teams/x/README.md\n## 파일 지도\n| 경로 | 뜻 |\n|---|---|\n| `README.md` | 지도 |\n| `indices/` | 카드 |\n' > "$R2/design/teams/x/README.md"
mkdir -p "$R2/design/teams/x/archive"; printf 'design/x/README.md\n' > "$R2/design/teams/x/archive/old.md"
GITC "$R2" add -A >/dev/null 2>&1; GITC "$R2" commit -q -m init
out="$(FT_REPO_ROOT="$R2" FT_PROJECT_ROOT="$R2" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --verify x 2>&1)"; rc=$?
eq "$rc" 0 "ⓓ verify rc0"
has "$out" "VERIFY ERR=0" "ⓓ 코드·시험에 옛 경로 0 + 기록만 있음 → ERR=0(기록은 셈 밖)"

echo "== 0 문법 · 키트 사본 cmp0"
for f in ft_team_move.py ft_team_move_apply.py; do python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/$f" && ok "ast $f" || bad "ast $f"; done
for f in ft_team_move.py ft-team-move.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"; done
echo "== fail=$fail"; [ "$fail" = 0 ]
