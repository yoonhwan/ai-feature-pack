#!/usr/bin/env bash
# test_nano_close_cwd_holders_skip_self_r680.sh — 카드 r680: ft-nano-close 가 만드는 워크트리 정리 계획의 가드 ②(=워크트리를 cwd 로 쥔 프로세스 0)가
#   «이 명령 자신과 그 조상» 을 빼고 세는가. 사건 = 닫기를 그 워크트리 «안» 에서 부르면 부른 셸이 늘 cwd 를 쥐고 있어 정리가 영영 `skipped:cwd 보유 프로세스 1개`.
#   같은 키트 ft-seat-reap.sh:9 의 «이 명령 자신과 조상» 제외와 같은 규칙 — 세는 대상에서 자기 나무만 뺀다(남의 보유자·lsof 실패·ps 실패는 그대로 실패).
# 픽스처 = test_nano_close_rerun_wt_clean.sh 꼴(임시 git 리포 R + bare 원격 · 가짜 tmux·baton·sweep) — 실 리포·실 명부·실 tmux 세션·외부 호출 0 · GIT_* env 0.
# 계획은 FT_WT_AUTOCLEAN=0 으로 «생성만» 한 뒤, 그 워크트리 안에서 /bin/bash <계획> 으로 «직접» 돌린다 = close 가 세션 kill 직후 하는 그 호출 그대로.
# 축 ⓐ(전 판 원문 = FT_TEST_SRC 로 base 판) 워크트리 안 호출 → `skipped:cwd 보유 프로세스` · 정리 0
#   ⓑ 같은 호출(고친 판) → 자기·조상 제외로 가드 통과 → `cleaned` · 워크트리 폴더 없음 · 가지 보존
#   ⓒ 워크트리 안에 cwd 를 둔 «다른» 프로세스(sleep — CPU 0 · 시험 끝에 정리) → 실패 그대로 + `pid=<n> cmd=<앞 60자>` 1줄
#   ⓓ lsof 실패 = 실패 그대로(fail-closed) ⓔ 조상 계산(ps) 실패 = 제외 없이 세는 쪽(조용한 통과 0) ⓕ 기존 nano_close 시험 PASS
# 되돌림 = 이전 판 ft-nano-close.sh (계획 본문은 close 가 생성 시점에 굽는다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"                   # 부속 도구는 항상 «지금» 키트에서
SUT="${FT_TEST_SRC:-$KIT}/ft-nano-close.sh"                    # FT_TEST_SRC = «고치기 전» 판 대조용(증거 01-before-red)
T="$(cd "$(mktemp -d)" && pwd -P)"
SLEEPPID=""
cleanup() { [ -n "$SLEEPPID" ] && kill "$SLEEPPID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }

bash -n "$SUT" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/home"
cp "$SUT" "$T/bin/ft-nano-close.sh"
BASE_SUT="${FT_TEST_BASE_SUT:-}"                               # ⓐ 대조용 «고치기 전» 판(없으면 ⓐ 생략 — 증거 01-before-red 가 그 원문)
[ -z "$BASE_SUT" ] || cp "$BASE_SUT" "$T/bin/ft-nano-close.base.sh"
cp "$KIT/ft-nano-evidence-check.sh" "$KIT/ft-hil.sh" "$KIT/ft-landed-check.sh" "$T/bin/"
cp "$KIT/ft_teamset.py" "$KIT/ft-team-lib.sh" "$KIT/ft-merge-lib.sh" "$T/bin/"   # r992: 입구가 ft_teamset.py(r655)·ft-team-lib.sh 를 요구한다 — 빠지면 계획 생성 자체가 ERROR(이 시험은 base 에서도 빨간불이었다)
cp "$KIT/ft-sheet-events.sh" "$KIT/ft_sheet_events.py" "$KIT/ft_sheet_confirm.py" "$KIT/ft_sheet_key.py" "$KIT/ft_board_env.py" "$KIT/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "cherry OK"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\necho "baton-stub $*"\n' "$T/baton.calls" > "$T/bin/baton"
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
  kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare -b main "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin main
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies" "$T/wtclean"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; BR='nano/k'; RW="$R/.worktrees/harness-k"; PLAN="$T/wtclean/$SEAT.sh"
SEATS="$R/.fable-team/seats-harness.json"

run() { ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_FAIL="$T/tmux-fail" \
  BATON_BIN="$T/bin/baton" "$@" 2>&1 ); }
