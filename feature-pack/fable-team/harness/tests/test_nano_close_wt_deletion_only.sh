#!/usr/bin/env bash
# test_nano_close_wt_deletion_only.sh — 카드 r-wt-clean-deletion-only: wt-clean 계획 ⑤(기본 경로)가 «삭제만 남은 워크트리»(tracked 가 전부 ` D`)를
# 실작업물로 세지 않는다. 임시 git 리포 + 가짜 tmux + 스텁 baton 만 쓴다 — 실제 리포·워크트리·baton·tmux 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-hil.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  ls) echo "no server running on /tmp/fake"; exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-del#0'; CARD="$REPO/design/planner/indices/진행/del.md"
NW="$REPO/.worktrees/cfo-del"; BR="nano/del-only"
PLAN="$T/wtclean/$SEAT.sh.hil"
# 계획이 부르는 baton 스텁 — 워크트리를 지우기만 한다(실 baton 0)
printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }

# fresh — 새 워크트리(파일 f1~f4 + .serena/project.yml 커밋) → 깨끗한 상태에서 close 로 계획 생성(.sh.hil)
fresh() {
  [ ! -d "$NW" ] || GIT worktree remove --force "$NW"
  GIT branch -D "$BR" >/dev/null 2>&1; GIT worktree add -q "$NW" -b "$BR"
  mkdir -p "$NW/.serena"; for f in f1 f2 f3 f4; do echo "$f" > "$NW/$f"; done
  if [ "${FRESH_SERENA_UNTRACKED:-0}" = 1 ]; then echo "k: v" > "$NW/.serena/other.yml"; else echo "name: x" > "$NW/.serena/project.yml"; fi   # untracked 변형: .serena 에 다른 추적 파일이 있어 '?? .serena/project.yml' 이 디렉터리로 안 접힌다
  git -C "$NW" add -A && git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "work"
  SHA="$(git -C "$NW" rev-parse HEAD)"
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/del.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
  out="$(run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
    FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR")"
  [ -f "$PLAN" ] || { bad "계획 생성 실패 ← ${out:0:300}"; return 1; }
}
# runplan — 계획 실행(스텁 baton). 결과 줄은 마지막 stdout.
runplan() { planout="$(cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" BATON_BIN="$T/fake/baton" /bin/bash "$PLAN" 2>&1)"; prc=$?; last="$(printf '%s' "$planout" | tail -1)"; }
rm3() { rm "$NW/f1" "$NW/f2" "$NW/f3"; }
branch_unmoved() { [ "$(git -C "$REPO" rev-parse "refs/heads/$BR")" = "$SHA" ] && ok "  └ 브랜치 tip 그대로(삭제 커밋 0 · [wip] 0)" || bad "브랜치 tip 이 움직임 — 삭제가 브랜치에 커밋됨"; }

echo "== ⓐ ' D' 3개만 → cleaned(삭제만 3파일 …)"
fresh && { rm3; runplan
  [ "$prc" -eq 0 ] && has "$last" "cleaned(삭제만 3파일" "ⓐ → cleaned(삭제만 3파일)" || bad "ⓐ rc=$prc ← ${planout:0:400}"
  has "$last" "복원 = git worktree add $NW $BR" "  └ 복원 안내(경로 · 브랜치)"
  [ ! -d "$NW" ] && ok "  └ 워크트리 정리됨" || bad "워크트리 남음"
  branch_unmoved
  has "$(cat "$T/ledger.md")" "wt=cleaned(삭제만 3파일" "  └ 원장 표식 wt=cleaned(삭제만 3파일 …)"; }

echo "== ⓑ ' D' 3개 + .serena/project.yml ' M' → 같음"
fresh && { rm3; echo "name: y" > "$NW/.serena/project.yml"; runplan
  [ "$prc" -eq 0 ] && has "$last" "cleaned(삭제만 3파일" "ⓑ → cleaned(삭제만 3파일)" || bad "ⓑ rc=$prc ← ${planout:0:400}"
  [ ! -d "$NW" ] && ok "  └ 워크트리 정리됨" || bad "워크트리 남음"
  branch_unmoved; }

echo "== ⓒ ' D' 3개 + 실 ' M' 1 → 지금처럼 멈춤(skipped:실작업물 미커밋 1파일)"
fresh && { rm3; echo changed >> "$NW/f4"; runplan
  [ "$prc" -eq 1 ] && has "$last" "skipped:실작업물 미커밋 1파일" "ⓒ → skipped(셈 = 실변경 줄 1)" || bad "ⓒ rc=$prc ← ${planout:0:400}"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"
  branch_unmoved; }

echo "== ⓓ ' D' 3개 + '??' 1 → 미커밋 1"
fresh && { rm3; echo new > "$NW/untracked.txt"; runplan
  [ "$prc" -eq 1 ] && has "$last" "skipped:실작업물 미커밋 1파일" "ⓓ → skipped 1파일" || bad "ⓓ rc=$prc ← ${planout:0:400}"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }

echo "== ⓔ 'D '(인덱스에 올린 삭제) 1 + ' D' 3 → 미커밋 1"
fresh && { rm3; git -C "$NW" rm -q f4; runplan
  [ "$prc" -eq 1 ] && has "$last" "skipped:실작업물 미커밋 1파일" "ⓔ → skipped 1파일(' D' 3 은 안 센다)" || bad "ⓔ rc=$prc ← ${planout:0:400}"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "워크트리가 사라짐"; }

echo "== ⓕ 삭제 없는 깨끗한 워크트리 → 기존 표식 그대로(cleaned · '삭제만' 문구 0)"
fresh && { runplan
  [ "$prc" -eq 0 ] && has "$last" "cleaned" "ⓕ → cleaned" || bad "ⓕ rc=$prc ← ${planout:0:400}"
  hasnt "$last" "삭제만" "  └ '삭제만' 문구 없음"; }

echo "== ⓖ 추적 안 된 .serena/project.yml + ' D' 3 → [wip] 커밋에 삭제 0 (브랜치에 f1~f3 그대로)"
FRESH_SERENA_UNTRACKED=1 fresh && { rm3; echo "name: y" > "$NW/.serena/project.yml"
  has "$(git -C "$NW" status --porcelain)" "?? .serena/project.yml" "  └ 전제: '?? .serena/project.yml' 로 보임"
  runplan
  [ "$prc" -eq 0 ] && has "$last" "cleaned(삭제만 3파일" "ⓖ → cleaned(삭제만 3파일)" || bad "ⓖ rc=$prc ← ${planout:0:400}"
  [ ! -d "$NW" ] && ok "  └ 워크트리 정리됨" || bad "워크트리 남음"
  [ -z "$(git -C "$REPO" diff --diff-filter=D --name-only "$SHA" "refs/heads/$BR")" ] && ok "  └ 브랜치에 삭제 커밋 0" || bad "브랜치에 삭제가 커밋됨: $(git -C "$REPO" diff --diff-filter=D --name-only "$SHA" "refs/heads/$BR" | tr '\n' ' ')"
  [ "$(git -C "$REPO" ls-tree -r --name-only "refs/heads/$BR" | grep -cE '^f[123]$')" -eq 3 ] && ok "  └ 브랜치 tip 에 f1~f3 그대로" || bad "브랜치 tip 에서 f1~f3 사라짐"; }

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
