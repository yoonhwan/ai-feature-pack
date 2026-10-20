#!/usr/bin/env bash
# test_team_rename.sh — r468 팀 «이름» 바꾸기 도구 격리 시험 (카드 시험 입력 ⓐ~ⓖ)
#   ⓐ --plan = 변경 표 + PLAN-END blockers=0 · 쓰기 0   ⓑ --apply = 스냅샷 + git mv + 명단 행 + 본문 치환(패턴 2) + 각주 + 명부·env rename · 한 커밋 · RESYNC
#   ⓒ --verify <새> ERR 0 · 잔여 WARN 목록(각주 제외)   ⓓ --revert = 바이트 복원 + git revert → ⓐ 전 상태 cmp0
#   ⓔ 새 이름 명단에 있음 / 옛 이름 없음 / 작업 트리 더러움 / pane cwd 점유 → REJECT 쓰기 0   ⓕ 쌍둥이·옛 꼴 → REJECT 먼저 ft-team-move
#   ⓖ 옛 계보 우편 감시(watch · 7일 · peek 만) + ft-tick 배선 · 600/300 0
# 임시 폴더·가짜 tmux·가짜 lsof·가짜 mbox 만 쓴다 — 실제 리포·명부·tmux·우편함은 건드리지 않는다 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }

echo "== 0 문법 · 키트 사본 cmp0"
bash -n "$SRC/ft-team-rename.sh" && ok "bash -n ft-team-rename.sh" || bad "bash -n ft-team-rename.sh"
bash -n "$SRC/ft-tick.sh" && ok "bash -n ft-tick.sh" || bad "bash -n ft-tick.sh"
python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/ft_team_rename.py" && ok "ast ft_team_rename.py" || bad "ast ft_team_rename.py"
for f in ft-team-rename.sh ft_team_rename.py ft-tick.sh team-tick-env.tsv; do cmp -s "$SRC/$f" "$KIT/$f" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"; done

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
exit 0
EOF
chmod +x "$T/fake/tmux" "$T/fake/lsof"
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── 픽스처: 팀 old·other(둘 다 design/teams/ 꼴) · 카드 3 · README 지도 · 명부(_name·_tree 옛 경로·행 2) · env 3파일 · nano-card-base 1 · worktree-info 1 ──
mkrepo() {  # <리포>
  local R="$1" t; mkdir -p "$R/design" "$R/.fable-team/state/nano-card-base" "$R/.baton" "$R/.worktrees"
  git -C "$R" init -q -b main
  { printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'
    for t in old other; do printf '| %s | `design/teams/%s/` | byz-%s-master-claude | 현역 |\n' "$t" "$t" "$t"; done; } > "$R/design/TEAMS.md"
  printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n| old | 3 |\n| other | 3 |\n' > "$R/design/TEAMSET.md"
  for t in old other; do
    mkdir -p "$R/design/teams/$t/indices/진행" "$R/design/teams/$t/indices/대기" "$R/design/teams/$t/indices/완성"
    printf '# %s\n정본 위치: design/teams/%s/README.md\n## 파일 지도\n| 경로 | 뜻 |\n|---|---|\n| `README.md` | 지도 |\n| `indices/` | 카드 |\n' "$t" "$t" > "$R/design/teams/$t/README.md"
  done
  printf '# 카드 c1\n- 근거: design/teams/old/README.md · 담당 byz-old-master-claude#1\n- 기능 이름 old 팀 화면(이력 글자)\n' > "$R/design/teams/old/indices/진행/c1.md"
  printf '# 카드 c2\n- 근거: design/teams/old/indices/진행/c1.md\n' > "$R/design/teams/old/indices/대기/c2.md"
  printf '# 카드 c3\n- 완성 byz-old-nano-a#0\n' > "$R/design/teams/old/indices/완성/c3.md"
  printf '# other\n- 참고: design/teams/old/README.md (다른 팀 이력 — 치환 0)\n' > "$R/design/teams/other/indices/진행/o1.md"
  printf '.worktrees/\n.fable-team/\n.baton/\n' > "$R/.gitignore"
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init; git -C "$R" update-ref refs/remotes/origin/main HEAD
  GITC "$R" worktree add -q "$R/.worktrees/wt1" -b nano/wt1
  printf '{"branch":"nano/wt1","purpose":"design/teams/old/indices/진행/c1.md"}' > "$R/.worktrees/wt1/.worktree-info.json"
  cat > "$R/.fable-team/seats-old.json" <<EOF
{
  "_name": "Seatbelt-OLD",
  "_label": "old",
  "_tree": "design/old/STATE.md",
  "_cards": "design/teams/old/indices",
  "_doc": "old 팀 레지스트리 · 카드 = design/teams/old/indices · env = .fable-team/bin-old/old-env.sh · 틱 = com.byz.ft-tick-old",
  "_master": "byz-old-master-claude#1",
  "byz-old-master-claude#0": {"role": "stop-ready", "index": "design/teams/old/indices/진행/c1.md"},
  "byz-old-master-claude#1": {"role": "master", "index": "design/teams/old/indices/진행/c1.md", "_replaces": ["byz-old-master-claude#0"]},
  "byz-old-nano-w#0": {"role": "nano", "worktree": "wt1", "index": "design/teams/old/indices/진행/c1.md"}
}
EOF
  mkdir -p "$R/.fable-team/bin-old"
  printf '# old 팀 값\nexport FT_SEATS_JSON=%s/.fable-team/seats-old.json\nexport FT_NANO_PREFIX=byz-old-nano-\nexport FT_NANO_WT_PREFIX=old-\nexport FT_ACTIVE_TAG=@zc_old_active\nexport FT_NANO_LEDGER=design/old/NANO-LEDGER-old.md\nexport FT_GOAL_LINES_FILE=%s/.fable-team/bin-old/goal-lines-old.txt\nexport FT_NANO_LEDGER_WT=%s/.worktrees/old-main\n' "$R" "$R" "$R" > "$R/.fable-team/bin-old/old-env.sh"
  printf '골 줄\n' > "$R/.fable-team/bin-old/goal-lines-old.txt"
  printf '<plist><string>com.byz.ft-tick-old</string><string>/tmp/ft-tick-old.log</string></plist>\n' > "$R/.fable-team/bin-old/ft-tick-old.plist"
  chmod 755 "$R/.fable-team/bin-old/old-env.sh"
  printf '{\n  "name": "byz-old-nano-a#0",\n  "card_path": "design/teams/old/indices/진행/c1.md",\n  "worktree": "%s"\n}\n' "$R" > "$R/.fable-team/state/nano-card-base/byz-old-nano-a#0.json"
  printf '[{"child_branch":"nano/wt1","purpose":"design/teams/old/ 정리"}]\n' > "$R/.baton/branches.json"
}
manifest() { (cd "$1" && find . \( -type f -o -type d \) ! -path './.git*' ! -path './.git/*' ! -path './.worktrees/wt1/.git' ! -path './.fable-team/state/team-rename*' -print0 | sort -z | xargs -0 -I{} sh -c 'if [ -d "{}" ]; then echo "D {}"; else shasum -a 256 "{}"; fi'); }
REPO="$T/repo"; mkrepo "$REPO"
TR() { FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_PANES="${FAKE_PANES:-}" PATH="$T/fake:$PATH" bash "$SRC/ft-team-rename.sh" "$@" 2>&1; }
BEFORE="$(manifest "$REPO")"; HEAD0="$(git -C "$REPO" rev-parse HEAD)"

