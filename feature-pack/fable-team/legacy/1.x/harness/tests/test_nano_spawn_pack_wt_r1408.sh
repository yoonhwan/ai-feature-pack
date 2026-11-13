#!/usr/bin/env bash
# test_nano_spawn_pack_wt_r1408.sh — 카드 r1408: 하네스 카드 spawn 이 팩 작업 폴더를 «좌석 열기 전» 직접 만들고, 팩 루트가 가지에 있으면 열지 않는다.
#   왜: 팩 작업 폴더를 발주문 글로만 시켰더니 pi 나노가 건너뛰고 공용 팩 루트에서 가지를 바꿨다 → 전 팀 spawn DRIFT(r1392 실사건).
#   W1 루트 detached · 폴더 없음 → «PACK-WT <경로> 만듦» 1줄 · 가지 nano/<slug> · 기준 origin/main · 루트 HEAD detached 유지
#   W2 루트가 가지(r1392-…) → REJECT · 워크트리 0 · 루트 가지 그대로 (+ 실 spawn --dry-run 한 바퀴: REJECT rc1 · tmuxc·명부 0)
#   W3 같은 slug 폴더 · 가지 nano/<slug> → «재사용» 1줄
#   W4 같은 경로 폴더가 다른 가지 → REJECT · 폴더 가지 그대로
#   W5 하네스 카드 아님(원장 줄 다름) → 출력 0 · 팩 쪽 동작 0
#   D  --dry-run · 폴더 없음 → «만들 예정» · 쓰기 0 (실 spawn --dry-run 갈래 포함) · 발주 줄 = «이미 만들어 둠» + checkout/switch 금지
#   S  호출 자리 = dry-run 종료·좌석 열기(tmuxc) 앞 · 실패 = exit 1 · bin·kit cmp0
# 변이: FT_R1408_SPAWN=<바꾼 사본> → 함수 칸(W1~W5·D)만 그 사본으로 돈다(실 spawn·cmp 칸 건너뜀).
#   루트 HEAD 검사 삭제 → W2 FAIL · 만들기 삭제 → W1 FAIL · 가지 확인 삭제 → W4 FAIL
# 꼴 = 임시 «팩 꼴» 리포(bare 원격 + 루트 detached) + 임시 bin 사본 · 실 팩·실 명부·실 tmux 0 · 자기 재호출 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
SPAWN="${FT_R1408_SPAWN:-$BIN/ft-nano-spawn.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$BIN/ft-team-lib.sh"   # ft_pack_card · ft_git_capped(추적 lib 한 출처)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — 없음 «$3» ← $(printf '%s' "${2:0:300}" | tr '\n' ';')";; esac; }
G() { git -c user.name=t -c user.email=t@t "$@"; }

# ── 임시 «팩 꼴» 리포: bare 원격 + 루트(origin/main detached) ──
mkpack() {  # $1 = 폴더 → 루트 경로 stdout
  local d="$1"; mkdir -p "$d"
  G init -q --bare "$d/origin.git"; G clone -q "$d/origin.git" "$d/seed" 2>/dev/null
  echo a > "$d/seed/a"; G -C "$d/seed" add a; G -C "$d/seed" commit -qm a; G -C "$d/seed" push -q origin HEAD:main 2>/dev/null
  G clone -q -b main "$d/origin.git" "$d/pack" 2>/dev/null; G -C "$d/pack" checkout -q --detach origin/main
  echo b > "$d/seed/b"; G -C "$d/seed" add b; G -C "$d/seed" commit -qm b; G -C "$d/seed" push -q origin HEAD:main 2>/dev/null   # 원격이 한 칸 앞 = fetch 해야 최신
  printf '%s\n' "$d/pack"
}
MARK='<!-- ledger: design/harness/GOAL-harness.md -->'
printf '# 인덱스: h\n%s\n- 설치: 있음\n\n## 상태\n' "$MARK" > "$T/h.md"
printf '# 인덱스: p\n<!-- ledger: design/v65/GOAL-LEDGER-v65.md -->\n- 설치: 있음\n\n## 상태\n' > "$T/p.md"

