#!/usr/bin/env bash
# test_nano_close_lsof_scope_r992.sh — 카드 r992: ft-nano-close 가 만드는 워크트리 정리 계획의 가드 ②(=워크트리를 cwd 로 쥔 프로세스 0)가
#   lsof 를 «머신 전체» 가 아니라 «내 uid ∧ cwd fd» 로 좁혀 7초 안에 묻고, 넘으면 내 uid pid 를 반으로 쪼개 1회 재시도하며,
#   그래도 넘으면 단계 이름 있는 ERROR 로 멈추는가(조용한 통과 0). 부하 19 에서 7초를 넘겨 ops 나노 닫기 3종이 막힌 사건(쪽지 171486 · 171335 ③).
# 픽스처 = test_nano_close_cwd_holders_skip_self_r680.sh 꼴(임시 git 리포 R + bare 원격 · 가짜 tmux·baton·sweep·lsof) —
#   실 리포·실 명부·실 tmux 세션·외부 호출 0 · GIT_* env 0. 계획은 FT_WT_AUTOCLEAN=0 으로 «생성만» 한 뒤 그 워크트리 안에서 /bin/bash <계획>.
# 축 ⓖ 전체 훑기가 8초(>7초 상한) · 묶음 호출은 즉시 → 반 쪼개기 1회로 ② 통과 + 첫 호출 인자 = «-a -u <내 uid> -d cwd -Fn»
#   ⓗ 묶음까지 8초 → «② lsof 7초 초과(묶음 2…)» 로 skipped(rc≠0 · cleaned 0 · 워크트리 그대로)
#   ⓘ 변이 «상한 제거»(_nf_cap_s=7 → 999) → ⓖ 칸 FAIL   ⓙ 변이 «-u 제거» → ⓖ 칸 FAIL(인자 검사)
# 되돌림 = 이전 판 ft-nano-close.sh (계획 본문은 close 가 생성 시점에 굽는다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"
SUT="${FT_TEST_SRC:-$KIT}/ft-nano-close.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
T0="$(date +%s)"
MYUID="$(id -u)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }

bash -n "$SUT" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/home"
cp "$SUT" "$T/bin/ft-nano-close.sh"
cp "$KIT/ft-nano-evidence-check.sh" "$KIT/ft-hil.sh" "$KIT/ft-landed-check.sh" "$T/bin/"
cp "$KIT/ft_teamset.py" "$KIT/ft-team-lib.sh" "$KIT/ft-merge-lib.sh" "$T/bin/"
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
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
# 가짜 lsof — 호출 인자를 남기고, «전체 훑기»(인자에 -p 없음) / «묶음»(인자에 -p) 별로 잠들 시간을 정한다.
#   실제 lsof 대신 쓰므로 «내 uid» 대조는 인자 기록(lsof.calls)으로 한다.
mkfake() {  # <파일> <전체: sleep|fast> <묶음: sleep|fast>
  cat > "$1" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$T/lsof.calls"
case "\$*" in
  *" -p "*) _m="$3";;
  *) _m="$2";;
esac
[ "\$_m" = sleep ] && sleep 8
printf 'p%s\n' "\$\$"
exit 0
EOF
  chmod +x "$1"
}
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare -b main "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin main
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies" "$T/wtclean"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; BR='nano/k'; RW="$R/.worktrees/harness-k"; PLAN="$T/wtclean/$SEAT.sh"
SEATS="$R/.fable-team/seats-harness.json"

run() { ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
  BATON_BIN="$T/bin/baton" "$@" 2>&1 ); }