echo "== ⓐ --plan old new = 변경 표 · 쓰기 0"
out="$(TR --plan old new)"; rc=$?
[ "$rc" = 0 ] && has "$out" "PLAN-END blockers=0" "ⓐ plan rc0 · blockers=0" || bad "ⓐ plan rc=$rc ← ${out:0:600}"
has "$out" "ROW TEAMS.md | old | \`design/teams/old/\` | byz-old-master-claude" "ⓐ 명단 TEAMS.md 행"; has "$out" "ROW TEAMSET.md | old | 3 |" "  └ TEAMSET.md 행"
has "$out" "REF1 팀 폴더 파일 4개 · 본문 치환 예상 design/teams/old/ 3곳 · byz-old- 2곳" "ⓐ 파일 N · 본문 치환 예상(패턴 2)"
has "$out" "REF3 명부 seats-old.json → seats-new.json 칸 4(_name·_label·_tree·_doc) · 행 3" "ⓐ 명부 칸 4 · 행 수"
has "$out" "REF4 nano-card-base 파일 1개" "ⓐ 저장 참조 REF4"; has "$out" "REF5 worktree-info 파일 1개" "  └ REF5"; has "$out" "REF6 baton branches.json 참조 1곳" "  └ REF6"; has "$out" "REF7 추가 파일 0개" "  └ REF7"
has "$out" "ENV bin-old/ → bin-new/ 파일 3개 · 이름 바뀜 3" "ⓐ env 폴더 3파일"
[ "$(manifest "$REPO")" = "$BEFORE" ] && [ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && ok "ⓐ plan 쓰기 0(manifest·HEAD 동일)" || bad "ⓐ plan 이 파일을 바꿨다"

echo "== ⓔ REJECT 4종 — 쓰기 0"
rej() {  # <이름> <기대 글자> <명령 인자...>
  local name="$1" want="$2"; shift 2; local o rc0; o="$(TR "$@")"; rc0=$?
  [ "$rc0" = 1 ] && has "$o" "$want" "ⓔ $name → REJECT rc1" || bad "ⓔ $name rc=$rc0 ← ${o:0:400}"
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && [ ! -e "$REPO/.fable-team/state/team-rename" ] && [ ! -e "$REPO/.fable-team/seats-new.json" ] && [ ! -e "$REPO/.fable-team/seats-other.json" ] \
    && ok "  └ $name 쓰기 0(HEAD·스냅샷·새 명부 없음)" || bad "  └ $name 쓰기 발생"
}
rej "새 이름이 명단에 이미 있음" "other 은 이미 팀 명단" --apply old other
rej "옛 이름 없음" "zz 은 팀 명단(TEAMS.md)에 없다" --apply zz new
printf 'x\n' >> "$REPO/design/teams/old/indices/진행/c1.md"
rej "작업 트리 더러움" "작업 트리 더러움" --apply old new
git -C "$REPO" checkout -q -- design/teams/old
printf 'byz-old-master-claude#1\t%s/design/teams/old/indices\n' "$REPO" > "$T/panes"
FAKE_PANES="$T/panes" rej "pane cwd 점유" "CWD byz-old-master-claude#1" --apply old new
[ "$(manifest "$REPO")" = "$BEFORE" ] && ok "ⓔ REJECT 4종 뒤 manifest 원본 그대로" || bad "ⓔ REJECT 뒤 manifest 다름"

echo "== ⓕ 쌍둥이(옛 꼴 design/old 잔존) · 옛 꼴 행 → REJECT 먼저 ft-team-move"
R2="$T/repo2"; mkrepo "$R2"; mkdir -p "$R2/design/old"; printf 'twin\n' > "$R2/design/old/x.md"; GITC "$R2" add -A >/dev/null; GITC "$R2" commit -q -m twin
H2="$(git -C "$R2" rev-parse HEAD)"
out="$(FT_REPO_ROOT="$R2" FT_PROJECT_ROOT="$R2" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-rename.sh" --apply old new 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$out" "먼저 ft-team-move.sh --apply old" "ⓕ 쌍둥이 → REJECT 먼저 ft-team-move" || bad "ⓕ 쌍둥이 rc=$rc ← ${out:0:400}"
[ "$(git -C "$R2" rev-parse HEAD)" = "$H2" ] && [ -d "$R2/design/teams/old" ] && ok "  └ 쌍둥이 REJECT 쓰기 0(rename 안에서 이동 0)" || bad "  └ 쌍둥이 쓰기 발생"
sed -i '' 's|`design/teams/old/`|`design/old/`|' "$R2/design/TEAMS.md"; GITC "$R2" commit -qam form1
out="$(FT_REPO_ROOT="$R2" FT_PROJECT_ROOT="$R2" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-rename.sh" --plan old new 2>&1)"
has "$out" "design/teams/old/ 꼴이 아니다" "ⓕ 옛 꼴 행 → plan BLOCK"; hasnt "$out" "blockers=0" "  └ blockers>0"