# setup — 계획을 만들 수 있는 «깨끗한» 좌석: 가지 nano/k = main 과 같은 sha(착지) · 실작업물 0 · 세션 0 · 원장 닫힘 행 1개
setup() {
  : > "$T/panes"; printf '%s' "$R" > "$T/cwd"; : > "$T/tlog"; : > "$T/baton.calls"; : > "$T/sweep.calls"
  rm -rf "$T/wtclean"; mkdir -p "$T/wtclean"; rm -rf "$R/.worktrees/harness-k" "$R/.worktrees/harness-k.deleting-"*
  git -C "$R" worktree prune; GC "$R" branch -f "$BR" main
  GC "$R" worktree add -q "$RW" "$BR"
  printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
  GC "$RW" add -A; GC "$RW" commit -q -m work; git -C "$R" push -q -f origin "$BR:refs/heads/$BR"   # 실작업물 0 이 되도록 info json 도 커밋(r566 픽스처와 같은 꼴)
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
  printf '# 인덱스: k\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$R" rev-parse "$BR")" > "$R/design/harness/indices/진행/k.md"
  printf -- '- `%s` 닫힘(ft-nano-close) 2026-10-22 · wt=planned\n' "$SEAT" > "$T/ledger.md"
}
# genplan — cwd = 리포 루트(워크트리 «밖») 에서 close · FT_WT_AUTOCLEAN=0 = 계획만 생성(실행 0)
genplan() { local _sut="${1:-$T/bin/ft-nano-close.sh}"; run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 \
  FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "$_sut" "$SEAT" --result "$T/result.md" --recv 1; }
# runplan — ★사건 그대로★: 워크트리 «안» 을 cwd 로 둔 셸이 계획을 부른다(= close 가 세션 kill 직후 하는 그 호출)
runplan() { ( cd "$RW" && env -i HOME="$T/home" PATH="$1" FT_LSOF_BIN="$2" FT_TMUX_BIN="$T/fake/tmux" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_FAIL="$T/tmux-fail" \
  BATON_BIN="$T/bin/baton" /bin/bash "$PLAN" 2>&1 ); }
# plan_of <축이름> — setup + 계획 생성. 실패면 빈 문자열
plan_of() { local _sut="${2:-$T/bin/ft-nano-close.sh}"; setup; local o; o="$(genplan "$_sut")"; if [ -f "$PLAN" ]; then ok "$1 계획 생성"; return 0; fi
  bad "$1 계획 생성 실패 ← ${o:0:1200}"; return 1; }

echo "== ⓐ 전 판 원문(FT_TEST_BASE_SUT) — 워크트리 «안» 에서 계획 실행 → «cwd 보유 프로세스» 로 skipped (정리 0 · 폴더 그대로)"
if [ -z "$BASE_SUT" ]; then
  ok "ⓐ 생략 — FT_TEST_BASE_SUT 미지정(전 판 대조는 증거 01-before-red)"
elif plan_of "ⓐ" "$T/bin/ft-nano-close.base.sh"; then
  out="$(runplan "$PATH" /usr/sbin/lsof)"; rc=$?
  [ "$rc" -ne 0 ] && has "$out" "skipped:cwd 보유 프로세스" "ⓐ 전 판 = skipped:cwd" || bad "ⓐ rc=$rc ← ${out:0:500}"
  [ -d "$RW" ] && ok "  └ 워크트리 그대로(정리 0)" || bad "  └ 워크트리 사라짐"
  hasnt "$out" "cleaned" "  └ cleaned 0"
