#!/usr/bin/env bash
# test_nano_close_std_wt_other_branch.sh — 카드 r599: 좌석이 «표준 워크트리 경로» 그대로 두고 가지만 다른 nano/ 이름으로 바꿔 일한 경우
#   ft-nano-close 가 그 워크트리를 좌석의 것으로 인정해 자동 정리 경로(실행 계획 .sh)로 보낸다(예전 = 좌석 해석 0 → REJECT · 사람 계획).
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 스크립트 사본(가짜 cherry 게이트)만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-nano-slots.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  ls) if [ -s "$FAKE_SESSIONS" ]; then cat "$FAKE_SESSIONS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO"
git init -q --bare "$T/origin.git"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" remote add origin "$T/origin.git" && git -C "$REPO" push -q origin main   # r842: ref(origin/main) 실재 — r842 계약은 ref 못 풀면 REJECT(시험 픽스처는 ref 를 준다 · ref 에 design/TEAMS.md 없음 = 단계 판정 빈 rc0 → 지금 규칙)
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-planner-nano-ovr#0'; CARD="$REPO/design/planner/indices/진행/ovr.md"
WTX="$REPO/.worktrees/v65-ovr"          # 표준 경로(접두 v65- + 좌석 키 ovr)
OTHER="nano/other-work"                  # 좌석 키와 다른 nano/ 가지
GIT worktree add -q "$WTX" -b "$OTHER"
git -C "$WTX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m work
SHA="$(git -C "$WTX" rev-parse HEAD)"
printf '{"branch":"%s","base":"main"}\n' "$OTHER" > "$WTX/.worktree-info.json"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_SESSIONS="$T/sessions" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {   # 정상 상태로 리셋 — 세션 0(닫을 좌석은 이미 죽었다) · 카드·명부·원장
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; : > "$T/pane-cwds"; : > "$T/sessions"; : > "$T/cwd"; : > "$T/tlog"; : > "$T/ledger.md"
  rm -rf "$T/wtclean"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1; }
# 가지·info 값을 한 칸씩 비튼다(워크트리를 새로 만들지 않고 checkout/info 만 바꾼다)
set_br() { git -C "$WTX" checkout -q -B "$1" "$SHA"; printf '{"branch":"%s","base":"main"}\n' "${2:-$1}" > "$WTX/.worktree-info.json"; }

echo "== ⓐ 표준 경로 + 다른 nano/ 가지 → 좌석 워크트리로 인정(예전엔 해석 0)"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT" "ⓐ rc=0 · CLOSED-ABSENT" || bad "ⓐ rc=$rc ← ${out:0:600}"
hasnt "$out" "좌석 워크트리가 아니고" "  └ «해석 0» 사유 없음"
PLAN="$T/wtclean/$SEAT.sh"
[ -f "$PLAN" ] && ok "  └ 실행 계획(.sh — sweep 순회 대상)" || bad "ⓐ 계획 없음: $(ls "$T/wtclean" 2>&1)"
[ ! -e "$T/wtclean/$SEAT.sh.hil" ] && ok "  └ .sh.hil(사람 대기) 0" || bad "ⓐ .sh.hil 이 생김(사람 손 대기 재발)"
L="$(cat "$T/ledger.md")"
has "$L" "mode=std-wt-other-branch wt=$WTX branch=$OTHER" "  └ 원장 행 mode=std-wt-other-branch wt=<표준경로> branch=<다른 가지>"
has "$L" "닫힘(ft-nano-close)" "  └ 닫힘 행 append"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제" || bad "ⓐ 명부에 좌석 남음"
[ -d "$WTX" ] && [ -f "$WTX/.git" ] && ok "  └ 워크트리 그대로(계획은 sweep 몫)" || bad "ⓐ 워크트리 사라짐"
git -C "$REPO" rev-parse --verify -q "refs/heads/$OTHER" >/dev/null && ok "  └ 브랜치 삭제 0" || bad "ⓐ 브랜치 삭제됨"
SWEEP="$(cd "$REPO" && FT_WT_CLEAN_DIR="$T/wtclean" bash "$SRC/ft-wt-sweep.sh" --dry-run 2>&1)"
has "$SWEEP" "$SEAT" "  └ sweep --dry-run 이 이 계획을 집어 간다"