echo "== ⓑ --apply old new"
out="$(TR --apply old new)"; rc=$?
[ "$rc" = 0 ] && has "$out" "RENAMED old → new" "ⓑ apply rc0" || bad "ⓑ apply rc=$rc ← ${out:0:900}"
SNAP="$(printf '%s\n' "$out" | sed -n 's/^SNAPSHOT //p' | tail -1)"
case "$SNAP" in "$REPO/.fable-team/state/team-rename/"*-old-new/snapshot.json) [ -f "$SNAP" ] && ok "ⓑ 스냅샷 .fable-team/state/team-rename/<ts>-old-new/" || bad "ⓑ 스냅샷 없음";; *) bad "ⓑ 스냅샷 경로: $SNAP";; esac
[ -d "$REPO/design/teams/new" ] && [ ! -e "$REPO/design/teams/old" ] && ok "ⓑ git mv design/teams/old → new" || bad "ⓑ 폴더 이동 안 됨"
[ "$(git -C "$REPO" rev-list --count "$HEAD0..HEAD")" = 1 ] && [ -z "$(git -C "$REPO" status --porcelain)" ] && ok "ⓑ 한 커밋 · 작업 트리 깨끗" || bad "ⓑ 커밋 수/미커밋: $(git -C "$REPO" status --porcelain | head -3)"
tm="$(cat "$REPO/design/TEAMS.md")"
has "$tm" '| new | `design/teams/new/` | byz-new-master-claude | 현역 |' "ⓑ TEAMS.md 행"; hasnt "$tm" '| old |' "  └ 옛 행 0"
has "$tm" "- 옛 이름 old → new(개명 " "ⓑ TEAMS.md 각주 1줄"; has "$tm" '| other | `design/teams/other/` | byz-other-master-claude' "  └ 다른 팀 행 그대로"
has "$(cat "$REPO/design/TEAMSET.md")" "| new | 3 |" "ⓑ TEAMSET.md 행"
c1="$(cat "$REPO/design/teams/new/indices/진행/c1.md")"
has "$c1" "design/teams/new/README.md · 담당 byz-new-master-claude#1" "ⓑ 본문 치환 패턴 2(폴더 경로 · 좌석 접두)"; has "$c1" "기능 이름 old 팀 화면" "ⓑ 그 밖 글자 0 변경(«old 팀 화면» 그대로)"
has "$(cat "$REPO/design/teams/other/indices/진행/o1.md")" "design/teams/old/README.md (다른 팀 이력" "ⓑ 다른 팀 문서 치환 0"
[ -f "$REPO/.fable-team/seats-new.json" ] && [ ! -e "$REPO/.fable-team/seats-old.json" ] && ls "$REPO/.fable-team/" | grep -q '^seats-old.json.bak-rename-' && ok "ⓑ 명부 seats-old.json → seats-new.json + .bak-rename-<ts>" || bad "ⓑ 명부 rename: $(ls "$REPO/.fable-team")"
python3 -I - "$REPO/.fable-team/seats-new.json" <<'PY' && ok "ⓑ 명부 칸(_name·_label·_tree 새 꼴·_doc·_renamed_from) · 행 이름·_master 불변 · 받은 행 새 경로 · 못 받은(wt1) 행 _move_pending" || bad "ⓑ 명부 내용"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["_name"] == "Seatbelt-NEW" and d["_label"] == "new", (d["_name"], d["_label"])
assert d["_tree"] == "design/teams/new/STATE.md" and d["_cards"] == "design/teams/new/indices", (d["_tree"], d["_cards"])
assert d["_doc"] == "new 팀 레지스트리 · 카드 = design/teams/new/indices · env = .fable-team/bin-new/new-env.sh · 틱 = com.byz.ft-tick-new", d["_doc"]
assert d["_renamed_from"] == "old" and d["_renamed_at"], d
assert d["_master"] == "byz-old-master-claude#1", d["_master"]
assert {k for k in d if not k.startswith("_")} == {"byz-old-master-claude#0", "byz-old-master-claude#1", "byz-old-nano-w#0"}, list(d)
assert d["byz-old-master-claude#1"]["index"] == "design/teams/new/indices/진행/c1.md" and d["byz-old-master-claude#1"]["_replaces"] == ["byz-old-master-claude#0"]
w = d["byz-old-nano-w#0"]
assert w["index"] == "design/teams/old/indices/진행/c1.md" and w["_move_pending"] == "design/teams/new/", w
PY
envf="$REPO/.fable-team/bin-new/new-env.sh"
[ -f "$envf" ] && [ ! -e "$REPO/.fable-team/bin-old" ] && [ -f "$REPO/.fable-team/bin-new/goal-lines-new.txt" ] && [ -f "$REPO/.fable-team/bin-new/ft-tick-new.plist" ] && ok "ⓑ env bin-old/ → bin-new/ · 파일 이름 3 바뀜" || bad "ⓑ env 폴더: $(ls "$REPO/.fable-team")"
[ -x "$envf" ] && ok "  └ 실행 권한 유지" || bad "  └ 실행 권한 잃음"
e="$(cat "$envf")"
for want in "seats-new.json" "FT_NANO_PREFIX=byz-new-nano-" "FT_NANO_WT_PREFIX=new-" "@zc_new_active" "FT_NANO_LEDGER=design/teams/new/NANO-LEDGER-old.md" "bin-new/goal-lines-new.txt" "# new 팀 값" "/.worktrees/old-main"; do has "$e" "$want" "ⓑ env 값: $want"; done
has "$(cat "$REPO/.fable-team/bin-new/ft-tick-new.plist")" "com.byz.ft-tick-new</string><string>/tmp/ft-tick-new.log" "ⓑ env plist 라벨·로그"
has "$(cat "$REPO/.fable-team/state/nano-card-base/byz-old-nano-a#0.json")" '"card_path": "design/teams/new/indices/진행/c1.md"' "ⓑ nano-card-base card_path"
has "$(cat "$REPO/.worktrees/wt1/.worktree-info.json")" "design/teams/old/indices" "ⓑ 미전환 워크트리 worktree-info 옛 경로 유지"
has "$(cat "$REPO/.baton/branches.json")" "design/teams/new/ 정리" "ⓑ baton 재작성"
has "$out" "AFTER 옛 자리 잔여 0" "ⓑ AFTER 줄 — 옛 폴더·명부·env 잔여 0"
GITC "$REPO/.worktrees/wt1" merge -q --ff-only main && ok "ⓑ wt1 이 개명 커밋을 받음(head-sync 모사)" || bad "ⓑ wt1 merge"
out="$(TR --apply old new)"; rc=$?
[ "$rc" = 0 ] && has "$out" "RESYNC old → new" "ⓑ 같은 명령 다시 = RESYNC rc0" || bad "ⓑ resync rc=$rc ← ${out:0:500}"
has "$(cat "$REPO/.fable-team/seats-new.json")" '"byz-old-nano-w#0": {' "  └ 행 이름 그대로"
python3 -I -c 'import json,sys;w=json.load(open(sys.argv[1]))["byz-old-nano-w#0"];assert w["index"]=="design/teams/new/indices/진행/c1.md" and "_move_pending" not in w,w' "$REPO/.fable-team/seats-new.json" && ok "ⓑ RESYNC 뒤 wt1 행 새 경로 · _move_pending 제거" || bad "ⓑ RESYNC 명부"
has "$(cat "$REPO/.worktrees/wt1/.worktree-info.json")" "design/teams/new/indices" "ⓑ RESYNC 뒤 worktree-info 재작성"
SNAP2="$(printf '%s\n' "$out" | sed -n 's/^SNAPSHOT //p' | tail -1)"

