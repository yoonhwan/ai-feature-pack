#!/usr/bin/env bash
# test_nano_close_rerun_wt_clean.sh — 카드 r566: ft-nano-close «재실행» 경로(명부 행 없음 ∧ 원장 닫힘 행 있음)가 표준 나노 좌석에서도 워크트리 정리를 «실제로» 하는가
# 픽스처 = test_nano_close_rerun_early.sh 꼴(임시 git 리포 R + bare 원격 · 가짜 tmux · 가짜 reap · 가짜 baton) — 실제 리포·명부·tmux 세션·외부 호출 0 · GIT_* env 0.
# 축 ⓐ 옛 계획(.sh.hil.stale) 잔존 재실행 → 옛 계획 보존 이동 + 새 계획 생성·실행 + «워크트리 정리: cleaned» + 폴더 없음 + 가지 보존
#   ⓑ 추적 파일 다수 ' D' → [wip] 커밋 0(가지 sha 그대로) ⓒ 가지 HEAD 가 원격에 없음 → 실행 0 · 계획 .sh.hil + 이유 줄
#   ⓓ 세션 살아 있음 → kill 뒤 실행 · kill 실패면 실행 0 ⓔ --wt/--branch(표준 해석과 «다른 값»)·--shared-wt 재실행 → 지금 동작 그대로(새 계획 0) ⓕ tmux 조회 실패 → REJECT · 실행 0
# 되돌림 = .bak-r566
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
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "cherry OK"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
# 가짜 baton = 호출 기록만(실제 아카이브·삭제 0)
printf '#!/bin/sh\necho "$*" >> "%s"\necho "baton-stub $*"\n' "$T/baton.calls" > "$T/bin/baton"
# 가짜 ft-wt-sweep = --finish 호출 기록만(실제 분리 삭제 0 — .deleting-<ts> 폴더는 남는다)
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/sweep.calls" > "$T/bin/ft-wt-sweep.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    [ ! -e "$FAKE_FAIL" ] || { echo "error connecting to /tmp/fake (Permission denied)"; exit 1; }
    if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option) echo "$*" >> "$FAKE_LOG";;
  kill-session) [ ! -e "$FAKE_KILLFAIL" ] || exit 1; echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare -b main "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin main
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; BR='nano/k'; RW="$R/.worktrees/harness-k"
SEATS="$R/.fable-team/seats-harness.json"; mkdir -p "$T/wtclean"
printf -- '- `%s` 닫힘(ft-nano-close) 2026-10-20 · wt=planned\n' "$SEAT" > "$T/ledger.md"

run() { ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_FAIL="$T/tmux-fail" FAKE_KILLFAIL="$T/killfail" \
  BATON_BIN="$T/bin/baton" "$@" 2>&1 ); }