fn="$(awk '/^pack_wt_prepare\(\) \{/,/^\}/' "$SPAWN")"
if [ -z "$fn" ]; then
  bad "W1 pack_wt_prepare 함수 없음(만들기 0)"; bad "W2 pack_wt_prepare 함수 없음(루트 HEAD 검사 0)"
  bad "W3 함수 없음"; bad "W4 함수 없음"; bad "D 함수 없음"
else
  eval "$fn"
  # W1 — 만듦 · 가지 · 기준 origin/main(fetch 한 최신) · 루트 detached 유지
  P="$(mkpack "$T/w1")"; NEW="$(G -C "$T/w1/seed" rev-parse HEAD)"
  O="$(FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && ok "W1 rc0" || bad "W1 rc=$RC ← ${O}"
  [ "$O" = "PACK-WT $P/.worktrees/s1 만듦" ] && ok "W1 출력 = PACK-WT 만듦 1줄" || bad "W1 출력 «${O}»"
  [ "$(G -C "$P/.worktrees/s1" symbolic-ref -q --short HEAD 2>/dev/null)" = nano/s1 ] && ok "W1 가지 nano/s1" || bad "W1 가지 다름/폴더 없음"
  [ "$(G -C "$P/.worktrees/s1" rev-parse HEAD 2>/dev/null)" = "$NEW" ] && ok "W1 기준 = fetch 한 origin/main" || bad "W1 기준 다름"
  G -C "$P" symbolic-ref -q HEAD >/dev/null && bad "W1 루트 HEAD 가 가지로 바뀜" || ok "W1 루트 HEAD detached 유지"
  # W3 — 같은 폴더 다시 = 재사용
  O="$(FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && [ "$O" = "PACK-WT $P/.worktrees/s1 재사용" ] && ok "W3 재사용 1줄" || bad "W3 rc=$RC «${O}»"
  # W4 — 같은 경로 폴더가 다른 가지 → REJECT · 그대로
  G -C "$P" worktree add -q -b other "$P/.worktrees/s4" origin/main 2>/dev/null
  O="$(FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s4 nano/s4 0)"; RC=$?
  [ "$RC" = 1 ] && ok "W4 rc1" || bad "W4 rc=$RC ← ${O}"
  has "W4 REJECT 문구(가지 other)" "$O" "REJECT 팩 작업 폴더 $P/.worktrees/s4 가 가지 other 에 있음"
  [ "$(G -C "$P/.worktrees/s4" symbolic-ref -q --short HEAD)" = other ] && ok "W4 폴더 가지 그대로" || bad "W4 폴더 가지 바뀜"
  # D — dry-run: 만들 예정 · 쓰기 0
  O="$(FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" sd nano/sd 1)"; RC=$?
  [ "$RC" = 0 ] && has "D dry-run = 만들 예정" "$O" "PACK-WT $P/.worktrees/sd 만들 예정(dry-run" || bad "D rc=$RC «${O}»"
  [ ! -e "$P/.worktrees/sd" ] && ! G -C "$P" rev-parse -q --verify refs/heads/nano/sd >/dev/null && ok "D 쓰기 0(폴더·가지)" || bad "D 폴더나 가지가 생김"
  # W2 — 루트가 가지 → REJECT · 워크트리 0 · 루트 그대로
  P2="$(mkpack "$T/w2")"; G -C "$P2" checkout -q -b r1392-x
  O="$(FT_PACK_ROOT="$P2" pack_wt_prepare "$T/h.md" s2 nano/s2 0)"; RC=$?
  [ "$RC" = 1 ] && ok "W2 rc1" || bad "W2 rc=$RC ← ${O}"
  has "W2 REJECT 문구" "$O" "REJECT 팩 루트가 가지 r1392-x 에 있음 — detached origin/main 으로 되돌린 뒤 다시"
  [ ! -e "$P2/.worktrees/s2" ] && ok "W2 워크트리 0" || bad "W2 워크트리 생김"
  [ "$(G -C "$P2" symbolic-ref -q --short HEAD)" = r1392-x ] && ok "W2 루트 가지 그대로(자동 되돌림 0)" || bad "W2 루트가 바뀜"
  # W5 — 하네스 밖 카드 → 출력 0 · 팩 쪽 동작 0(루트가 가지여도)
  O="$(FT_PACK_ROOT="$P2" pack_wt_prepare "$T/p.md" s5 nano/s5 0)"; RC=$?
  [ "$RC" = 0 ] && [ -z "$O" ] && [ ! -e "$P2/.worktrees/s5" ] && ok "W5 하네스 밖 = 출력 0 · 동작 0" || bad "W5 rc=$RC «${O}»"
  # 판정 불가 — 팩 루트 폴더 없음 = REJECT(조용한 통과 0)
  O="$(FT_PACK_ROOT="$T/none" pack_wt_prepare "$T/h.md" s6 nano/s6 0)"; RC=$?
  [ "$RC" = 1 ] && has "판정 불가 REJECT(폴더 없음)" "$O" "REJECT 팩 루트 판정 불가" || bad "판정 불가 rc=$RC «${O}»"