echo "== ⓒ --verify new"
out="$(TR --verify new)"; rc=$?
[ "$rc" = 0 ] && has "$out" "VERIFY ERR=0" "ⓒ verify ERR 0 rc0" || bad "ⓒ verify rc=$rc ← ${out: -900}"
has "$out" "WARN 잔여 «old»: design/teams/new/indices/진행/c1.md:3" "ⓒ 잔여 «old» 글자 WARN 목록(카드 본문)"
has "$out" "WARN 잔여 «old»: .fable-team/bin-new/new-env.sh:" "  └ env 잔여(워크트리 이름 old-main · 보존 대상) WARN"
has "$out" "다른 문서 1파일이 design/teams/old/ 경로 글자를 가짐" "  └ 다른 팀 이력 문서 1줄 요약"
hasnt "$out" "TEAMS.md:" "  └ 각주 줄은 WARN 제외"; hasnt "$out" "seats-new.json:_master" "  └ 옛 좌석 이름(_master) WARN 제외"
mv "$REPO/.fable-team/seats-new.json" "$T/keep.json"; printf '{}' > "$REPO/.fable-team/seats-old.json"
out="$(TR --verify new)"; rc=$?
[ "$rc" = 0 ] && has "$out" "_renamed_from 없음" "ⓒ 개명 기록 없는 명부 = WARN(검사 생략 표시)" || bad "ⓒ 기록 없음 rc=$rc ← ${out: -400}"
rm -f "$REPO/.fable-team/seats-old.json"; mv "$T/keep.json" "$REPO/.fable-team/seats-new.json"; mkdir "$REPO/.fable-team/bin-old"
out="$(TR --verify new)"; rc=$?
[ "$rc" = 1 ] && has "$out" "ERR 옛 env 폴더 잔존" "ⓒ 변이: 옛 env 폴더 잔존 = ERR rc1" || bad "ⓒ 변이 rc=$rc ← ${out: -400}"
rmdir "$REPO/.fable-team/bin-old"

