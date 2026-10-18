#!/usr/bin/env bash
# test_team_move_roundtrip.sh — R382 팀 폴더 이동 «코드 선행» 격리 시험 (카드 시험 입력 ⓐ~ⓔ · ⓕ 는 FT_TMR_RUN_EXISTING=1 일 때만 기존 3종을 돌린다)
#   ⓐ 픽스처 리포(13팀 3꼴·명부 2·nano-card-base·worktree-info·baton·카드·README 지도)에서 --plan --all → --apply --all → --verify ERR 0 → --revert → 원본과 sha256 동일
#   ⓑ 미전환 워크트리 섞임: `_move_pending` 표식·옛 index 유지·head-sync 뒤 재맞춤 · ft-nano-close 가 쌍둥이 후보로 카드를 찾음(lib 빼면 REJECT = 변이 대조)
#   ⓒ ft_team_root 세 꼴 13팀 집합 동일 · ⓓ LIVE_ROOT 파일(LIVE_BIN 위치를 바꿔도 같은 원장 · 없음 = ERROR rc1) · ⓔ 조립 하드코딩 린트 0
# 임시 폴더·가짜 tmux·가짜 lsof 만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"; KIT="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:350}";; *) ok "$3";; esac; }

echo "== 0 문법 · 키트 사본 cmp0"
for f in ft-team-lib.sh ft-team-move.sh ft-team-path-lint.sh; do bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"; done
for f in ft_team_move.py ft_team_move_apply.py; do python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/$f" && ok "ast $f" || bad "ast $f"; done
for f in ft-team-lib.sh ft-team-move.sh ft_team_move.py ft_team_move_apply.py ft-team-path-lint.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"; done

mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "${FAKE_PANES:-/nonexistent}" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
esac
EOF
cat > "$T/fake/lsof" <<'EOF'
#!/usr/bin/env bash
# lsof -nP -Fpcn 모사 — FAKE_LSOF 각 줄 "<명령> <pid> <열린 경로>" 를 p/c/n 레코드로
printf 'p1\ncfake\nn/dev/null\n'
[ -s "${FAKE_LSOF:-/nonexistent}" ] && while read -r c p n; do printf 'p%s\nc%s\nn%s\n' "$p" "$c" "$n"; done < "$FAKE_LSOF"
exit 0
EOF
chmod +x "$T/fake/tmux" "$T/fake/lsof"
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
TEAMS13=(harness planner cfo ops graphics issues feature kk v65 loom lecture room concierge)
FORM1=(harness planner cfo ops graphics issues feature kk v65); FORM2=(loom lecture); FORM3=(room concierge)
mkteam() {  # <폴더> <팀> <카드 이름|"">  — README 지도 + indices/ (+ 카드 1장)
  mkdir -p "$1/indices/진행"; : > "$1/indices/.gitkeep"
  printf '# %s\n정본 위치: design/%s/README.md\n## 파일 지도\n| 경로 | 뜻 |\n|---|---|\n| `README.md` | 지도 |\n| `indices/` | 카드 |\n' "$2" "$2" > "$1/README.md"
  [ -z "${3:-}" ] || printf '# 카드 %s\n- 근거: design/%s/README.md\n' "$3" "$2" > "$1/indices/진행/$3.md"
}
mkrepo() {  # <리포 경로> <팀형식표: "팀=꼴" 공백구분>
  local R="$1" spec="$2" t form; mkdir -p "$R/design" "$R/.fable-team/state/nano-card-base" "$R/.baton" "$R/.worktrees"
  git -C "$R" init -q -b main
  { printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'
    for kv in $spec; do t="${kv%%=*}"; form="${kv##*=}"
      case "$form" in 1) p="design/$t/";; 2) p="design/teams/$t/";; 3) p='$FT_HARNESS_ROOT/design/'"$t/";; esac
      printf '| %s | `%s` | byz-%s-master-claude | 현역 |\n' "$t" "$p" "$t"; done; } > "$R/design/TEAMS.md"
  { printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n'; for kv in $spec; do printf '| %s | 3 |\n' "${kv%%=*}"; done; } > "$R/design/TEAMSET.md"
  for kv in $spec; do t="${kv%%=*}"; form="${kv##*=}"; c=""; case "$t" in harness|v65|planner) c="$t-c1";; esac
    case "$form" in 1) mkteam "$R/design/$t" "$t" "$c";; 2) mkteam "$R/design/teams/$t" "$t" "$c";; 3) mkteam "$T/hroot/design/$t" "$t" "$c";; esac; done
  printf '.worktrees/\n.fable-team/\n.baton/\ndesign/harness/scratch/\n' > "$R/.gitignore"
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init
}
SPEC13=""; for t in "${FORM1[@]}"; do SPEC13="$SPEC13 $t=1"; done; for t in "${FORM2[@]}"; do SPEC13="$SPEC13 $t=2"; done; for t in "${FORM3[@]}"; do SPEC13="$SPEC13 $t=3"; done
REPO="$T/repo"; mkdir -p "$T/hroot"; mkrepo "$REPO" "$SPEC13"
GITC "$REPO" worktree add -q "$REPO/.worktrees/wt1" -b nano/wt1
printf '{"branch":"nano/wt1","purpose":"design/harness/indices/진행/harness-c1.md"}' > "$REPO/.worktrees/wt1/.worktree-info.json"
printf '{\n  "_name": "SB",\n  "_cards": "design/harness/indices",\n  "_tree": "design/harness/STATE.md",\n  "byz-harness-nano-a#0": {"role": "nano", "index": "design/harness/indices/진행/harness-c1.md"},\n  "byz-harness-nano-wt#0": {"role": "nano", "worktree": "wt1", "index": "design/harness/indices/진행/harness-c1.md"}\n}\n' > "$REPO/.fable-team/seats-harness.json"
printf '{\n  "_name": "V65",\n  "ft-v65-temp-a#0": {"role": "nano", "index": "design/v65/indices/진행/v65-c1.md"}\n}\n' > "$REPO/.fable-team/seats.json"
printf '{\n  "name": "byz-harness-nano-a#0",\n  "card_path": "design/harness/indices/진행/harness-c1.md",\n  "worktree": "%s",\n  "branch": "nano/a"\n}\n' "$REPO" > "$REPO/.fable-team/state/nano-card-base/byz-harness-nano-a#0.json"
printf '[{"child_branch":"nano/wt1","child_worktree":".worktrees/wt1","purpose":"design/harness/ 정리"}]\n' > "$REPO/.baton/branches.json"
manifest() { (cd "$1" && find . -type f ! -path './.git/*' ! -name .git ! -path './.fable-team/state/team-move/*' -print0 | sort -z | xargs -0 shasum -a 256); }
TM() { FT_REPO_ROOT="$REPO" FT_PROJECT_ROOT="$REPO" FT_HARNESS_ROOT="$T/hroot" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_PANES="${FAKE_PANES:-}" FAKE_LSOF="${FAKE_LSOF:-}" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" "$@" 2>&1; }

echo "== ⓒ ft_team_root 세 꼴 13팀 집합 동일"
for form in 1 2 3; do S=""; for t in "${TEAMS13[@]}"; do S="$S $t=$form"; done; mkdir -p "$T/c$form"; mkrepo "$T/c$form" "$S" 2>/dev/null; done
set13="$(printf '%s\n' "${TEAMS13[@]}" | LC_ALL=C sort | tr '\n' ' ')"
for form in 1 2 3; do got="$(FT_REPO_ROOT="$T/c$form" bash -c '. "$1"; ft_team_names' _ "$SRC/ft-team-lib.sh" | LC_ALL=C sort | tr '\n' ' ')"; [ "$got" = "$set13" ] && ok "ⓒ 꼴$form 팀 이름 13 == 기준 집합" || bad "ⓒ 꼴$form: $got"; done
r1="$(FT_REPO_ROOT="$T/c1" bash -c '. "$1"; ft_team_root harness; ft_team_root harness --alt' _ "$SRC/ft-team-lib.sh" | tr '\n' ' ')"
[ "$r1" = "$T/c1/design/harness $T/c1/design/teams/harness " ] && ok "ⓒ 꼴1 root=design/<t> · --alt=design/teams/<t>" || bad "ⓒ 꼴1 root/alt: $r1"
r2="$(FT_REPO_ROOT="$T/c2" bash -c '. "$1"; ft_team_root harness; ft_team_root harness --alt' _ "$SRC/ft-team-lib.sh" | tr '\n' ' ')"
[ "$r2" = "$T/c2/design/teams/harness $T/c2/design/harness " ] && ok "ⓒ 꼴2 root=design/teams/<t> · --alt=design/<t>" || bad "ⓒ 꼴2 root/alt: $r2"
r3="$(FT_REPO_ROOT="$T/c3" FT_HARNESS_ROOT="$T/hroot" bash -c '. "$1"; ft_team_root harness' _ "$SRC/ft-team-lib.sh")"
[ "$r3" = "$T/hroot/design/harness" ] && ok "ⓒ 꼴3 root=\$FT_HARNESS_ROOT/design/<t>" || bad "ⓒ 꼴3 root: $r3"
out="$(FT_REPO_ROOT="$T/c3" bash -c 'unset FT_HARNESS_ROOT; . "$1"; ft_team_root harness; echo rc=$?' _ "$SRC/ft-team-lib.sh" 2>&1)"
has "$out" "ERROR" "ⓒ 꼴3 env 없음 = ERROR(옛 경로 후퇴 0)"; has "$out" "rc=1" "  └ rc=1"
out="$(FT_REPO_ROOT="$T/c1" bash -c '. "$1"; ft_team_root zz; echo rc=$?' _ "$SRC/ft-team-lib.sh" 2>&1)"; has "$out" "rc=1" "ⓒ 명단에 없는 팀 → rc1"

echo "== ⓐ plan → apply → verify → revert (13팀 · 3꼴 · 저장 참조 7종)"
mkdir -p "$T/home"; printf "# BOOT\nharness 지도 design/harness/README.md · planner design/planner/README.md\n" > "$T/home/BOOT.md"; printf "# GUIDE\ndesign/cfo/README.md\n" > "$T/home/GUIDE.md"
export FT_TEAM_MOVE_EXTRA="$T/home/BOOT.md:$T/home/GUIDE.md"; EXTRA0="$(shasum -a 256 "$T/home/BOOT.md" "$T/home/GUIDE.md")"
BEFORE="$(manifest "$REPO")"; HEAD0="$(git -C "$REPO" rev-parse HEAD)"
out="$(TM --plan --all)"; rc=$?
[ "$rc" = 0 ] && has "$out" "PLAN-END blockers=0" "ⓐ plan --all rc0 · blockers=0" || bad "ⓐ plan rc=$rc ← ${out:0:400}"
[ "$(printf '%s\n' "$out" | grep -c '^PLAN ')" = 9 ] && ok "ⓐ 이동 대상 9팀(꼴1)" || bad "ⓐ PLAN 줄 수: $(printf '%s\n' "$out" | grep -c '^PLAN ')"
[ "$(printf '%s\n' "$out" | grep -c '^SKIP ')" = 4 ] && ok "ⓐ SKIP 4팀(꼴2·꼴3)" || bad "ⓐ SKIP 줄 수"
has "$out" "REF1 팀 폴더" "ⓐ 7종 REF1"; has "$out" "REF2 TEAMS.md" "  └ REF2"; has "$out" "REF3 명부" "  └ REF3"; has "$out" "REF4 nano-card-base" "  └ REF4"; has "$out" "REF5 worktree-info" "  └ REF5"; has "$out" "REF6 baton" "  └ REF6"; has "$out" "REF7 텍스트" "  └ REF7"
has "$out" "WT wt1 미전환" "ⓐ 워크트리 wt1 = 미전환 후보로 표시"
[ "$(manifest "$REPO")" = "$BEFORE" ] && ok "ⓐ plan 은 쓰기 0(manifest 동일)" || bad "ⓐ plan 이 파일을 바꿨다"
printf 'byz-harness-master-claude#1\t%s/design/harness\n' "$REPO" > "$T/panes"; printf 'vim 4242 %s/design/harness/README.md\n' "$REPO" > "$T/lsof"
out="$(FAKE_PANES="$T/panes" FAKE_LSOF="$T/lsof" TM --plan harness)"
has "$out" "CWD byz-harness-master-claude#1" "ⓐ 점유: tmux pane cwd 가 표에 나온다"; has "$out" "LSOF vim pid=4242" "  └ lsof 점유도 표에"; hasnt "$out" "blockers=0" "  └ blockers>0"
out="$(FAKE_PANES="$T/panes" TM --apply harness)"; rc=$?
[ "$rc" = 1 ] && has "$out" "REJECT 점유 중" "ⓐ 점유 중 apply → REJECT rc1" || bad "ⓐ 점유 apply rc=$rc ← ${out:0:350}"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD0" ] && [ "$(manifest "$REPO")" = "$BEFORE" ] && ok "  └ 점유 REJECT 는 쓰기 0(HEAD·manifest 동일)" || bad "  └ 점유 REJECT 인데 변경"

out="$(TM --apply --all)"; rc=$?
[ "$rc" = 0 ] && ok "ⓐ apply --all rc0" || bad "ⓐ apply rc=$rc ← ${out:0:700}"
SNAP="$(printf '%s\n' "$out" | sed -n 's/^SNAPSHOT //p' | tail -1)"; [ -f "$SNAP" ] && ok "ⓐ 스냅샷 파일 실재" || bad "ⓐ 스냅샷 없음: $SNAP"
[ -d "$REPO/design/teams/harness" ] && [ ! -d "$REPO/design/harness" ] && ok "ⓐ git mv: design/teams/harness 있고 design/harness 없음" || bad "ⓐ 폴더 이동 안 됨"
n=0; for t in "${FORM1[@]}"; do [ -d "$REPO/design/teams/$t" ] && n=$((n+1)); done; [ "$n" = 9 ] && ok "ⓐ 꼴1 9팀 전부 이동" || bad "ⓐ 이동 팀 수 $n"
[ "$(grep -c 'design/teams/' "$REPO/design/TEAMS.md")" = 11 ] && ok "ⓐ TEAMS.md 꼴2 행 11(기존 2 + 이동 9)" || bad "ⓐ TEAMS.md: $(grep -c 'design/teams/' "$REPO/design/TEAMS.md")"
has "$(cat "$REPO/design/teams/harness/README.md")" "design/teams/harness/README.md" "ⓐ README 본문 경로 재작성"
has "$(cat "$REPO/design/teams/harness/indices/진행/harness-c1.md")" "design/teams/harness/README.md" "ⓐ 카드 본문 경로 재작성"
has "$(cat "$REPO/.gitignore")" "design/teams/harness/scratch/" "ⓐ .gitignore 재작성"
[ "$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ')" = 0 ] && ok "ⓐ 이동 뒤 작업 트리 깨끗(커밋됨)" || bad "ⓐ 미커밋 변경: $(git -C "$REPO" status --porcelain | head -3)"
ros="$(cat "$REPO/.fable-team/seats-harness.json")"
has "$ros" '"index": "design/teams/harness/indices/진행/harness-c1.md"' "ⓐ 명부: 받은 좌석(ROOT) index 재작성"
has "$ros" '"_move_pending"' "ⓐ 명부: 미전환 워크트리(wt1) 좌석 = _move_pending 표식"
has "$ros" '"_tree": "design/teams/harness/STATE.md"' "ⓐ 명부 _tree 재작성"
has "$(cat "$REPO/.fable-team/seats.json")" "design/teams/v65/indices/진행/v65-c1.md" "ⓐ v65 명부(seats.json) 재작성"
has "$(cat "$REPO/.fable-team/state/nano-card-base/byz-harness-nano-a#0.json")" "design/teams/harness/indices/진행/harness-c1.md" "ⓐ nano-card-base card_path 재작성"
has "$(cat "$REPO/.worktrees/wt1/.worktree-info.json")" "design/harness/indices" "ⓐ 미전환 워크트리 worktree-info 는 옛 경로 유지"
has "$(cat "$REPO/.baton/branches.json")" "design/teams/harness/ 정리" "ⓐ baton branches.json 재작성"
out="$(TM --verify --all)"; rc=$?
[ "$rc" = 0 ] && has "$out" "VERIFY ERR=0" "ⓐ verify --all ERR 0 rc0" || bad "ⓐ verify rc=$rc ← ${out: -900}"
out="$(TM --revert "$SNAP")"; rc=$?
[ "$rc" = 0 ] && has "$out" "REVERT-END" "ⓐ revert rc0" || bad "ⓐ revert rc=$rc ← ${out:0:500}"
[ "$(manifest "$REPO")" = "$BEFORE" ] && ok "ⓐ revert 뒤 모든 파일 sha256 이 원본과 동일(저장 참조 포함)" || { bad "ⓐ revert 뒤 manifest 다름"; diff <(echo "$BEFORE") <(manifest "$REPO") | head -6; }
[ -d "$REPO/design/harness" ] && [ ! -d "$REPO/design/teams/harness" ] && ok "ⓐ revert 뒤 design/harness 복귀" || bad "ⓐ revert 폴더"
[ "$(shasum -a 256 "$T/home/BOOT.md" "$T/home/GUIDE.md")" = "$EXTRA0" ] && ok "ⓐ revert 뒤 홈 BOOT/GUIDE(추가 파일)도 원본 sha256" || bad "ⓐ 홈 BOOT/GUIDE 복원 안 됨"
python3 -I - "$SNAP" <<'PYEOF' && ok "ⓐ 스냅샷 7종 × 3칸(before_sha·after_sha·revert_match) 실재 · revert 가 대조 결과를 기록(전부 bool True)" || bad "ⓐ 스냅샷 7종×3칸 검사"
import json, sys
KINDS = {"roster", "nano_card_base", "worktree_info", "baton", "card_body", "readme_map", "home_boot_guide"}
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["steps"], "steps 없음"
changed = {}
for st in d["steps"]:
    items = {i["kind"]: i for i in st["items"]}
    assert set(items) == KINDS, (st["team"], sorted(items))            # 빠진 종류 0
    for k, i in items.items():
        for c in ("before_sha", "after_sha", "revert_match"):
            assert c in i, (st["team"], k, c)                          # 3칸 실재
        assert i["state"] in ("changed", "tracked", "unchanged"), i
        assert i["revert_match"] is True, (st["team"], k, i)           # revert 뒤 대조 결과 = bool True
        if i["state"] == "unchanged":
            assert i["before_sha"] is None and i["after_sha"] is None, i
        else:
            assert i["before_sha"] and i["after_sha"] and i["before_sha"] != i["after_sha"], (st["team"], k, i)
            changed.setdefault(st["team"], set()).add(k)
        if i["state"] == "tracked":
            assert st["commit"] and all(f["commit"] == st["commit"] for f in i["files"]), (st["team"], k)
h = changed["harness"]
assert {"roster", "nano_card_base", "baton", "card_body", "readme_map", "home_boot_guide"} <= h, h
assert {i["kind"]: i["state"] for i in next(s for s in d["steps"] if s["team"] == "harness")["items"]}["card_body"] == "tracked"
PYEOF

echo "== ⓑ 미전환 워크트리 섞임 · head-sync 뒤 재맞춤"
R2="$T/repo2"; mkrepo "$R2" "planner=1 harness=1 cfo=3"
GITC "$R2" worktree add -q "$R2/.worktrees/wt-old" -b nano/old
printf '{"branch":"nano/old","purpose":"design/planner/indices/진행/planner-c1.md"}' > "$R2/.worktrees/wt-old/.worktree-info.json"
printf '{\n  "_name": "P",\n  "byz-planner-nano-r#0": {"role": "nano", "index": "design/planner/indices/진행/planner-c1.md"},\n  "byz-planner-nano-o#0": {"role": "nano", "worktree": "wt-old", "index": "design/planner/indices/진행/planner-c1.md"}\n}\n' > "$R2/.fable-team/seats-planner.json"
TM2() { FT_REPO_ROOT="$R2" FT_PROJECT_ROOT="$R2" FT_HARNESS_ROOT="$T/hroot" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" "$@" 2>&1; }
out="$(TM2 --apply planner)"; rc=$?; [ "$rc" = 0 ] && ok "ⓑ apply planner rc0" || bad "ⓑ apply rc=$rc ← ${out:0:400}"
python3 - "$R2/.fable-team/seats-planner.json" <<'PY' && ok "ⓑ 명부: ROOT 좌석 index=teams 꼴 · wt-old 좌석 index=옛 꼴 + _move_pending" || bad "ⓑ 명부 내용"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
r, o = d["byz-planner-nano-r#0"], d["byz-planner-nano-o#0"]
assert r["index"].startswith("design/teams/planner/") and "_move_pending" not in r, r
assert o["index"].startswith("design/planner/") and o.get("_move_pending") == "design/teams/planner/", o
PY
has "$(TM2 --verify planner)" "VERIFY ERR=0" "ⓑ 미전환 섞인 상태에서도 verify ERR 0(옛 index 가 wt-old 에 실재)"
GITC "$R2/.worktrees/wt-old" merge -q --ff-only main && ok "ⓑ wt-old 가 이동 커밋을 받음(head-sync 모사)" || bad "ⓑ wt-old merge"
out="$(TM2 --apply planner)"; rc=$?
[ "$rc" = 0 ] && has "$out" "RESYNC planner" "ⓑ 같은 팀 --apply 다시 = RESYNC(저장 참조만 · git 변경 0)" || bad "ⓑ resync rc=$rc ← ${out: -900}"
python3 - "$R2/.fable-team/seats-planner.json" <<'PY' && ok "ⓑ 재맞춤 뒤 wt-old 좌석 = teams 꼴 · _move_pending 제거" || bad "ⓑ 재맞춤 명부"
import json, sys
o = json.load(open(sys.argv[1], encoding="utf-8"))["byz-planner-nano-o#0"]
assert o["index"].startswith("design/teams/planner/") and "_move_pending" not in o, o
PY
has "$(cat "$R2/.worktrees/wt-old/.worktree-info.json")" "design/teams/planner/" "ⓑ 받은 뒤 wt-old worktree-info 재작성"
has "$(TM2 --verify planner)" "VERIFY ERR=0" "ⓑ 재맞춤 뒤 verify ERR 0"

echo "== ⓖ 7초 룰 — --sync-worktrees 는 배치 공통 deadline 70초 · 초과/실패 = PARTIAL rc3 (DA⑥ Q5)"
cat > "$T/sync_case.py" <<'PYEOF'
import glob, json, os, subprocess, sys
sys.path.insert(0, sys.argv[1]); cap = float(sys.argv[2])
import ft_team_move as m, ft_team_move_apply as ap
clock, calls = [0.0], []
ap.time.monotonic = lambda: clock[0]          # 가짜 시계 — 실제로 기다리지 않는다
ap.sync_cap = lambda ctx: cap
real = ap.run
def fake(*cmd, **kw):
    if len(cmd) > 1 and str(cmd[1]).endswith("fake-head-sync"):
        calls.append(kw["timeout"])
        if len(calls) == 1:
            clock[0] += kw["timeout"]; return subprocess.CompletedProcess(list(cmd), 0, "OK\n", "")
        clock[0] += kw["timeout"]; raise subprocess.TimeoutExpired(list(cmd), kw["timeout"])   # DA 모의 주입
    return real(*cmd, **kw)
ap.run = fake
rc = ap.main(["--apply", "--all", "--sync-worktrees"], m.make_ctx())
snap = json.load(open(sorted(glob.glob(os.environ["FT_TEAM_MOVE_STATE"] + "/*/snapshot.json"))[-1], encoding="utf-8"))
print("RESULT " + json.dumps({"rc": rc, "calls": calls, "pending": snap["pending_teams"]}))
PYEOF
sync_repo() {  # <리포> — planner(먼저) · ops(나중) 두 팀
  mkrepo "$1" "planner=1 ops=1"
  printf '{\n  "_name": "O",\n  "byz-ops-nano-x#0": {"role": "nano", "index": "design/ops/README.md"}\n}\n' > "$1/.fable-team/seats-ops.json"
  printf '{\n  "_name": "P",\n  "byz-planner-nano-x#0": {"role": "nano", "index": "design/planner/README.md"}\n}\n' > "$1/.fable-team/seats-planner.json"
}
sync_case() {  # <리포> <cap>
  FT_REPO_ROOT="$1" FT_PROJECT_ROOT="$1" FT_HARNESS_ROOT="$T/hroot" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FT_TEAM_MOVE_STATE="$1/.fable-team/state/team-move" FT_HEAD_SYNC="$T/fake/fake-head-sync" \
    PATH="$T/fake:$PATH" python3 -I "$T/sync_case.py" "$SRC" "$2" 2>&1
}
R4="$T/repo4"; sync_repo "$R4"
out="$(sync_case "$R4" 60)"; res="$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')"
python3 -I -c 'import json,sys;r=json.loads(sys.argv[1]);assert r["rc"]==3,r;assert r["calls"]==[60.0,10.0],r;assert sum(r["calls"])<=70,r;assert r["pending"]==["ops"],r' "$res" \
  && ok "ⓖ 두 팀 모의 주입: rc3 · 호출 상한 [60,10] 합 70 ≤ 70(팀 루프가 잔여 시간을 차감) · pending_teams=[ops] ← $res" || bad "ⓖ 공통 deadline: ${out: -500}"
has "$out" "PARTIAL ops" "ⓖ PARTIAL 줄(비정상 반환을 출력만 하지 않는다)"
has "$(cat "$R4/.fable-team/seats-ops.json")" "design/ops/README.md" "ⓖ ops 저장 참조는 쓰기 전에 멈춤(옛 경로 그대로)"
has "$(cat "$R4/.fable-team/seats-planner.json")" "design/teams/planner/README.md" "ⓖ 먼저 끝난 planner 는 저장 참조 재작성 완료"
has "$(git -C "$R4" log --format=%s)" "팀 폴더 이동 ops" "ⓖ 완료된 팀 커밋 보존(ops 이동 커밋 실재)"
TM4() { FT_REPO_ROOT="$R4" FT_PROJECT_ROOT="$R4" FT_HARNESS_ROOT="$T/hroot" FT_TEAM_MOVE_LSOF="$T/fake/lsof" PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" "$@" 2>&1; }
out="$(TM4 --apply ops)"; rc=$?
[ "$rc" = 0 ] && has "$out" "RESYNC ops" "ⓖ 다음 --apply = RESYNC 로 이어감 rc0" || bad "ⓖ resync rc=$rc ← ${out:0:300}"
has "$(cat "$R4/.fable-team/seats-ops.json")" "design/teams/ops/README.md" "  └ RESYNC 뒤 ops 명부 새 경로"
R5="$T/repo5"; sync_repo "$R5"
out="$(sync_case "$R5" 70)"; res="$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')"
python3 -I -c 'import json,sys;r=json.loads(sys.argv[1]);assert r["rc"]==3,r;assert r["calls"]==[70.0],r;assert r["pending"]==["ops"],r' "$res" \
  && ok "ⓖ 첫 팀이 70초를 다 쓰면 둘째 팀은 점유 스냅샷·helper 를 부르지 않고 이동 «전» 에 중단(남은 0) · rc3 · pending=[ops] (R382d: 마감 소진 = 이동 0)" || bad "ⓖ 잔여 0: ${out: -500}"
has "$out" "PARTIAL ops 배치 총 마감" "ⓖ 잔여 0: 이동 전 PARTIAL 줄"
[ -d "$R5/design/ops" ] && [ ! -d "$R5/design/teams/ops" ] && ok "ⓖ 잔여 0: ops 는 옮기지 않음(옛 폴더 그대로)" || bad "ⓖ 잔여 0: ops 가 옮겨졌다"
has "$(grep -c 'timeout: float = 7' "$SRC/ft_team_move.py")" "1" "ⓖ 기본 helper timeout = 7(기준 단위)"
hasnt "$(grep -nE "\b($((6*100))|$((3*100)))\b" "$SRC/ft_team_move.py" "$SRC/ft_team_move_apply.py" "$SRC/ft-team-move.sh" || true)" ":" "ⓖ 이동 도구에 600/300 숫자 0"

echo "== ⓑ' ft-nano-close 가 쌍둥이 후보로 카드를 찾는다(lib 빼면 REJECT = 변이 대조)"
R3="$T/r3"; mkdir -p "$R3/.fable-team" "$R3/design/teams/planner/indices/진행" "$T/comm/bodies" "$T/bin3" "$T/bin3b"
git -C "$R3" init -q -b main; GITC "$R3" commit -q --allow-empty -m init
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
for b in "$T/bin3" "$T/bin3b"; do
  cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$b/"
  printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$b/ft-nano-cherry-gate.sh"; chmod +x "$b/"*
done
cp "$SRC/ft-team-lib.sh" "$T/bin3/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
SEAT='byz-planner-nano-tw#0'; NW="$R3/.worktrees/cfo-tw"; BR="fix/tw"
GITC "$R3" worktree add -q "$NW" -b "$BR"; git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m work; SHA="$(git -C "$NW" rev-parse HEAD)"
printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$R3/design/teams/planner/indices/진행/tw.md"
printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/tw.md"}}\n' "$SEAT" > "$R3/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) case "$*" in *pane_current_path*) cat "$FAKE_PANE_CWDS";; *) cat "$FAKE_PANES";; esac;;\n  display-message) cat "$FAKE_CWD";;\n  has-session) exit 1;;\n  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;\nesac\n' > "$T/fake/tmux3"; mv "$T/fake/tmux3" "$T/fake/tmux"; chmod +x "$T/fake/tmux"
printf '%s|%%1\n' "$SEAT" > "$T/panes3"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pcwds3"; printf '%s' "$NW" > "$T/cwd3"
close3() { ( cd "$R3" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes3" FAKE_CWD="$T/cwd3" FAKE_PANE_CWDS="$T/pcwds3" FAKE_LOG="$T/tlog3" \
  FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$R3/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean3" \
  bash "$1/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR" 2>&1 ); }
