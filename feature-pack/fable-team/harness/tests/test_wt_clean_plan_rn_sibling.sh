#!/usr/bin/env bash
# test_wt_clean_plan_rn_sibling.sh — 카드 r574: wt-clean 계획 본문 ④ «HEAD 가지 = info branch» 가, 착지 게이트 때문에 같은 좌석이 `-rN` 형제 가지로 갈아탄 워크트리(HEAD=nano/k-r2 · info=nano/k)를 거절해 껍데기를 남기던 것을 «둘 다 nano/<KEY>[-rN] 이면 HEAD 가지로 판정» 으로 고친다(가지 삭제 0).
# 픽스처 = test_wt_clean_plan_self_check.sh 꼴(임시 git 리포 · 가짜 tmux · 가짜 sweep/baton/landed-check) — 실제 리포·명부·tmux 세션·press 호출 0
# 축 ⓐ info=nano/k · HEAD=nano/k-r2 · 미커밋 0 · 원격 밖 0 → (지금 판 FAIL) cleaned · 두 가지 그대로 ⓑ info=nano/k-r2 · HEAD=nano/k → cleaned
#   ⓒ HEAD=nano/other-r2(키 다름) → fail 그대로 ⓓ HEAD=nano/k-rx(꼴 아님)·detached → fail 그대로 ⓔ 형제 HEAD + 실작업물 1(FT_NANO_WIP=1) → [wip] 커밋 경로 · 가지 = HEAD 가지
# 되돌림 = .bak-r574
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${FT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # FT_TEST_SRC = «고치기 전» 판 대조용(증거 01-before-red)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/home"
cp "$SRC/ft-nano-close.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
printf '#!/bin/sh\necho "LANDED ok"; exit 0\n' > "$T/bin/ft-landed-check.sh"   # 착지 재검증은 이 카드 범위 밖 — 고정 통과
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/sweep.calls" > "$T/bin/ft-wt-sweep.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\necho "baton-stub $*"\n' "$T/baton.calls" > "$T/bin/baton"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) echo "no server running on /tmp/fake"; exit 1;;
      *) echo "no server running on /tmp/fake"; exit 1;;
    esac;;
  ls) echo "no server running on /tmp/fake"; exit 1;;
  display-message) echo "no server running on /tmp/fake"; exit 1;;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
mkdir -p "$R/.fable-team"
SEAT='byz-harness-nano-k#0'; KEYBR='nano/k'; WT="$R/.worktrees/harness-k"; PLAN="$T/wtclean/$SEAT.sh"
printf -- '- `%s` 닫힘(ft-nano-close) 2026-10-20 · wt=planned\n' "$SEAT" > "$T/ledger.md"
printf '{"%s":{"role":"nano","index":"design/harness/indices/x.md"}}\n' "$SEAT" > "$R/.fable-team/seats-harness.json"

run() { ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$T/sheet-root" PATH="$T/fake:$PATH" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
# reset_wt <HEAD 가지> <info 가지> — 임시 리포 안 워크트리 하나를 지정 가지로 새로 만든다(미커밋 0 · 원격 밖 0)
reset_wt() {
  local hb="$1" ib="$2"
  # 앞 케이스가 남긴 워크트리(정리 계획이 이름만 바꿔 둔 .deleting-<ts> 포함)를 먼저 등록 해제한다 — 안 하면 그 가지들이 «사용 중» 이라 새 워크트리를 만들 수 없다
  while IFS= read -r _d; do
    [ -z "$_d" ] || git -C "$R" worktree remove --force "$_d" 2>/dev/null || rm -rf "$_d"
  done < <(git -C "$R" worktree list --porcelain 2>/dev/null | awk -v b="$R/.worktrees/" '/^worktree /{p=substr($0,10); if (index(p,b)==1) print p}')
  git -C "$R" worktree prune
  for _b in $(git -C "$R" for-each-ref --format='%(refname:short)' refs/heads/nano); do git -C "$R" branch -D "$_b" >/dev/null 2>&1; done   # 케이스마다 가지 초기화
  GC "$R" worktree add -q "$WT" -b "$hb" main
  git -C "$R" rev-parse --verify -q "refs/heads/$KEYBR" >/dev/null || GC "$R" branch "$KEYBR" main   # 형제 사건의 «다른 쪽» 가지(info 쪽)를 실제로 만들어 둔다
  echo kit > "$WT/kit.sh"; GC "$WT" add -A; GC "$WT" commit -q -m work
  printf '{"branch":"%s","base":"main"}\n' "$ib" > "$WT/.worktree-info.json"; GC "$WT" add -A; GC "$WT" commit -q -m info   # info 파일도 추적(실 나노 워크트리와 같은 «미커밋 0»)
}
# genplan [FT_NANO_WIP 값] — 표준(비 named) 계획 생성 = close --plan-only(실행은 runplan 이 따로 한다)
genplan() {
  rm -rf "$T/wtclean"; mkdir -p "$T/wtclean"; : > "$T/baton.calls"; : > "$T/sweep.calls"
  out="$(run FT_SEATS_JSON="$R/.fable-team/seats-harness.json" FT_NANO_PREFIX='byz-harness-nano-' FT_NANO_WT_PREFIX='harness-' FT_NANO_LEDGER="$T/ledger.md" \
    FT_WT_CLEAN_DIR="$T/wtclean" FT_NANO_WIP="${1:-0}" FT_CENSUS_MAIN=main FT_TMUX_BIN="$T/fake/tmux" \
    bash "$T/bin/ft-nano-close.sh" "$SEAT" --plan-only "$WT")"; rc=$?
}
runplan() {
  planout="$( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$T/sheet-root" PATH="$T/fake:$PATH" \
    FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN=/usr/sbin/lsof BATON_BIN="$T/bin/baton" \
    bash "$PLAN" 2>&1)"; prc=$?; last="$(printf '%s\n' "$planout" | tail -1)"
}