echo "== ⓓ --revert (RESYNC 스냅샷 → apply 스냅샷 순) → ⓐ 전 상태 cmp0"
GITC "$REPO/.worktrees/wt1" reset -q --hard "$HEAD0"
out="$(TR --revert "$SNAP2")"; rc=$?; [ "$rc" = 0 ] && has "$out" "REVERT-END" "ⓓ RESYNC 스냅샷 revert rc0" || bad "ⓓ resync revert rc=$rc ← ${out:0:500}"
out="$(TR --revert "$SNAP")"; rc=$?
[ "$rc" = 0 ] && has "$out" "REVERT-END" "ⓓ apply 스냅샷 revert rc0" || bad "ⓓ revert rc=$rc ← ${out:0:700}"
[ "$(manifest "$REPO")" = "$BEFORE" ] && ok "ⓓ revert 뒤 모든 파일·폴더 sha256 원본 동일(명부·env·저장 참조 포함 · .bak-rename 0)" || { bad "ⓓ revert 뒤 manifest 다름"; diff <(echo "$BEFORE") <(manifest "$REPO") | head -8; }
[ -z "$(git -C "$REPO" diff "$HEAD0" HEAD --stat)" ] && ok "ⓓ git revert 뒤 트리 = 원본 커밋 트리" || bad "ⓓ 트리 다름"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert all(i["revert_match"] is True for s in d["steps"] for i in s["items"]),d["steps"][0]["items"]' "$SNAP" && ok "ⓓ 스냅샷 7종 revert_match 전부 True" || bad "ⓓ revert_match"

