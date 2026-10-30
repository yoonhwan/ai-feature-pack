#!/usr/bin/env bash
# test_nano_detached_base_on_main_r1162.sh — 카드 r1162: --base 없이 detached 사본(r1120 길)에서 spawn 할 때 그 커밋이 origin/main 의 조상이 아니면
#   카드·워크트리·명부·tmux 쓰기 «전» REJECT 1줄(«--base origin/main 으로 다시»). 착지된 detached · 이름 있는 가지 · --base 지정은 그대로.
# 계약↔시험: ⓐ R1 + 변이(조상 검사 끔) · ⓑ R2 · ⓒ R3·R4 · ⓓ bin·kit cmp · ⓔ 회귀(test_nano_detached_base_r1120.sh 는 따로 돈다)
# 임시 리포 + 가짜 원격(bare · main 2커밋) + --detach linked worktree 사본 + 가짜 tmux/tmuxc/tmm(PATH 앞) · --dry-run 만(좌석·tmux 0)
#   실 리포·실 원격·실 명부 0 · 고정 sleep 0 · 자기 재호출 = real_state_guard 재진입 표지(RSG_ACTIVE)뿐. 꼴 = test_r975_nano_spawn_reply_target.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'
CARDX="design/harness/indices/대기/x.md"
GIT() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

echo "== ⓓ bin·kit 같은 내용"
bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n ft-nano-spawn.sh"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "사본 cmp ft-nano-spawn.sh" || bad "사본 불일치 ft-nano-spawn.sh"

# ── 가짜 도구(PATH 앞) — 실 tmux·tmuxc·tmm 을 부르지 않는다
mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\ncase "$1" in has-session|list-panes) exit 1;; show-option) echo 1;; esac\nexit 0\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/usr/bin/env bash\nprintf "harne ● byz-harness-master-claude#1 IDLE  fabl5·hi 09~14  0m harness-ops\\n"\n' > "$T/fake/tmm"
chmod +x "$T/fake/"*
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"; chmod +x "$BINX/ft-all-stop.sh"

# ── 픽스처: 리포 D(main 2커밋) + 가짜 원격 bare(origin) ──
D="$T/d"
mkdir -p "$D/.fable-team/state" "$D/.fable-team/comm" "$D/.fable-team/bin-harness" "$D/design/harness/indices/대기" "$D/design/v65" "$D/scripts"
printf '#!/bin/sh\nexit 0\n' > "$D/scripts/real.sh"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$D/.fable-team/state/all-stop.log"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$D/design/TEAMS.md"
echo x > "$D/design/v65/SEATBELT-README.md"
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$D/.fable-team/bin-harness/goal-lines.txt"
printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$D/design/harness/GOAL-harness.md"
printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① real.sh | ⓐ rc0 |\n\n## 완료 조건\n- 시험 rc=0\n\n## 상태\n- 대기\n' \
  "$G1" "$G2" "$G3" "$CLOSE" > "$D/$CARDX"
printf '{"_version":"1.0.0","byz-harness-master-claude#1":{"role":"master"}}\n' > "$D/.fable-team/seats-harness.json"
printf '{"_version":"1.0.0"}\n' > "$D/.fable-team/seats.json"
printf "export FT_SEATS_JSON='%s/.fable-team/seats-harness.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-harness/goal-lines.txt'\n" "$D" "$D" > "$D/.fable-team/bin-harness/harness-env.sh"
git init -q -b main "$D"; GIT "$D" add -A >/dev/null; GIT "$D" commit -q -m init; M1="$(GIT "$D" rev-parse HEAD)"
echo two > "$D/two.txt"; GIT "$D" add two.txt; GIT "$D" commit -q -m two
git clone -q --bare "$D" "$T/remote.git"; GIT "$D" remote add origin "$T/remote.git"; GIT "$D" fetch -q origin
# 사본: R1 미착지(사본에서 새 커밋) · R2 착지(main 조상 M1) · R3 이름 있는 가지(main 조상 아님)
git -C "$D" worktree add -q --detach "$T/unl" main; echo u > "$T/unl/u.txt"; GIT "$T/unl" add u.txt; GIT "$T/unl" commit -q -m unlanded
UNL="$(GIT "$T/unl" rev-parse HEAD)"
git -C "$D" worktree add -q --detach "$T/landed" "$M1"
git -C "$D" worktree add -q -b feat/x "$T/feat" main; echo f > "$T/feat/f.txt"; GIT "$T/feat" add f.txt; GIT "$T/feat" commit -q -m feat

