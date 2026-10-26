#!/usr/bin/env bash
# test_team_path_oldpath_md.sh — r447 팀 폴더 옛 경로 재발 방지 (카드 시험 입력 ⓐ~ⓕ)
#   ⓐ 리졸버: 쌍둥이 공존 + 명단 새 꼴 → 새 꼴 + WARN · 명단 옛 꼴 팀은 변경 0
#   ⓑ 카드 위치 옛 꼴 → ft-index-lint · ft-nano-spawn --dry-run · ft-index-move REJECT · 새 꼴 위치는 위치 REJECT 0
#   ⓒ ft-team-path-lint --md: 새 꼴 팀 옛 글자 ERR(줄 번호) · 전환 중 팀 INFO · 꼴3 팀 대상 아님
#   ⓓ ft-team-move 쌍둥이 병합 이동(유일본 2 · 다른 내용 3 · 같은 내용 1 · 본문 치환 · 미커밋 REJECT · revert 원본 복원)
#   ⓔ ft-merge-land: 가지에 옛 꼴 새 파일 1 → REJECT(착지 0) · 새 꼴이면 착지  ⓕ 600/300 0 · bin/kit 짝 cmp0
# 임시 리포·가짜 tmux/lsof/gh 만 쓴다 — 실제 팀 가지·seats·tmux 세션은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"; BIN="$HERE/../../harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_REPO_ROOT FT_TEAMS_MD
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
GITC() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }
CHANGED="ft-team-lib.sh ft-team-path-lint.sh ft-team-move.sh ft-nano-spawn.sh ft-index-move.sh ft-merge-land.sh ft_team_move.py ft_team_move_apply.py ft_team_move_twin.py"

echo "== 0 문법 · bin/kit 짝 cmp0"
for f in $CHANGED ft-index-lint.sh; do case "$f" in *.py) python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$KIT/$f";; *) bash -n "$KIT/$f";; esac && ok "문법 $f" || bad "문법 $f"; done
for f in $CHANGED; do cmp -s "$KIT/$f" "$BIN/$f" && ok "짝 cmp0 $f" || bad "짝 cmp $f"; done

# 픽스처: alpha = 새 꼴(design/teams/alpha/) · beta = 옛 꼴(전환 중) · harness = 꼴3
mkrepo() {
  local R="$1"; mkdir -p "$R/design/teams/alpha/indices/대기" "$R/design/beta/indices/대기"
  git init -q -b main "$R"
  printf '# 팀 명단\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` | h | 현역 |\n| alpha | `design/teams/alpha/` | a | 현역 |\n| beta | `design/beta/` | b | 현역 |\n' > "$R/design/TEAMS.md"
  printf '# 팀셋\n## 표 2\n| 팀 | 상한 |\n|---|---|\n| alpha | 3 |\n| beta | 3 |\n' > "$R/design/TEAMSET.md"
  printf '# alpha\n정본: design/teams/alpha/README.md\n' > "$R/design/teams/alpha/README.md"
  printf '# beta\n' > "$R/design/beta/README.md"
  printf '.worktrees/\n.fable-team/\n' > "$R/.gitignore"
  GITC "$R" add -A; GITC "$R" commit -q -m init; git -C "$R" update-ref refs/remotes/origin/main HEAD
}
R="$T/repo"; mkrepo "$R"
mkdir -p "$R/design/alpha/indices/대기"; printf '# 옛 카드\n' > "$R/design/alpha/indices/대기/x.md"; printf '# 새 카드\n' > "$R/design/teams/alpha/indices/대기/y.md"
LIB() { ( cd "$R" && bash -c '. "$1"; shift; "$@"' _ "$KIT/ft-team-lib.sh" "$@" ); }