echo "== ⓖ 옛 계보 우편 감시(watch) · ft-tick 배선"
cat > "$T/fake/mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = peek ] || exit 9
case "$2" in 'byz-old-master-claude#1') echo "pending=2 scanned=1 lineage=$2";; *) echo "pending=0 scanned=1 lineage=$2";; esac
EOF
chmod +x "$T/fake/mbox.sh"
W="$T/w"; mkdir -p "$W"; TODAY="$(date +%F)"; OLD8="$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=8))')"
printf '{"_renamed_from":"old","_renamed_at":"%s","_master":"byz-new-master-claude#2","byz-old-master-claude#0":{},"byz-old-master-claude#1":{},"byz-old-arch-claude#3":{},"byz-new-master-claude#2":{}}\n' "$TODAY" > "$W/seats-new.json"
printf '{"_renamed_from":"old2","_renamed_at":"%s","_master":"m","byz-old2-master-claude#1":{}}\n' "$OLD8" > "$W/seats-gone.json"
printf '{"_master":"x","byz-x-master-claude#1":{}}\n' > "$W/seats-x.json"
out="$(python3 -I "$SRC/ft_team_rename.py" watch "$T/fake/mbox.sh" "$W/seats-new.json" "$W/seats-gone.json" "$W/seats-x.json" "$W/seats-new.json" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$(printf 'PENDING\tbyz-new-master-claude#2\tbyz-old-master-claude#1\t2\told\tnew')" ] \
  && ok "ⓖ watch: 7일 안 명부의 옛 계보(최신 번호 좌석)만 peek · pending>0 1줄 · 8일 지난 명부·개명 없는 명부·중복 0" || bad "ⓖ watch rc=$rc ← $out"
tk="$(cat "$SRC/ft-tick.sh")"
has "$tk" $'  raised_watch\n  renamed_watch' "ⓖ ft-tick pass() 가 renamed_watch 를 부른다"; has "$tk" 'FT_TICK_RENAMED_SEC:-3600' "  └ 1시간 간격"; has "$tk" 'renamed.sig' "  └ 중복 억제 서명"
tsv="$(grep -v '^#' "$SRC/team-tick-env.tsv")"
[ "$(printf '%s\n' "$tsv" | grep -c FT_TICK_RENAMED)" = "$(printf '%s\n' "$tsv" | grep -c .)" ] && ok "ⓖ 팀 틱 표 전 행 = RENAMED 끔(전 명부 스캔은 메인 틱 1개)" || bad "ⓖ 팀 틱 표 RENAMED"
has "$tsv" $'chatbot\tseats-chatbot.json\t/tmp/ft-tick-state-chatbot' "ⓖ 키트 틱 표 concierge → chatbot 행"; hasnt "$tsv" concierge "  └ concierge 행 0"
hasnt "$(grep -nE "\b($((6*100))|$((3*100)))\b" "$SRC/ft_team_rename.py" "$SRC/ft-team-rename.sh" || true)" ":" "ⓖ 이름 바꾸기 도구에 600/300 숫자 0"

echo "== fail=$fail"; [ "$fail" = 0 ]