setup() {
  : > "$T/panes"; printf '%s' "$R" > "$T/cwd"; : > "$T/tlog"; : > "$T/baton.calls"; : > "$T/sweep.calls"; : > "$T/lsof.calls"
  rm -rf "$T/wtclean"; mkdir -p "$T/wtclean"; rm -rf "$R/.worktrees/harness-k" "$R/.worktrees/harness-k.deleting-"*
  git -C "$R" worktree prune; GC "$R" branch -f "$BR" main
  GC "$R" worktree add -q "$RW" "$BR"
  printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
  GC "$RW" add -A; GC "$RW" commit -q -m work; git -C "$R" push -q -f origin "$BR:refs/heads/$BR"
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
  printf '# 인덱스: k\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$R" rev-parse "$BR")" > "$R/design/harness/indices/진행/k.md"
  printf -- '- `%s` 닫힘(ft-nano-close) 2026-10-27 · wt=planned\n' "$SEAT" > "$T/ledger.md"
}
genplan() { local _sut="${1:-$T/bin/ft-nano-close.sh}"; run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 \
  FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "$_sut" "$SEAT" --result "$T/result.md" --recv 1; }
# 계획은 «한 번만» 만든다(하드 룰 22: 시험 1개 70초 — close 호출·setup 이 무겁다).
#   계획 본문은 좌석·워크트리·원장 «경로» 만 굽고 그 경로는 setup 이 매번 같은 값으로 다시 만들므로, 한 벌을 여러 칸이 나눠 써도 된다.
#   칸마다 앞에 setup(워크트리 새로) 만 다시 한다.
PLANGEN="$T/plan.base.sh"
gen_once() {
  local o; setup; o="$(genplan)"
  [ -f "$PLAN" ] || { bad "계획 생성 실패 ← ${o:0:900}"; return 1; }
  cp "$PLAN" "$PLANGEN"
}
# plan_exec <lsof> [<계획파일>] — 워크트리를 새로 만든 뒤 그 계획을 «그 워크트리 안에서» /bin/bash 로 돌린다(= close 가 세션 kill 직후 하는 그 호출)
plan_exec() { local _lf="$1" _pl="${2:-$PLANGEN}"; setup; : > "$T/lsof.calls"
  ( cd "$RW" && env -i HOME="$T/home" PATH="$PATH" FT_LSOF_BIN="$_lf" FT_TMUX_BIN="$T/fake/tmux" \
    FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" \
    BATON_BIN="$T/bin/baton" /bin/bash "$_pl" 2>&1 ); }
# assert_g <계획파일> <lsof> — ⓖ 칸 검사(반 쪼개기 통과 · 첫 호출 인자 = 내 uid ∧ cwd fd). 어긋난 칸은 «CELL …» 로 말하고 rc 1
assert_g() {
  local pl="$1" lf="$2" o rc b=0 c1 c2
  o="$(plan_exec "$lf" "$pl")"; rc=$?
  [ "$rc" -eq 0 ] || { echo "CELL rc=$rc ${o:0:400}"; b=1; }
  case "$o" in *"INFO ② lsof 쪼개기"*) ;; *) echo "CELL 쪼개기 INFO 없음 ← ${o:0:400}"; b=1;; esac
  case "$o" in *cleaned*) ;; *) echo "CELL cleaned 없음 ← ${o:0:400}"; b=1;; esac
  c1="$(sed -n 1p "$T/lsof.calls")"; c2="$(sed -n 2p "$T/lsof.calls")"
  case "$c1" in *"-a -u $MYUID -d cwd -Fn"*) ;; *) echo "CELL 첫 호출 인자 어긋남: «${c1}»"; b=1;; esac
  case "$c1" in *"-d cwd -Fn"*) ;; *) echo "CELL 첫 호출에 cwd fd 선택자(-d cwd -Fn) 없음: «${c1}»"; b=1;; esac
  case "$c1" in *" -p "*) echo "CELL 첫 호출에 -p 가 있다(전체 훑기가 아니다): «${c1}»"; b=1;; esac
  case "$c2" in *"-a -p "*) ;; *) echo "CELL 둘째 호출이 묶음(-a -p) 아님: «${c2}»"; b=1;; esac
  return "$b"
}
# mut_plan <표지> <대체 줄> — 계획 «본문» 사본을 바꾼다(계획이 곧 실행 대상 · 바뀐 글자를 되짚어 확인)
mut_plan() {
  python3 - "$PLANGEN" "$T/plan.mut.sh" "$1" "$2" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, (mark, hit)
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
  grep -q -F -- "$2" "$T/plan.mut.sh" || { echo "MUT-FAIL 적용 안 됨"; return 1; }
}