sp() {  # sp <cwd 사본> <bindir> [인자…] — env -i 격리 · --dry-run 고정
  local w="$1" bd="$2"; shift 2
  ( cd "$w" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" \
      bash "$bd/ft-nano-spawn.sh" "$CARDX" --dry-run "$@" 2>&1 )
}
r1_check() {  # r1_check <bindir> → 0 = R1 통과(REJECT 1줄 · rc1 · 카드 바이트 그대로 · PLAN 0)
  local out rc n=0
  cp "$T/unl/$CARDX" "$T/card.before"
  out="$(sp "$T/unl" "$1")"; rc=$?
  [ "$rc" = 1 ] || { n=$((n+1)); echo "  R1 rc=$rc"; }
  case "$out" in *"REJECT 기준 커밋 ${UNL:0:10} 가 origin/main 에 없다(미착지·squash) — --base origin/main 으로 다시"*) ;; *) n=$((n+1)); echo "  R1 REJECT 줄 없음 ← ${out: -400}";; esac
  [ "$(printf '%s\n' "$out" | grep -c '^REJECT')" = 1 ] || { n=$((n+1)); echo "  R1 REJECT 줄 수 ≠ 1"; }
  case "$out" in *"PLAN seat="*) n=$((n+1)); echo "  R1 PLAN 줄이 나왔다(열기 진행)";; esac
  cmp -s "$T/card.before" "$T/unl/$CARDX" || { n=$((n+1)); echo "  R1 카드 바이트가 바뀜"; }
  return "$n"
}

s=$SECONDS; echo "== ⓐ R1 detached 사본 HEAD = 미착지 커밋 · --base 없음 → REJECT 1줄 · 카드 그대로"
r1o="$(r1_check "$BINX")" && ok "R1 REJECT «${UNL:0:10} 가 origin/main 에 없다» · rc1 · 카드 cmp 같음" || bad "R1$(printf '\n%s' "$r1o")"
echo "  (R1 $((SECONDS-s))초)"

s=$SECONDS; echo "== ⓑ R2 detached 사본 HEAD = origin/main 조상 → OK · base = 그 40hex(detached)"
out="$(sp "$T/landed" "$BINX")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"base=$M1(detached) index="* ]]; } && ok "R2 OK · base=$M1(detached)" || bad "R2 rc=$rc ← ${out: -400}"
echo "  (R2 $((SECONDS-s))초)"

s=$SECONDS; echo "== ⓒ R3 이름 있는 가지(feat/x · main 조상 아님) → OK(검사 0)"
out="$(sp "$T/feat" "$BINX")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"base=feat/x index="* ]]; } && ok "R3 OK · base=feat/x" || bad "R3 rc=$rc ← ${out: -400}"
echo "== ⓒ R4 detached 미착지 + --base origin/main → OK"
out="$(sp "$T/unl" "$BINX" --base origin/main)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"base=origin/main index="* ]]; } && ok "R4 OK · base=origin/main" || bad "R4 rc=$rc ← ${out: -400}"
echo "  (R3·R4 $((SECONDS-s))초)"

s=$SECONDS; echo "== 변이: 조상 검사 끔(is-ancestor → cat-file -e) → R1 FAIL 이어야 한다"
BINM="$T/binm"; cp -R "$BINX" "$BINM"
sed 's/merge-base --is-ancestor "\$_dh" refs\/remotes\/origin\/main/cat-file -e "$_dh"/' "$BINX/ft-nano-spawn.sh" > "$BINM/ft-nano-spawn.sh"
cmp -s "$BINM/ft-nano-spawn.sh" "$BINX/ft-nano-spawn.sh" && bad "변이 적용 0(패턴 없음)" || {
  r1_check "$BINM" >/dev/null && bad "변이가 R1 을 통과 — 시험이 조상 검사를 못 본다" || ok "변이 → R1 FAIL(잡힘)"; }
echo "  (변이 $((SECONDS-s))초)"

echo
echo "총 $((SECONDS-T0))초"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
