#!/usr/bin/env bash
# test_nano_close_rerun_named_equal.sh — 카드 r572: ft-nano-close «재실행» 에서 --wt/--branch(이름 지정) 인자가 «표준 좌석 해석과 같은 값» 이면 표준 좌석으로 보고 r566 정리(조건 4)를 타는가 · 다르면 정리 0 + 사유 INFO 1줄
# 픽스처 = test_nano_close_rerun_wt_clean.sh 꼴(임시 git 리포 R + bare 원격 · 가짜 tmux · 가짜 reap · 가짜 baton · 가짜 sweep) — 실제 리포·명부·tmux 세션·외부 호출 0
# 축 ⓐ 표준 좌석 재실행 · --wt/--branch 가 해석과 같은 값 → 옛 계획 보존 + cleaned + 폴더 없음 + 가지 보존 + 원장 행 1개 그대로
#   ⓑ 팀 접두가 v65- 가 아님(FT_NANO_WT_PREFIX=cfo- · 워크트리 cfo-<키>) → cleaned
#   ⓒ --wt 가 표준 해석과 다른 경로 → 정리 0 + INFO «명시가 표준 해석과 다름(해석=… 받은=…)» + 폴더 그대로
#   ⓓ --branch 가 nano/* 아님 → 정리 0 + 같은 INFO ⓔ 같은-값 named 라도 원격에 없는 커밋 → .sh.hil + [HIL] 줄
# 되돌림 = .bak-r572
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${FT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # FT_TEST_SRC = «고치기 전» 판 대조용(증거 01-before-red)
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/home"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-hil.sh" "$SRC/ft-landed-check.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "cherry OK"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\necho "baton-stub $*"\n' "$T/baton.calls" > "$T/bin/baton"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/sweep.calls" > "$T/bin/ft-wt-sweep.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option) echo "$*" >> "$FAKE_LOG";;
  kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare -b main "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin main
mkdir -p "$R/.fable-team" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEATS="$R/.fable-team/seats-harness.json"
# 좌석 파라미터(setup 이 매번 새로 쓴다 — ⓑ 는 팀 접두가 다르다)
seat_vars() { SEAT="$1"; NP="$2"; WP="$3"; WTNAME="$4"; BR="${5:-nano/k}"; RW="$R/.worktrees/$WTNAME"; }
seat_vars 'byz-harness-nano-k#0' 'byz-harness-nano-' 'harness-' 'harness-k'
run() { ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
  BATON_BIN="$T/bin/baton" "$@" 2>&1 ); }