echo "== ⓐ info=nano/k · HEAD=nano/k-r2 · 미커밋 0 → cleaned + 두 가지 그대로"
reset_wt nano/k-r2 nano/k; genplan
[ "$rc" -eq 0 ] && [ -f "$PLAN" ] && ok "ⓐ 계획 생성(--plan-only rc=0)" || bad "ⓐ 계획 생성 실패 rc=$rc ← ${out:0:400}"
runplan
[ "$prc" -eq 0 ] && has "$last" "cleaned" "ⓐ 실행 → cleaned" || bad "ⓐ rc=$prc ← ${planout:0:600}"
has "$planout" "형제 가지 — info nano/k · HEAD nano/k-r2" "  └ ④ 형제 인정 INFO 1줄"
hasnt "$planout" "≠ info" "  └ «HEAD≠info» 거절 0"
[ ! -e "$WT" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
git -C "$R" rev-parse --verify -q "refs/heads/$KEYBR" >/dev/null && git -C "$R" rev-parse --verify -q 'refs/heads/nano/k-r2' >/dev/null \
  && ok "  └ 두 가지(nano/k · nano/k-r2) 그대로" || bad "  └ 가지 삭제됨"
has "$(cat "$T/ledger.md")" "형제=nano/k-r2" "  └ 원장 표식에 형제=<HEAD 가지> 1조각"

echo "== ⓑ info=nano/k-r2 · HEAD=nano/k → cleaned(대칭)"
reset_wt "$KEYBR" nano/k-r2; genplan
[ "$rc" -eq 0 ] && [ -f "$PLAN" ] && ok "ⓑ 계획 생성" || bad "ⓑ 계획 생성 실패 rc=$rc ← ${out:0:400}"
runplan
[ "$prc" -eq 0 ] && has "$last" "cleaned" "ⓑ 실행 → cleaned" || bad "ⓑ rc=$prc ← ${planout:0:600}"
has "$planout" "형제 가지 — info nano/k-r2 · HEAD nano/k" "  └ INFO 줄(info=-r2 · HEAD=본 가지)"
[ ! -e "$WT" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"

echo "== ⓒ HEAD=nano/other-r2(키가 다름) → fail 그대로 · 워크트리 그대로"
reset_wt nano/k-r2 nano/k; genplan
git -C "$WT" checkout -q -b nano/other-r2
runplan
[ "$prc" -eq 1 ] && has "$last" "≠ info nano/k" "ⓒ → skipped(HEAD≠info)" || bad "ⓒ rc=$prc ← ${planout:0:600}"
hasnt "$planout" "형제 가지" "  └ 형제 인정 0"
[ -d "$WT" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"

echo "== ⓓ HEAD=nano/k-rx(꼴 아님) → fail 그대로"
reset_wt nano/k-r2 nano/k; genplan
git -C "$WT" checkout -q -b nano/k-rx
runplan
[ "$prc" -eq 1 ] && has "$last" "≠ info nano/k" "ⓓ rx → skipped" || bad "ⓓ rx rc=$prc ← ${planout:0:600}"
hasnt "$planout" "형제 가지" "  └ 형제 인정 0"
reset_wt nano/k-r2 nano/k; genplan
git -C "$WT" checkout -q --detach HEAD
runplan
[ "$prc" -eq 1 ] && has "$last" "HEAD=detached ≠ info nano/k" "ⓓ detached → skipped" || bad "ⓓ detached rc=$prc ← ${planout:0:600}"
[ -d "$WT" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"

echo "== ⓔ 형제 HEAD + 실작업물 1(FT_NANO_WIP=1) → [wip] 커밋 경로 · 가지 = HEAD 가지"
reset_wt nano/k-r2 nano/k; genplan 1
BEFORE="$(git -C "$R" rev-parse "$KEYBR")"
echo work >> "$WT/kit.sh"
runplan
[ "$prc" -eq 0 ] && has "$last" "cleaned" "ⓔ 실행 → cleaned" || bad "ⓔ rc=$prc ← ${planout:0:600}"
[ ! -e "$WT" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
[ "$(git -C "$R" log --format=%s "nano/k-r2" -n 5 | grep -c '\[wip\] nano close')" -ge 1 ] && ok "  └ [wip] 커밋이 HEAD 가지(nano/k-r2)에 붙음" || bad "  └ HEAD 가지에 [wip] 커밋 0"
[ "$(git -C "$R" rev-parse "$KEYBR")" = "$BEFORE" ] && ok "  └ info 가지(nano/k) tip 그대로" || bad "  └ info 가지가 움직임"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