out="$(close3 "$T/bin3b")"; rc=$?
[ "$rc" = 1 ] && has "$out" "⑥카드 못 찾음" "ⓑ' 변이: lib 없는 bin 은 옛 index 로 카드를 못 찾아 REJECT" || bad "ⓑ' 변이 대조 rc=$rc ← ${out:0:350}"
out="$(close3 "$T/bin3")"; rc=$?
[ "$rc" = 0 ] && has "$out" "CLOSED $SEAT" "ⓑ' lib 있는 bin = 쌍둥이 후보(design/teams/…)로 카드를 찾아 CLOSED" || bad "ⓑ' 쌍둥이 rc=$rc ← ${out:0:500}"

echo "== ⓓ LIVE_ROOT 파일 — LIVE_BIN 위치와 무관 · 없음 = ERROR rc1"
D="$T/d"; mkdir -p "$D/.fable-team" "$D/data" "$D/binA" "$D/binB"
cp "$SRC"/ft_goal_ledger.py "$D/binA/"; cp "$SRC"/ft_goal_ledger.py "$D/binB/"
lr() { env -i HOME="$HOME" FT_ROOT="$D" python3 -I -c 'import sys;sys.path.insert(0,sys.argv[1]);import ft_goal_ledger as g
try: print(g.live_root(RuntimeError))
except RuntimeError as e: print(e); sys.exit(1)' "$1" 2>&1; }
printf '%s\n' "$D/binA" > "$D/.fable-team/LIVE_BIN"; printf '%s\n' "$D/data" > "$D/.fable-team/LIVE_ROOT"
a="$(lr "$D/binA")"; printf '%s\n' "$D/binB" > "$D/.fable-team/LIVE_BIN"; b="$(lr "$D/binB")"
[ "$a" = "$D/data" ] && [ "$b" = "$D/data" ] && ok "ⓓ LIVE_BIN 위치(binA→binB)를 바꿔도 같은 데이터 루트" || bad "ⓓ a=$a b=$b"
rm -f "$D/.fable-team/LIVE_ROOT"; out="$(lr "$D/binA")"; rc=$?
[ "$rc" = 1 ] && has "$out" "LIVE_ROOT 이 없거나 무효" "ⓓ LIVE_ROOT 없음 = ERROR rc1(LIVE_BIN 에서 유도 0)" || bad "ⓓ 없음 rc=$rc $out"
has "$(grep -c 'from ft_goal_ledger import live_root' "$SRC/ft_news_ledger.py")" "1" "ⓓ 뉴스 원장이 같은 live_root 함수를 쓴다(고정 v6 경로 0)"
hasnt "$(cat "$SRC/ft_news_ledger.py")" '"v6-realtime-live"' "ⓓ 뉴스 원장 코드에 v6-realtime-live 고정 접미사 0"
has "$(grep -c 'FT_ROOT:-' "$SRC/ft-tick.sh")" "1" "ⓓ ft-tick ROOT 는 env FT_ROOT 우선(코드 위치 유도 0)"

echo "== ⓔ 조립 하드코딩 린트 0"
lint="$(cd "$SRC" && grep -nE 'design/\$\{?[A-Za-z_]+\}?/' -- *.sh *.py | wc -l | tr -d ' ')"; [ "$lint" = 0 ] && ok "ⓔ grep 'design/\$VAR/' *.sh *.py = 0 (fable-team-bin)" || bad "ⓔ 조립 하드코딩 $lint곳"
lint="$(cd "$KIT" && grep -nE 'design/\$\{?[A-Za-z_]+\}?/' -- *.sh *.py | wc -l | tr -d ' ')"; [ "$lint" = 0 ] && ok "ⓔ 키트 bin 도 0" || bad "ⓔ 키트 조립 하드코딩 $lint곳"
out="$(FT_REPO_ROOT="$R2" bash "$SRC/ft-team-path-lint.sh" "$SRC" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "$out" "OK 하드코딩 0" "ⓔ ft-team-path-lint.sh rc0" || bad "ⓔ lint rc=$rc $out"
mkdir -p "$T/lintbad"; printf 'x="$ROOT/design/$TEAM/a"\n' > "$T/lintbad/x.sh"; cp "$SRC/ft-team-lib.sh" "$SRC/ft-team-path-lint.sh" "$T/lintbad/"
out="$(FT_REPO_ROOT="$R2" bash "$T/lintbad/ft-team-path-lint.sh" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$out" "ERR 팀 경로 조립 하드코딩" "ⓔ 변이: 조립 한 줄 → ERR rc1" || bad "ⓔ 변이 rc=$rc $out"
rm -f "$T/lintbad/x.sh"; printf 'twin="$(ft_index_twin "$p")"\n' > "$T/lintbad/y.sh"
out="$(FT_REPO_ROOT="$T/c2" bash "$T/lintbad/ft-team-path-lint.sh" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$out" "쌍둥이 후보가 남았다" "ⓔ 전환 끝(전 팀 꼴2) + 쌍둥이 호출 잔존 → ERR rc1" || bad "ⓔ 전환 끝 rc=$rc $out"

if [ "${FT_TMR_RUN_EXISTING:-0}" = 1 ]; then
  echo "== ⓕ 기존 시험 3종 rc0"
  for t in test_nano_close_named_wt test_nano_team_env test_goal_table_gate; do bash "$HERE/$t.sh" > "$T/$t.out" 2>&1; rc=$?; [ "$rc" = 0 ] && ok "ⓕ $t rc0" || bad "ⓕ $t rc=$rc"; done
fi
echo "== fail=$fail"; [ "$fail" = 0 ]