echo "== ⓐ 리졸버 쌍둥이 공존 → 새 꼴 + WARN"
out="$(LIB ft_team_root alpha 2>"$T/err")"; err="$(cat "$T/err")"
[ "$out" = "$R/design/teams/alpha" ] && ok "ⓐ alpha(명단 새 꼴 · 옛 폴더 실재) → design/teams/alpha" || bad "ⓐ alpha root: $out"
has "$err" "WARN 옛 꼴 잔존 1파일 — ft-team-move.sh --apply alpha" "ⓐ stderr WARN «옛 꼴 잔존 N파일»"
[ "$(LIB ft_team_root alpha --alt 2>/dev/null)" = "$R/design/alpha" ] && ok "ⓐ --alt 그대로(옛 꼴 쌍둥이)" || bad "ⓐ --alt"
out="$(LIB ft_team_root beta 2>"$T/err")"
[ "$out" = "$R/design/beta" ] && [ ! -s "$T/err" ] && ok "ⓐ beta(명단 옛 꼴) → 옛 꼴 그대로 · WARN 0(변경 0)" || bad "ⓐ beta: $out $(cat "$T/err")"
rm -rf "$R/design/alpha.tmp"; mv "$R/design/alpha" "$R/design/alpha.tmp"
LIB ft_team_root alpha 2>"$T/err" >/dev/null; [ ! -s "$T/err" ] && ok "ⓐ 옛 폴더 없음 → WARN 0" || bad "ⓐ 옛 폴더 없음 WARN: $(cat "$T/err")"
mv "$R/design/alpha.tmp" "$R/design/alpha"

echo "== ⓑ 카드 위치 옛 꼴 → index-lint · nano-spawn --dry-run · index-move REJECT"
OLDC="$R/design/alpha/indices/대기/x.md"; NEWC="$R/design/teams/alpha/indices/대기/y.md"; BETAC="$R/design/beta/indices/대기/z.md"; printf '# beta 카드\n' > "$BETAC"
out="$(cd "$R" && bash "$KIT/ft-index-lint.sh" "$OLDC" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 카드 위치 옛 경로 — ft-team-move.sh --apply alpha 뒤 다시" "ⓑ index-lint 옛 꼴 위치 → REJECT rc1" || bad "ⓑ index-lint rc=$rc $out"
out="$(cd "$R" && bash "$KIT/ft-index-lint.sh" "$NEWC" 2>&1)"; hasnt "$out" "카드 위치 옛 경로" "ⓑ index-lint 새 꼴 위치 → 위치 REJECT 0"
out="$(cd "$R" && bash "$KIT/ft-index-lint.sh" "$BETAC" 2>&1)"; hasnt "$out" "카드 위치 옛 경로" "ⓑ index-lint 전환 중 팀(beta) 옛 꼴 → 위치 REJECT 0(변경 0)"
echo '{"_master":"byz-harness-master-claude#1","byz-harness-master-claude#1":{"role":"master"}}' > "$R/.fable-team.seats.json"   # r975: 회신 대상 = 명부 _master
mkdir -p "$T/sbin" "$T/sheet/.fable-team/state"   # spawn 은 임시 bin 사본(설치 폴더 밖 · test_nano_team_env 와 같은 묶음) — 라이브 루트·정지 파일 0
cp "$KIT/ft-nano-spawn.sh" "$KIT/ft-proposal-gate.sh" "$KIT/ft-team-lib.sh" "$KIT/ft-resource-gate.sh" "$KIT/ft_raised.py" "$KIT/ft_teamset.py" "$KIT/ft_spawn_queue.py" \
  "$KIT/ft-sheet-events.sh" "$KIT/ft_sheet_events.py" "$KIT/ft_sheet_confirm.py" "$KIT/ft_sheet_key.py" "$KIT/ft_board_env.py" "$KIT/ft_board_mail.py" "$T/sbin/"