echo "== ⓑ 같은 경로인데 nano/ 가지가 아님 → 지금처럼 표준 0(자율 정리 0)"
setup; set_br "feat/x"; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "세션 없음: $SEAT" "ⓑ rc=1 · 세션 없음(좌석 해석 0)" || bad "ⓑ rc=$rc ← ${out:0:500}"
hasnt "$out" "mode=std-wt-other-branch" "  └ 원장 모드 없음"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 계획 0" || bad "ⓑ 계획이 생김"
[ -z "$(cat "$T/tlog")" ] && ok "  └ tmux 변경 0" || bad "ⓑ REJECT 인데 tmux 변경: $(cat "$T/tlog")"
set_br "$OTHER"

echo "== ⓒ info branch ≠ HEAD 가지 → 표준 0"
setup; set_br "$OTHER" "nano/other-info"; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "세션 없음: $SEAT" "ⓒ rc=1 · 세션 없음(info 불일치)" || bad "ⓒ rc=$rc ← ${out:0:500}"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 계획 0" || bad "ⓒ 계획이 생김"

echo "== ⓓ 그 다른 가지를 키로 하는 좌석 세션이 살아 있음 → 인정 0 + 사유 1줄(남의 좌석 가지)"
setup; set_br "$OTHER"; printf 'byz-planner-nano-other-work#0\n' > "$T/sessions"; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "남의 좌석 가지 · 추측 금지" "ⓓ rc=1 · 사유 «남의 좌석 가지 · 추측 금지»" || bad "ⓓ rc=$rc ← ${out:0:500}"
has "$out" "byz-planner-nano-other-work#0" "  └ 사유에 살아 있는 세션 이름"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ 계획 0" || bad "ⓓ 계획이 생김"

echo "== ⓔ 가지 = nano/<키> 인 기존 표준 좌석 → 회귀 0(바이트 같은 결과)"
setup; set_br "nano/ovr"; out_new="$(close)"; rc_new=$?
[ "$rc_new" -eq 0 ] && has "$out_new" "CLOSED-ABSENT $SEAT" "ⓔ rc=0 · CLOSED-ABSENT" || bad "ⓔ rc=$rc_new ← ${out_new:0:500}"
L_NEW="$(cat "$T/ledger.md")"
hasnt "$L_NEW" "mode=std-wt-other-branch" "  └ 새 모드 문구 0(표준 경로 그대로)"
has "$L_NEW" "wt=planned" "  └ 원장 wt=planned(기존 꼴)"
[ -f "$T/wtclean/$SEAT.sh" ] && ok "  └ 계획 .sh(기존 꼴)" || bad "ⓔ 계획 없음"
# origin/main 판(= r599 이전)과 같은 결과인지: 계획 존재·원장 행·종료코드를 대조
if git -C "$SRC" cat-file -e "origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-nano-close.sh" 2>/dev/null; then
  git -C "$SRC" show "origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-nano-close.sh" > "$T/bin/ft-nano-close-old.sh"
  setup; set_br "nano/ovr"
  out_old="$(run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
    FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean-old" bash "$T/bin/ft-nano-close-old.sh" "$SEAT" --result "$T/result.md" --recv 1)"; rc_old=$?
  [ "$rc_old" = "$rc_new" ] && ok "  └ rc 동일($rc_old)" || bad "  └ rc 다름(옛 $rc_old ≠ 새 $rc_new)"
  [ "$(cat "$T/ledger.md")" = "$L_NEW" ] && ok "  └ 원장 행 바이트 동일" || bad "  └ 원장 행 다름: $(cat "$T/ledger.md")"
  [ -f "$T/wtclean-old/$SEAT.sh" ] && ok "  └ 옛 판도 같은 계획(.sh)" || bad "  └ 옛 판 계획 없음"
else
  echo "SKIP ⓔ 옛 판 대조 — origin/main 사본 없음(대조 불가)"; bad "ⓔ 옛 판 대조 불가"
fi

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