fi

[ -n "${FT_R1408_SPAWN:-}" ] && { echo; [ "$fail" -eq 0 ] && { echo "ALL PASS(변이 함수 칸)"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }

# ── S 정적: 호출 자리 · 발주 줄 · 짝 ──
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "S bin·kit cmp0" || bad "S bin·kit 다름"
/bin/bash -n "$BIN/ft-nano-spawn.sh" && ok "S /bin/bash 3.2 -n" || bad "S bash 3.2 구문"
lc="$(grep -n '^_PKW="$(pack_wt_prepare "$IDX" "$SLUG" "$BRANCH" "$DRY")" || { printf' "$BIN/ft-nano-spawn.sh" | head -1 | cut -d: -f1)"
ld="$(grep -n '^if \[ "$DRY" = 1 \]; then .*--dry-run; exit 0; fi' "$BIN/ft-nano-spawn.sh" | head -1 | cut -d: -f1)"
lo="$(grep -n '"${OPEN\[@\]}"' "$BIN/ft-nano-spawn.sh" | grep -v -- '--dry-run' | head -1 | cut -d: -f1)"
{ [ -n "$lc" ] && [ -n "$ld" ] && [ -n "$lo" ] && [ "$lc" -lt "$ld" ] && [ "$lc" -lt "$lo" ]; } && ok "S 호출 자리 = dry-run 종료($ld)·좌석 열기($lo) 앞($lc) · 실패 exit 1" || bad "S 호출 자리 lc=$lc ld=$ld lo=$lo"
eval "$(awk '/^pack_wt_line\(\) \{/,/^\}/' "$BIN/ft-nano-spawn.sh")"
O="$(FT_PACK_ROOT=/x/pack pack_wt_line "$T/h.md" s1 nano/s1)"
has "S 발주 줄 = 이미 만들어 둠" "$O" "팩 작업 폴더 = /x/pack/.worktrees/s1 (이미 만들어 둠"
has "S 발주 줄 = 루트 checkout/switch 금지" "$O" "팩 루트 /x/pack 에서 checkout/switch 금지"

# ── 실 spawn --dry-run 한 바퀴(r1398 대역): 루트가 가지 = REJECT rc1 · tmuxc·명부 0 / detached = 만들 예정 rc0 ──
SB="$T/bin"; bash "$HERE/lib/kit_bin_copy.sh" "$SB" >/dev/null || { echo "FAIL 임시 bin 사본 실패"; exit 1; }
cp "$BIN/ft-nano-spawn.sh" "$SB/ft-nano-spawn.sh"
mkdir -p "$T/fake"; TL="$T/tmuxlog"; : > "$TL"
printf '#!/bin/sh\necho "LINT-OK"\nexit 0\n' > "$SB/ft-index-lint.sh"
printf '#!/bin/sh\necho gate-ok\nexit 0\n' > "$SB/ft-proposal-gate.sh"
printf 'import sys\nsys.exit(0)\n' > "$SB/ft_card_map_lint.py"
printf '#!/bin/sh\necho "tmux $*" >> "%s"\ncase "$1" in list-sessions) exit 0;; *) exit 1;; esac\n' "$TL" > "$T/fake/tmux"
printf '#!/bin/sh\necho "tmuxc $*" >> "%s"\necho "TMUXC-DRY $*"\n' "$TL" > "$T/fake/tmuxc"; chmod 755 "$T/fake/tmux" "$T/fake/tmuxc"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T" ok
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-alpha-master-claude#1
R1="$T/repo"; mkdir -p "$R1/design/alpha/indices/대기" "$R1/.fable-team/comm" "$R1/.fable-team/state" "$T/tmp"
G init -q "$R1"; G -C "$R1" commit -q --allow-empty -m init
echo '{"_name":"alpha"}' > "$R1/.fable-team/seats-alpha.json"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$R1/.fable-team/state/all-stop.log"
printf '# 인덱스: x\n%s\n## 상태\n' "$MARK" > "$R1/design/alpha/indices/대기/x.md"
SEATS_MD5="$(md5 -q "$R1/.fable-team/seats-alpha.json" 2>/dev/null || md5sum "$R1/.fable-team/seats-alpha.json" | cut -d' ' -f1)"
printf '목표는 AAAA 이다.\n목표는 BBBB 이다.\n목표는 CCCC 이다.\n' > "$T/goal3.txt"
spr() { ( cd "$R1" && FT_ROOT="$R1" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$R1/.fable-team/seats-alpha.json" \
          FT_TEAMSET=0 FT_CARD_FLOW=0 FT_ACCT_ASSIGN=0 FT_GOAL_LINES_FILE="$T/goal3.txt" FT_PACK_ROOT="$1" \
          TMPDIR="$T/tmp" PATH="$T/fake:$PATH" bash "$SB/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 --dry-run 2>&1 ); }
O="$(spr "$P2")"; RC=$?
[ "$RC" = 1 ] && has "W2 실 spawn --dry-run REJECT" "$O" "REJECT 팩 루트가 가지 r1392-x 에 있음" || bad "W2 실 spawn rc=$RC ← $(printf '%s' "$O" | tail -5 | tr '\n' ';')"
grep -q '^tmuxc' "$TL" && bad "W2 실 spawn tmuxc 호출됨" || ok "W2 실 spawn tmuxc 0"
[ ! -d "$R1/.worktrees" ] && [ ! -e "$P2/.worktrees/x" ] && ok "W2 실 spawn 워크트리 0(BYZ·팩)" || bad "W2 실 spawn 워크트리 생김"
NOW_MD5="$(md5 -q "$R1/.fable-team/seats-alpha.json" 2>/dev/null || md5sum "$R1/.fable-team/seats-alpha.json" | cut -d' ' -f1)"
[ "$SEATS_MD5" = "$NOW_MD5" ] && ok "W2 실 spawn 명부 불변" || bad "W2 실 spawn 명부 바뀜"
: > "$TL"; O="$(spr "$P")"; RC=$?
[ "$RC" = 0 ] && has "D 실 spawn --dry-run = 만들 예정" "$O" "PACK-WT $P/.worktrees/x 만들 예정(dry-run" || bad "D 실 spawn rc=$RC ← $(printf '%s' "$O" | tail -5 | tr '\n' ';')"
has "D 실 spawn 발주 줄(이미 만들어 둠)" "$O" "팩 작업 폴더 = $P/.worktrees/x (이미 만들어 둠"
[ ! -e "$P/.worktrees/x" ] && ok "D 실 spawn 팩 쓰기 0" || bad "D 실 spawn 팩 폴더 생김"

echo; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