. "$HERE/lib/bin_source_deps.sh"; copy_source_deps "$KIT" "$T/sbin" || bad "r686 사본 source 대상 채우기"   # r686: 고른 도구가 source 하는 같은 폴더 lib(r672 swap · research-seat …)
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/sbin/ft-index-lint.sh"; chmod +x "$T/sbin/"*
SP() { ( cd "$R" && env -i HOME="$HOME" PATH="$PATH" FT_TEAMSET=0 FT_RES_ROOT="$FT_RES_ROOT" FT_SHEET_ROOT="$T/sheet" FT_NANO_PREFIX=byz-alpha-nano- FT_SEATS_JSON="$R/.fable-team.seats.json" bash "$T/sbin/ft-nano-spawn.sh" "$@" --dry-run 2>&1 ); }
out="$(SP "$OLDC")"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 카드 위치 옛 경로" "ⓑ nano-spawn --dry-run 옛 꼴 → REJECT rc1" || bad "ⓑ spawn rc=$rc ${out: -400}"
mv "$NEWC" "$T/y.md"; out="$(SP "design/teams/alpha/indices/대기/x.md")"; rc=$?   # 새 꼴 경로를 줬는데 카드는 옛 꼴에만 = 쌍둥이 해석 뒤 REJECT
[ "$rc" = 1 ] && has "$out" "REJECT 카드 위치 옛 경로" "ⓑ nano-spawn 새 꼴 이름 → 쌍둥이(옛 꼴)로 해석돼도 REJECT" || bad "ⓑ spawn 쌍둥이 rc=$rc ${out: -400}"
mv "$T/y.md" "$NEWC"
out="$(SP "$NEWC")"; hasnt "$out" "카드 위치 옛 경로" "ⓑ nano-spawn 새 꼴 위치 → 위치 REJECT 0"; has "$out" "PLAN seat=" "  └ 새 꼴은 PLAN 줄까지 간다"
out="$(cd "$R" && bash "$KIT/ft-index-move.sh" "$OLDC" 진행 --seat s 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 카드 위치 옛 경로" "ⓑ index-move 옛 꼴 → REJECT rc1" || bad "ⓑ index-move rc=$rc $out"
[ -f "$OLDC" ] && ok "  └ 이동 0(카드 제자리)" || bad "  └ 카드가 움직였다"
out="$(cd "$R" && bash "$KIT/ft-index-move.sh" "$NEWC" 진행 --seat s 2>&1)"; hasnt "$out" "카드 위치 옛 경로" "ⓑ index-move 새 꼴 → 위치 REJECT 0"

echo "== ⓒ ft-team-path-lint --md"
printf '# 카드\n- 근거: design/teams/alpha/README.md\n- 옛: design/alpha/indices/대기/x.md\n```\ncat /abs/root/design/alpha/a.md\n```\n- 하네스: $FT_HARNESS_ROOT/design/harness/x.md\n' > "$R/design/teams/alpha/indices/대기/bad.md"
out="$(bash "$KIT/ft-team-path-lint.sh" --md "$R/design/teams/alpha" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "ERR $R/design/teams/alpha/indices/대기/bad.md:3:" "ⓒ 새 꼴 팀 옛 글자 → ERR 줄 번호(3)" || bad "ⓒ md rc=$rc $out"
has "$out" "bad.md:5:" "ⓒ 코드 블록 안(절대경로)도 ERR(제외 0)"; hasnt "$out" "bad.md:2:" "ⓒ 새 꼴 글자 design/teams/alpha/ 는 ERR 0"; hasnt "$out" "bad.md:7:" "ⓒ 꼴3 팀(harness) 글자는 대상 아님"
has "$out" "ERR 카드·문서 옛 경로 글자 2줄(1파일)" "ⓒ 끝줄 ERR 집계"
printf '# b\n옛: design/beta/README.md\n' > "$R/design/beta/indices/대기/b.md"
out="$(bash "$KIT/ft-team-path-lint.sh" --md "$R/design/beta" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "$out" "INFO 전환 중 팀" "ⓒ 전환 중 팀(beta) 옛 글자 → INFO rc0" || bad "ⓒ beta rc=$rc $out"
rm -f "$R/design/teams/alpha/indices/대기/bad.md"
out="$(bash "$KIT/ft-team-path-lint.sh" --md "$R/design/teams/alpha" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "$out" "OK md 옛 경로 글자 0" "ⓒ 깨끗한 폴더 → OK rc0" || bad "ⓒ clean rc=$rc $out"
out="$(bash "$KIT/ft-team-path-lint.sh" --md 2>&1)"; [ $? = 2 ] && ok "ⓒ --md 인자 없음 → usage rc2" || bad "ⓒ usage $out"