fi

echo "== ⓑ 고친 판 — 같은 호출 → 이 명령 자신·조상은 안 세고 «남의 보유자 0» 이므로 가드 통과 → cleaned"
if plan_of "ⓑ"; then
  out="$(runplan "$PATH" /usr/sbin/lsof)"; rc=$?
  [ "$rc" -eq 0 ] && ok "ⓑ 계획 rc=0" || bad "ⓑ 계획 rc=$rc ← ${out:0:500}"
  hasnt "$out" "skipped:cwd" "  └ skipped:cwd 0"
  has "$out" "cleaned" "  └ cleaned(정리 진행)"
  [ ! -e "$RW" ] && ok "  └ 워크트리 폴더 없음" || bad "  └ 워크트리 남음"
  git -C "$R" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 가지 보존" || bad "  └ 가지 사라짐"
fi

echo "== ⓒ 워크트리 안에 cwd 를 둔 «다른» 프로세스(sleep) → 실패 그대로 + pid·cmd 1줄(내 셸은 그대로 제외)"
if plan_of "ⓒ"; then
  ( cd "$RW" && exec sleep 60 ) & SLEEPPID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$SLEEPPID" 2>/dev/null && break; sleep 0.1; done
  out="$(runplan "$PATH" /usr/sbin/lsof)"; rc=$?
  [ "$rc" -ne 0 ] && has "$out" "cwd 보유 프로세스" "ⓒ 다른 보유자 = 실패" || bad "ⓒ rc=$rc ← ${out:0:500}"
  has "$out" "pid=$SLEEPPID cmd=" "  └ 남은 보유자 pid=<sleep> 1줄"
  has "$out" "sleep 60" "  └ 같은 줄에 명령(sleep 60)"
  [ -d "$RW" ] && ok "  └ 워크트리 그대로(정리 0)" || bad "  └ 워크트리 사라짐"
  kill "$SLEEPPID" 2>/dev/null; wait "$SLEEPPID" 2>/dev/null; SLEEPPID=""
fi

echo "== ⓓ lsof 실패 = 실패 그대로(fail-closed)"
printf '#!/bin/sh\nexit 1\n' > "$T/fake/lsof-bad"; chmod +x "$T/fake/lsof-bad"
if plan_of "ⓓ"; then
  out="$(runplan "$PATH" "$T/fake/lsof-bad")"; rc=$?
  [ "$rc" -ne 0 ] && has "$out" "skipped:lsof 실패(rc=1)" "ⓓ lsof 실패 = skipped" || bad "ⓓ rc=$rc ← ${out:0:500}"
  [ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"
fi

echo "== ⓔ 조상 계산(ps) 실패 = 제외 «없이» 센다(자기 자신도 보유자 = 조용한 통과 0)"
mkdir -p "$T/fakeps"; printf '#!/bin/sh\nexit 1\n' > "$T/fakeps/ps"; chmod +x "$T/fakeps/ps"
if plan_of "ⓔ"; then
  out="$(runplan "$T/fakeps:$PATH" /usr/sbin/lsof)"; rc=$?
  [ "$rc" -ne 0 ] && has "$out" "cwd 보유 프로세스" "ⓔ ps 실패 = 실패(통과 0)" || bad "ⓔ rc=$rc ← ${out:0:500}"
  hasnt "$out" "cleaned" "  └ cleaned 0"
  [ -d "$RW" ] && ok "  └ 워크트리 그대로" || bad "  └ 워크트리 사라짐"
fi

echo "== ⓕ 기존 nano_close 시험 PASS"
for t in test_nano_close_fail_closed.sh test_nano_close_rerun_wt_clean.sh test_nano_close_worktree_list_pipe.sh; do
  [ -f "$HERE/$t" ] || continue
  o="$(bash "$HERE/$t" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "ⓕ $t rc=0" || bad "ⓕ $t rc=$rc ← $(printf '%s' "$o" | grep -m3 '^FAIL')"
done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