close() { run FT_NANO_PREFIX="$NP" FT_NANO_WT_PREFIX="$WP" FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
# 재실행 직전 상태로 리셋: 명부 행 없음 · 세션 0 · 가지 = 원격과 같은 sha · 옛 계획 .sh.hil.stale 잔존
setup() {
  printf '{}\n' > "$SEATS"; printf -- '- `%s` 닫힘(ft-nano-close) 2026-10-20 · wt=planned\n' "$SEAT" > "$T/ledger.md"
  : > "$T/panes"; printf '%s' "$R" > "$T/cwd"; : > "$T/tlog"; : > "$T/baton.calls"; : > "$T/sweep.calls"
  rm -rf "$T/wtclean"; mkdir -p "$T/wtclean"
  # 이전 케이스가 남긴 워크트리 정리(임시 리포 안 · git 등록부터 해제)
  while IFS= read -r _d; do [ -z "$_d" ] || git -C "$R" worktree remove --force "$_d" 2>/dev/null || rm -rf "$_d"; done \
    < <(git -C "$R" worktree list --porcelain 2>/dev/null | awk -v b="$R/.worktrees/" '/^worktree /{p=substr($0,10); if (index(p,b)==1) print p}')
  git -C "$R" worktree prune; git -C "$R" branch -f "$BR" main -q 2>/dev/null || GC "$R" branch -f "$BR" main
  GC "$R" worktree add -q "$RW" "$BR"
  printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
  printf '#!/bin/bash\n# 옛 판 계획(10-12) — 워크트리 삭제... Terminated: 15\n' > "$T/wtclean/$SEAT.sh.hil.stale"
}
push_head() { GC "$RW" add -A; GC "$RW" commit -q -m work; git -C "$R" push -q -f origin "$BR:refs/heads/$BR"; }

echo "== ⓐ 표준 좌석 재실행 · --wt/--branch = 해석과 같은 값 → 옛 계획 보존 + cleaned + 폴더 없음 + 가지 보존"
setup; echo kit > "$RW/kit.sh"; push_head; BEFORE="$(git -C "$R" rev-parse "$BR")"
out="$(close --wt "$RW" --branch "$BR")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ rc=0 · CLOSED" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "같은 값" "  └ 같은 값 INFO 1줄"
has "$out" "워크트리 정리: cleaned" "  └ «워크트리 정리: cleaned»"
ls "$T/wtclean" | grep -q "$SEAT.superseded-" && ok "  └ 옛 계획 .superseded-<시각> 보존" || bad "  └ 옛 계획 보존 0: $(ls "$T/wtclean")"
[ ! -e "$RW" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
git -C "$R" rev-parse --verify -q "refs/heads/$BR" >/dev/null && [ "$(git -C "$R" rev-parse "$BR")" = "$BEFORE" ] && ok "  └ 가지 보존 · sha 그대로" || bad "  └ 가지 사라짐/변경"
[ "$(grep -cF "\`$SEAT\` 닫힘(ft-nano-close)" "$T/ledger.md")" = 1 ] && ok "  └ 원장 행 1개 그대로(append 0)" || bad "  └ 원장 행 변경"

echo "== ⓑ 팀 접두가 v65- 가 아님(cfo-) → 같은 값 named 재실행 = cleaned"
seat_vars 'byz-cfo-nano-k#0' 'byz-cfo-nano-' 'cfo-' 'cfo-k'
setup; echo kit > "$RW/kit.sh"; push_head
out="$(close --wt "$RW" --branch "$BR")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "워크트리 정리: cleaned" "ⓑ rc=0 · cleaned(접두 cfo-)" || bad "ⓑ rc=$rc ← ${out:0:900}"
[ ! -e "$RW" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
seat_vars 'byz-harness-nano-k#0' 'byz-harness-nano-' 'harness-' 'harness-k'

echo "== ⓒ --wt 가 표준 해석과 다른 경로 → 정리 0 + INFO «명시가 표준 해석과 다름(해석=… 받은=…)»"
setup; echo kit > "$RW/kit.sh"; push_head
OTHER="$R/.worktrees/harness-other"; GC "$R" worktree add -q "$OTHER" -b nano/other main
out="$(close --wt "$OTHER" --branch nano/other)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "명시가 표준 해석과 다름" "ⓒ INFO 사유 줄" || bad "ⓒ rc=$rc ← ${out:0:900}"
has "$out" "해석=$RW" "  └ 해석= 표준 해석 경로"
has "$out" "받은=$OTHER" "  └ 받은= 넘긴 경로"
hasnt "$out" "워크트리 정리: cleaned" "  └ 실행 0"
[ ! -e "$T/wtclean/$SEAT.sh" ] && [ ! -e "$T/wtclean/$SEAT.sh.hil" ] && ok "  └ 새 계획 0" || bad "  └ 새 계획 생김: $(ls "$T/wtclean")"
[ -d "$RW" ] && [ -d "$OTHER" ] && ok "  └ 워크트리 둘 다 그대로" || bad "  └ 워크트리 사라짐"
GC "$R" worktree remove --force "$OTHER" 2>/dev/null || true

echo "== ⓓ --branch 가 nano/* 아님 → 정리 0 + 같은 INFO"
setup; echo kit > "$RW/kit.sh"; push_head
out="$(close --wt "$RW" --branch main)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "명시가 표준 해석과 다름" "ⓓ INFO 사유 줄" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$out" "받은=$RW" "  └ 받은= 넘긴 경로"
hasnt "$out" "워크트리 정리: cleaned" "  └ 실행 0"
[ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"

echo "== ⓔ 같은-값 named 라도 가지 HEAD 가 원격에 없음 → 실행 0 · 계획 .sh.hil + 이유 줄 «원격에 없는 커밋 N»"
setup; echo kit > "$RW/kit.sh"; push_head; echo local > "$RW/local.txt"; GC "$RW" add local.txt; GC "$RW" commit -q -m local-only
out="$(close --wt "$RW" --branch "$BR")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "[HIL] 재실행 — 원격에 없는 커밋" "ⓔ HIL · 이유 줄" || bad "ⓔ rc=$rc ← ${out:0:900}"
hasnt "$out" "워크트리 정리: cleaned" "  └ 실행 0"
[ -f "$T/wtclean/$SEAT.sh.hil" ] && grep -q '원격에 없는 커밋' "$T/wtclean/$SEAT.sh.hil" && ok "  └ 계획 .sh.hil + 이유 줄" || bad "  └ .sh.hil/이유 줄 없음: $(ls "$T/wtclean")"
[ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"
[ "$(grep -c . "$T/baton.calls")" = 0 ] && ok "  └ baton 호출 0" || bad "  └ baton 호출됨"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