echo "== ⓓ ft-team-move 쌍둥이 병합 이동"
R2="$T/repo2"; mkrepo "$R2"; mkdir -p "$R2/.fable-team/state" "$T/fake" "$R2/design/alpha/indices/대기"
printf '#!/usr/bin/env bash\necho "no server running on /tmp/fake"; exit 1\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\nprintf "p1\\ncfake\\nn/dev/null\\n"\n' > "$T/fake/lsof"; chmod +x "$T/fake/"*
for u in u1 u2; do printf '# %s\n근거: design/alpha/README.md\n' "$u" > "$R2/design/alpha/indices/대기/$u.md"; done
for d in d1 d2 d3; do printf '# %s 옛 내용\n' "$d" > "$R2/design/alpha/indices/대기/$d.md"; printf '# %s 새 내용\n' "$d" > "$R2/design/teams/alpha/indices/대기/$d.md"; done
printf '# s1\n근거: design/alpha/README.md\n' > "$R2/design/alpha/indices/대기/s1.md"; printf '# s1\n근거: design/teams/alpha/README.md\n' > "$R2/design/teams/alpha/indices/대기/s1.md"
printf '# 새쪽만\n옛 글자: design/alpha/x\n' > "$R2/design/teams/alpha/new-only.md"
GITC "$R2" add -A; GITC "$R2" commit -q -m twin
TM() { FT_REPO_ROOT="$R2" FT_PROJECT_ROOT="$R2" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$KIT/ft-team-move.sh" "$@" 2>&1; }
manifest() { (cd "$1" && find . -type f ! -path './.git/*' ! -path './.fable-team/state/team-move/*' -print0 | sort -z | xargs -0 shasum -a 256); }
out="$(TM --plan alpha)"; rc=$?
[ "$rc" = 0 ] && has "$out" "PLAN-TWIN alpha 쌍둥이 공존 design/alpha/ 6파일 → 유일본 2 · 다른 내용(옛 쪽 승) 3 · 같은 내용(옛 삭제) 1" "ⓓ --plan = PLAN-TWIN 집계(2·3·1)" || bad "ⓓ plan rc=$rc $out"
has "$out" "PLAN-END blockers=0" "  └ blockers=0"
echo wip >> "$R2/design/alpha/indices/대기/u1.md"; H0="$(git -C "$R2" rev-parse HEAD)"
out="$(TM --apply alpha)"; rc=$?
[ "$rc" = 1 ] && has "$out" "[wip] 먼저" "ⓓ 미커밋 있으면 REJECT «[wip] 먼저»" || bad "ⓓ wip rc=$rc $out"
[ "$(git -C "$R2" rev-parse HEAD)" = "$H0" ] && ok "  └ REJECT 는 커밋 0" || bad "  └ 커밋이 생겼다"
git -C "$R2" checkout -q -- design/alpha
BEFORE="$(manifest "$R2")"
out="$(TM --apply alpha)"; rc=$?; SNAP="$(printf '%s\n' "$out" | sed -n 's/^SNAPSHOT //p' | tail -1)"
[ "$rc" = 0 ] && has "$out" "TWIN-MERGED alpha MOVED 2 OVERWROTE 3 DROPPED-SAME 1" "ⓓ apply = MOVED 2 OVERWROTE 3 DROPPED-SAME 1" || bad "ⓓ apply rc=$rc $out"
[ -z "$(git -C "$R2" ls-tree -r HEAD design/alpha)" ] && ok "ⓓ ls-tree HEAD design/alpha = 0" || bad "ⓓ 옛 폴더 추적 파일 남음"
[ ! -e "$R2/design/alpha" ] && ok "ⓓ 빈 옛 폴더 정리" || bad "ⓓ 옛 폴더 디스크에 남음"
has "$(cat "$R2/design/teams/alpha/indices/대기/d2.md")" "d2 옛 내용" "ⓓ 같은 이름 다른 내용 = 옛 쪽 내용 승"
has "$(cat "$R2/design/teams/alpha/indices/대기/u1.md")" "design/teams/alpha/README.md" "ⓓ 유일본 이동 + 본문 글자 치환"
has "$(cat "$R2/design/teams/alpha/new-only.md")" "design/teams/alpha/x" "ⓓ 새 쪽 파일 옛 글자도 치환"
[ -z "$(git -C "$R2" status --porcelain)" ] && ok "ⓓ 작업 트리 깨끗(한 커밋)" || bad "ⓓ 미커밋: $(git -C "$R2" status --porcelain | head -3)"
out="$(bash "$KIT/ft-team-path-lint.sh" --md "$R2/design/teams/alpha" 2>&1)"; has "$out" "OK md 옛 경로 글자 0" "ⓓ 병합 뒤 md 린트 OK"
out="$(TM --revert "$SNAP")"; rc=$?
[ "$rc" = 0 ] && has "$out" "REVERT-END" "ⓓ --revert rc0" || bad "ⓓ revert rc=$rc $out"
[ "$(manifest "$R2")" = "$BEFORE" ] && ok "ⓓ revert 뒤 모든 파일 sha256 원본과 동일" || { bad "ⓓ revert manifest 다름"; diff <(echo "$BEFORE") <(manifest "$R2") | head -6; }
out="$(TM --apply beta)"; hasnt "$out" "TWIN-MERGED" "ⓓ 전환 중 팀(beta)은 쌍둥이 병합 대상 아님"

echo "== ⓔ ft-merge-land 옛 꼴 새 파일 → REJECT"
. "$HERE/_merge_fixture.sh"
E="$T/e"; mkdir -p "$E"; mkrepo "$E"; mkdir -p "$E/state"
export FT_ROOT="$E" FT_AUTONOMY_STATE_DIR="$E/state" FT_GH="$E/gh-stub" FT_GH_WRITE="$E/gh-stub" STUB_JSON="$E/pr.json"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\nexit 0\n' > "$E/gh-stub"; chmod +x "$E/gh-stub"
mkdir -p "$W/design/teams/alpha"; cp "$R/design/TEAMS.md" "$W/design/TEAMS.md"; printf 'r\n' > "$W/design/teams/alpha/README.md"; cm "$W" teams; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
mkpr() {  # <번호> <파일>
  git -C "$W" checkout -q -B "pr$1" origin/main; mkdir -p "$W/$(dirname "$2")"; echo "pr$1" > "$W/$2"; cm "$W" "pr $1"
  git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"t","body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" > "$STUB_JSON"
}
M1="$(sha "$ORIGIN" refs/heads/main)"
mkpr 21 "design/alpha/indices/대기/new.md"; apv --approve-sha "$PRSHA"; out="$(bash "$KIT/ft-merge-land.sh" 21 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 가지에 옛 꼴 경로 새 파일 1개" "ⓔ 옛 꼴 새 파일 1 → REJECT 1줄 rc1" || bad "ⓔ rc=$rc ${out:0:400}"
[ "$(sha "$ORIGIN" refs/heads/main)" = "$M1" ] && ok "  └ 착지 0(main 불변)" || bad "  └ main 이 움직였다"
mkpr 22 "design/teams/alpha/indices/대기/new.md"; apv --approve-sha "$PRSHA"; out="$(bash "$KIT/ft-merge-land.sh" 22 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "$out" "LANDED pr=22" "ⓔ 새 꼴 새 파일 → 착지 rc0" || bad "ⓔ 새 꼴 rc=$rc ${out:0:400}"
git -C "$W" fetch -q origin
mkpr 23 "design/beta/new.md"; apv --approve-sha "$PRSHA"; out="$(bash "$KIT/ft-merge-land.sh" 23 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ⓔ 전환 중 팀(beta) 옛 꼴 새 파일 → 착지(변경 0)" || bad "ⓔ beta rc=$rc ${out:0:400}"

echo "== ⓕ 600/300 0 · 외부 호출 0"
hasnt "$(cd "$KIT" && grep -nE "\b($((6*100))|$((3*100)))\b" ft_team_move_twin.py ft-team-lib.sh ft-team-path-lint.sh || true)" ":" "ⓕ 바뀐 lib·린트·병합 모듈에 600/300 숫자 0"
hasnt "$(cd "$KIT" && grep -nE 'curl|https?://|requests\.' ft_team_move_twin.py ft-team-lib.sh ft-team-path-lint.sh || true)" ":" "ⓕ 외부 호출 0"

echo "== fail=$fail"; [ "$fail" = 0 ]