mkfake "$T/fake/lsof-split" sleep fast
mkfake "$T/fake/lsof-slow" sleep sleep

echo "== ⓖ 전체 훑기 8초(>7초 상한) · 묶음은 즉시 → 반 쪼개기 1회로 ② 통과 · 첫 호출 = -a -u <내 uid> -d cwd -Fn"
gen_once || true
o="$(plan_exec "$T/fake/lsof-split")"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓖ 계획 rc=0" || bad "ⓖ 계획 rc=$rc ← ${o:0:600}"
has "$o" "INFO ② lsof 쪼개기 — 내 uid pid " "  └ 쪼개기 INFO 1줄"
has "$o" "cleaned" "  └ 정리 진행(쪼개기 결과로 같은 holders 계산)"
has "$(sed -n 1p "$T/lsof.calls")" "-a -u $MYUID -d cwd -Fn" "  └ 첫 호출 인자 = 내 uid ∧ cwd fd"
hasnt "$(sed -n 1p "$T/lsof.calls")" " -p " "  └ 첫 호출은 전체 훑기(-p 없음)"
has "$(sed -n 2p "$T/lsof.calls")" "-a -p " "  └ 둘째 호출 = 묶음 pid 목록(-a -p …)"
[ "$(grep -c -- '-a -p ' "$T/lsof.calls")" = 2 ] && ok "  └ 묶음 호출 정확히 2회(반 쪼개기)" || bad "  └ 묶음 호출 $(grep -c -- '-a -p ' "$T/lsof.calls")회(2회여야)"

echo "== ⓗ 묶음까지 8초 → «② lsof 7초 초과(묶음 2…)» skipped(rc≠0 · cleaned 0 · 워크트리 그대로 · 조용한 통과 0)"
o="$(plan_exec "$T/fake/lsof-slow")"; rc=$?
[ "$rc" -ne 0 ] && ok "ⓗ rc=$rc (0 아님)" || bad "ⓗ rc=0 ← ${o:0:600}"
has "$o" "skipped:② lsof 7초 초과(묶음 2" "  └ 단계 이름 있는 ERROR(② lsof 7초 초과(묶음 2))"
hasnt "$o" "cleaned" "  └ cleaned 0"
[ -d "$RW" ] && ok "  └ 워크트리 그대로(정리 0)" || bad "  └ 워크트리 사라짐"

echo "== ⓘ 변이 «상한 제거»(_nf_cap_s=7 → 999) → ⓖ 칸 FAIL(쪼개기·인자 검사가 잡는다)"
if mut_plan "# r992-mut:cap" '_nf_cap_s=999   # r992-mut:cap'; then
  assert_g "$T/plan.mut.sh" "$T/fake/lsof-split" >/dev/null 2>&1 && bad "ⓘ 상한 제거해도 ⓖ 통과(시험이 상한을 못 잡음)" || ok "ⓘ 상한 제거 → ⓖ FAIL"
else
  bad "ⓘ 변이 «상한 제거» 적용 실패"
fi

echo "== ⓙ 변이 «-u 제거» → ⓖ 칸 FAIL(첫 호출 인자 검사 · 다른 uid 프로세스가 보유자로 섞인다)"
if mut_plan "# r992-mut:uid" 'lsout="$( cd / && _ls_scan -a -d cwd -Fn )"; rc=$?   # r992-mut:uid'; then
  assert_g "$T/plan.mut.sh" "$T/fake/lsof-split" >/dev/null 2>&1 && bad "ⓙ -u 제거해도 ⓖ 통과(인자 검사가 못 잡음)" || ok "ⓙ -u 제거 → ⓖ FAIL"
else
  bad "ⓙ 변이 «-u 제거» 적용 실패"
fi

echo
echo "단계별 초: 전체 +$(( $(date +%s) - T0 ))s"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