close() { run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
# setup <옵션> — 재실행 직전 상태로 리셋: 명부 행 없음 · 세션 없음 · 가지 nano/k 가 원격과 같은 sha · 옛 계획 .sh.hil.stale 잔존
setup() {
  printf '{}\n' > "$SEATS"
  : > "$T/panes"; printf '%s' "$R" > "$T/cwd"; : > "$T/tlog"; : > "$T/baton.calls"; : > "$T/sweep.calls"
  rm -rf "$T/wtclean" "$T/tmux-fail" "$T/killfail"; mkdir -p "$T/wtclean"
  rm -rf "$R/.worktrees/harness-k" "$R/.worktrees/harness-k.deleting-"*
  git -C "$R" worktree prune; git -C "$R" branch -f "$BR" main -q 2>/dev/null || GC "$R" branch -f "$BR" main
  GC "$R" worktree add -q "$RW" "$BR"
  printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
  printf '#!/bin/bash\n# 옛 판 계획(10-12) — 워크트리 삭제... Terminated: 15\n' > "$T/wtclean/$SEAT.sh.hil.stale"
}
# 가지 HEAD 를 원격에 올린다(기본 = 추적 파일 1개 있는 정상 커밋)
push_head() { GC "$RW" add -A; GC "$RW" commit -q -m work; git -C "$R" push -q -f origin "$BR:refs/heads/$BR"; }
mkdir -p "$T/wtclean"

echo "== ⓐ 표준 나노 재실행(명부 행 0 · 원장 wt=planned · 세션 0 · HEAD=원격 · 옛 계획 .hil.stale) → 옛 계획 보존 + 새 계획 실행 + cleaned + 폴더 없음 + 가지 보존"
setup; echo kit > "$RW/kit.sh"; push_head; BEFORE="$(git -C "$R" rev-parse "$BR")"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ rc=0 · CLOSED" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "워크트리 정리: cleaned" "  └ «워크트리 정리: cleaned»"
ls "$T/wtclean" | grep -q "$SEAT.superseded-" && ok "  └ 옛 계획 .superseded-<시각> 보존" || bad "  └ 옛 계획 보존 0: $(ls "$T/wtclean")"
[ ! -e "$T/wtclean/$SEAT.sh.hil.stale" ] && ok "  └ 옛 .hil.stale 자리 비움" || bad "  └ 옛 .hil.stale 그대로"
[ "$(grep -c . "$T/sweep.calls")" -ge 1 ] && ok "  └ 분리 정리 위임 기록(계획 실제 실행)" || bad "  └ sweep 위임 0"
[ ! -e "$RW" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
git -C "$R" rev-parse --verify -q "refs/heads/$BR" >/dev/null && [ "$(git -C "$R" rev-parse "$BR")" = "$BEFORE" ] && ok "  └ 가지 보존 · sha 그대로" || bad "  └ 가지 사라짐/변경"
[ "$(grep -cF "\`$SEAT\` 닫힘(ft-nano-close)" "$T/ledger.md")" = 1 ] && ok "  └ 원장 행 1개 그대로(append 0)" || bad "  └ 원장 행 변경"

echo "== ⓑ 추적 파일 다수 ' D' 상태에서도 재실행 정리 → [wip] 커밋 0 · 가지 sha 그대로"
setup; echo a > "$RW/a.txt"; echo b > "$RW/b.txt"; push_head; BEFORE="$(git -C "$R" rev-parse "$BR")"
rm -f "$RW/a.txt" "$RW/b.txt"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "워크트리 정리: cleaned" "ⓑ rc=0 · cleaned" || bad "ⓑ rc=$rc ← ${out:0:900}"
[ "$(git -C "$R" rev-parse "$BR")" = "$BEFORE" ] && ok "  └ [wip] 커밋 0(가지 sha 그대로)" || bad "  └ 가지 sha 변경"
[ ! -e "$RW" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"

echo "== ⓒ 가지 HEAD 가 어떤 원격 ref 에도 없음 → 실행 0 · 계획 .sh.hil + 이유 줄 «원격에 없는 커밋 N»"
setup; echo kit > "$RW/kit.sh"; push_head; echo local > "$RW/local.txt"; GC "$RW" add local.txt; GC "$RW" commit -q -m local-only
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "[HIL] 재실행 — 원격에 없는 커밋" "ⓒ HIL · 이유 줄" || bad "ⓒ rc=$rc ← ${out:0:900}"
hasnt "$out" "워크트리 정리: cleaned" "  └ 실행 0"
[ -f "$T/wtclean/$SEAT.sh.hil" ] && grep -q '원격에 없는 커밋' "$T/wtclean/$SEAT.sh.hil" && ok "  └ 계획 .sh.hil + 이유 줄" || bad "  └ .sh.hil/이유 줄 없음: $(ls "$T/wtclean")"
[ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"
[ "$(grep -c . "$T/baton.calls")" = 0 ] && ok "  └ baton 호출 0" || bad "  └ baton 호출됨"

echo "== ⓓ 세션 살아 있음 → kill 뒤 실행 · kill 실패면 실행 0"
setup; echo kit > "$RW/kit.sh"; push_head
printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "워크트리 정리: cleaned" "ⓓ 세션 kill 뒤 정리 실행" || bad "ⓓ rc=$rc ← ${out:0:900}"
has "$(cat "$T/tlog")" "kill-session -t %1" "  └ 세션 kill"
setup; echo kit > "$RW/kit.sh"; push_head; : > "$T/killfail"
printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "FAIL $SEAT" "  └ kill 실패 = FAIL" || bad "  └ kill 실패 rc=$rc ← ${out:0:500}"
[ ! -e "$T/wtclean/$SEAT.sh" ] && [ "$(grep -c . "$T/baton.calls")" = 0 ] && ok "  └ 실행 0(계획 0 · baton 0)" || bad "  └ 실행됨: $(ls "$T/wtclean")"

echo "== ⓔ --wt/--branch(명시 · 표준 해석과 «다른 값») · --shared-wt 재실행 → 지금 동작 그대로(새 계획 0 · 실행 0) — r572: «같은 값» named 는 표준 좌석으로 보아 정리한다(test_nano_close_rerun_named_equal ⓐ)"
setup; echo kit > "$RW/kit.sh"; push_head
out="$(close --wt "$RW" --branch nano/other)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓔ 다른 값 named 재실행 → CLOSED" || bad "ⓔ named rc=$rc ← ${out:0:900}"
has "$out" "명시가 표준 해석과 다름" "  └ 사유 INFO 1줄"
hasnt "$out" "워크트리 정리: cleaned" "  └ 다른 값 named = 실행 0"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 새 계획 0" || bad "  └ 새 계획 생김"
[ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"
setup; out="$(close --shared-wt)"; rc=$?
[ "$rc" -eq 0 ] && hasnt "$out" "워크트리 정리: cleaned" "ⓔ --shared-wt 재실행 → CLOSED · 실행 0" || bad "ⓔ shared rc=$rc ← ${out:0:900}"
[ ! -e "$T/wtclean/$SEAT.sh" ] && [ "$(grep -c . "$T/baton.calls")" = 0 ] && ok "  └ 계획·실행 0" || bad "  └ 계획 생김: $(ls "$T/wtclean")"

echo "== ⓕ tmux 조회 실패 → REJECT(fail-closed) · 실행 0"
setup; echo kit > "$RW/kit.sh"; push_head; : > "$T/tmux-fail"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "tmux 조회 실패" "ⓕ REJECT" || bad "ⓕ rc=$rc ← ${out:0:900}"
[ ! -e "$T/wtclean/$SEAT.sh" ] && [ "$(grep -c . "$T/baton.calls")" = 0 ] && ok "  └ 실행 0" || bad "  └ 실행됨"

echo "== ⓖ 재실행이 아니면(명부 행 있음) 새 정리 동작을 타지 않는다 — 기존 경로 그대로"
setup; echo kit > "$RW/kit.sh"; push_head
printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
printf '# 인덱스: k\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$R" rev-parse "$BR")" > "$R/design/harness/indices/진행/k.md"
out="$(close)"; rc=$?
hasnt "$out" "재실행" "ⓖ 재실행 판별 0" || bad "ⓖ 재실행 문구: ${out:0:600}"
hasnt "$out" "INFO 재실행" "  └ 재실행 분기 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
