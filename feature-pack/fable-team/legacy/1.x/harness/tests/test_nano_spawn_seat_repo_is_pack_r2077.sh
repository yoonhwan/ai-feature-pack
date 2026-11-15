#!/usr/bin/env bash
# test_nano_spawn_seat_repo_is_pack_r2077.sh — 카드 r2077: 좌석 리포 = 팩 리포(aifp 팀)면 ft-nano-spawn 이 팩 작업 폴더를 따로 만들지 않는다.
#   왜: spawn 이 팩 작업 폴더를 가지 nano/<slug> 로 먼저 만들고, 뒤따르는 좌석 worktree add -b 가 같은 리포에서 «branch already exists» 로 죽었다(aifp master#17 실사건).
#   ① N1 같은 리포 판정 = ROOT 물리 경로 == 팩 루트 물리 경로(심링크 · 다른 리포 · ROOT 없음 · 빈 글 · 없는 폴더)
#   ② N2 실사건 꼴: 건너뜀 1줄 · 팩 폴더·가지 0 · 이어서 좌석 worktree add -b rc0
#   ③ N2 관문 순서: 루트 가지 side = REJECT 먼저 · dry-run = 건너뜀 · 남은 폴더(같은 가지 · 다른 가지) 손 0
#   ④ N3 발주 줄: 같은 리포 = «이 좌석 워크트리» 줄 · 다른 리포 = 기준판 글자 · 팩 카드 아님 = 0
#   ⑤ N4 불변: 팩 카드 아님 = 0 · 기존 r1408·r1205 시험 · bin·kit cmp0 · 두 함수 밖 diff 0(origin/main 대비) · 실 팩 워크트리 목록 앞뒤 같음
# 변이·기준판: FT_R2077_SPAWN=<사본> → 함수 칸(①~④ · ⑤ 첫 칸)만 그 사본으로 돈다.
# 꼴 = 임시 «팩 꼴» 리포(bare 원격 + 루트) · 두 함수를 awk 로 꺼내 eval · 실 팩 쓰기·실 명부·실 tmux 0 · sleep 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
SPAWN="${FT_R2077_SPAWN:-$BIN/ft-nano-spawn.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$BIN/ft-team-lib.sh"   # ft_pack_card · ft_git_capped
REAL="$HOME/Project/ai-feature-pack"
real_wts() { git -C "$REAL" worktree list --porcelain 2>/dev/null | grep -c '^worktree '; }
REAL0="$(real_wts)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — 없음 «$3» ← ${2:0:300}";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — 있음 «$3»";; *) ok "$1";; esac; }
G() { git -c user.name=t -c user.email=t@t "$@"; }
mkpack() {  # $1 폴더 → 루트(main 가지 · origin/main) 경로
  local d="$1"; mkdir -p "$d"
  G init -q --bare "$d/origin.git"; G clone -q "$d/origin.git" "$d/seed" 2>/dev/null
  echo a > "$d/seed/a"; G -C "$d/seed" add a; G -C "$d/seed" commit -qm a; G -C "$d/seed" push -q origin HEAD:main 2>/dev/null
  G clone -q -b main "$d/origin.git" "$d/pack" 2>/dev/null; printf '%s\n' "$d/pack"
}
br() { G -C "$1" rev-parse -q --verify "refs/heads/$2" >/dev/null && echo 있음 || echo 없음; }
printf '# 인덱스: h\n<!-- ledger: design/harness/GOAL-harness.md -->\n- 설치: 있음\n\n## 상태\n' > "$T/h.md"
printf '# 인덱스: p\n<!-- ledger: design/v65/GOAL-LEDGER-v65.md -->\n- 설치: 있음\n\n## 상태\n' > "$T/p.md"
SKIP="PACK-WT 건너뜀 — 좌석 리포 = 팩 리포"

fp="$(awk '/^pack_wt_prepare\(\) \{/,/^\}/' "$SPAWN")"; fl="$(awk '/^pack_wt_line\(\) \{/,/^\}/' "$SPAWN")"
if [ -z "$fp" ] || [ -z "$fl" ]; then bad "함수 없음(pack_wt_prepare/pack_wt_line)"; else
  eval "$fp"; eval "$fl"
  # ① N1 — 심링크 경로 ROOT = 같은 리포
  P="$(mkpack "$T/n1")"; ln -s "$P" "$T/n1-link"
  O="$(ROOT="$T/n1-link" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && has "① 심링크 ROOT = 건너뜀" "$O" "$SKIP($P)" || bad "① 심링크 rc=$RC «${O}»"
  [ ! -e "$P/.worktrees/s1" ] && ok "① 심링크 팩 폴더 0" || bad "① 심링크 팩 폴더 생김"
  #   다른 리포 ROOT → 만듦(기준판과 같음)
  Q="$(mkpack "$T/n1b")"; P="$(mkpack "$T/n1c")"
  O="$(ROOT="$Q" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && [ "$O" = "PACK-WT $P/.worktrees/s1 만듦" ] && [ "$(br "$P" nano/s1)" = 있음 ] && ok "① 다른 리포 = 만듦 · 폴더·가지" || bad "① 다른 리포 rc=$RC «${O}»"
  #   ROOT 없음 · 빈 글 · 없는 폴더 → 만듦
  O="$(unset ROOT; FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" u1 nano/u1 0)"
  [ "$O" = "PACK-WT $P/.worktrees/u1 만듦" ] && ok "① ROOT 없음 = 만듦" || bad "① ROOT 없음 «${O}»"
  O="$( (cd "$P" && ROOT="" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" u2 nano/u2 0) )"
  [ "$O" = "PACK-WT $P/.worktrees/u2 만듦" ] && ok "① ROOT 빈 글(cwd = 팩 루트) = 만듦" || bad "① ROOT 빈 글 «${O}»"
  O="$(ROOT="$T/none" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" u3 nano/u3 0)"
  [ "$O" = "PACK-WT $P/.worktrees/u3 만듦" ] && ok "① ROOT 없는 폴더 = 만듦" || bad "① ROOT 없는 폴더 «${O}»"
  # ② N2 실사건 꼴 — 건너뜀 · 폴더·가지 0 · 좌석 worktree add -b rc0
  P="$(mkpack "$T/n2")"
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && [ "$O" = "$SKIP($P) · 좌석 워크트리에서 일한다" ] && ok "② 건너뜀 1줄 rc0" || bad "② rc=$RC «${O}»"
  [ ! -e "$P/.worktrees/s1" ] && [ "$(br "$P" nano/s1)" = 없음 ] && ok "② 팩 폴더·가지 0" || bad "② 팩 폴더나 가지 생김"
  E="$(G -C "$P" worktree add -q --no-checkout "$P/.worktrees/aifp-ft-s1" -b nano/s1 origin/main 2>&1)"; RC=$?
  [ "$RC" = 0 ] && ok "② 좌석 worktree add -b rc0" || bad "② 좌석 worktree add rc=$RC «${E}»"
  # ③ N2 관문 순서
  P="$(mkpack "$T/n3a")"; G -C "$P" checkout -q -b side
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 1 ] && has "③ 루트 가지 side = REJECT 먼저" "$O" "REJECT 팩 루트가 가지 side 에 있음" || bad "③ side rc=$RC «${O}»"
  [ ! -e "$P/.worktrees/s1" ] && [ "$(br "$P" nano/s1)" = 없음 ] && ok "③ side 쓰기 0" || bad "③ side 쓰기 생김"
  P="$(mkpack "$T/n3b")"
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 1)"; RC=$?
  [ "$RC" = 0 ] && has "③ dry-run = 건너뜀" "$O" "$SKIP($P)" || bad "③ dry-run rc=$RC «${O}»"
  [ ! -e "$P/.worktrees/s1" ] && [ "$(br "$P" nano/s1)" = 없음 ] && ok "③ dry-run 폴더·가지 0" || bad "③ dry-run 쓰기 생김"
  P="$(mkpack "$T/n3c")"; G -C "$P" worktree add -q -b nano/s1 "$P/.worktrees/s1" origin/main 2>/dev/null; H0="$(G -C "$P/.worktrees/s1" rev-parse HEAD)"
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && has "③ 남은 폴더(같은 가지) = 건너뜀" "$O" "$SKIP($P)" || bad "③ 남은 폴더 rc=$RC «${O}»"
  [ "$(G -C "$P/.worktrees/s1" symbolic-ref -q --short HEAD)" = nano/s1 ] && [ "$(G -C "$P/.worktrees/s1" rev-parse HEAD)" = "$H0" ] && ok "③ 남은 폴더·가지 그대로" || bad "③ 남은 폴더 바뀜"
  G -C "$P" worktree add -q -b other "$P/.worktrees/s4" origin/main 2>/dev/null
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/h.md" s4 nano/s4 0)"; RC=$?
  [ "$RC" = 0 ] && has "③ 남은 폴더(다른 가지) = 건너뜀" "$O" "$SKIP($P)" || bad "③ 다른 가지 rc=$RC «${O}»"
  [ "$(G -C "$P/.worktrees/s4" symbolic-ref -q --short HEAD)" = other ] && [ "$(br "$P" nano/s4)" = 없음 ] && ok "③ 다른 가지 폴더 그대로" || bad "③ 다른 가지 폴더 바뀜"
  # ④ N3 발주 줄
  P="$(mkpack "$T/n4")"
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_line "$T/h.md" s1 nano/s1)"
  has "④ 같은 리포 = 이 좌석 워크트리" "$O" "팩 작업 폴더 = 이 좌석 워크트리(좌석 리포 = 팩 리포 · 가지 nano/s1 · 팩 루트 $P 에서 checkout/switch 금지"
  hasnt "④ 같은 리포 «이미 만들어 둠» 0" "$O" "이미 만들어 둠"; hasnt "④ 같은 리포 «nano-close --wt» 0" "$O" "nano-close --wt"
  O="$(ROOT="$T/n1b/pack" FT_PACK_ROOT=/x/pack pack_wt_line "$T/h.md" s1 nano/s1)"
  [ "$O" = " ★팩 작업 폴더 = /x/pack/.worktrees/s1 (이미 만들어 둠 · 가지 nano/s1 · 팩 루트 /x/pack 에서 checkout/switch 금지 · 세션 스크래치 0 — 닫기 = nano-close --wt /x/pack/.worktrees/s1 --branch nano/s1)★" ] && ok "④ 다른 리포 = 기준판 글자" || bad "④ 다른 리포 «${O}»"
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_line "$T/p.md" s1 nano/s1)"
  [ -z "$O" ] && ok "④ 같은 리포 · 팩 카드 아님 = 0" || bad "④ 팩 카드 아님 «${O}»"
  # ⑤ N4 — 같은 리포 · 팩 카드 아님 = prepare 출력 0 · 쓰기 0
  O="$(ROOT="$P" FT_PACK_ROOT="$P" pack_wt_prepare "$T/p.md" s1 nano/s1 0)"; RC=$?
  [ "$RC" = 0 ] && [ -z "$O" ] && [ ! -e "$P/.worktrees/s1" ] && [ "$(br "$P" nano/s1)" = 없음 ] && ok "⑤ 팩 카드 아님 = 출력 0 · 쓰기 0" || bad "⑤ 팩 카드 아님 rc=$RC «${O}»"
fi
[ -n "${FT_R2077_SPAWN:-}" ] && { echo; [ "$fail" -eq 0 ] && { echo "ALL PASS(변이 함수 칸)"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }

# ⑤ 불변 — 기존 시험 · cmp · 두 함수 밖 diff 0 · 실 팩 워크트리 목록
for t in test_nano_spawn_pack_wt_r1408.sh test_nano_spawn_pack_wt_line_r1205.sh; do
  O="$(bash "$HERE/$t" 2>&1)"; RC=$?
  [ "$RC" = 0 ] && ok "⑤ $t rc0 PASS=$(grep -c '^PASS' <<<"$O")" || bad "⑤ $t rc=$RC ← $(grep '^FAIL' <<<"$O" | head -3 | tr '\n' ';')"
done
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "⑤ bin·kit cmp0" || bad "⑤ bin·kit 다름"
/bin/bash -n "$BIN/ft-nano-spawn.sh" && ok "⑤ /bin/bash 3.2 -n" || bad "⑤ bash 3.2 구문"
strip() { awk '/^pack_wt_(prepare|line)\(\) \{/{s=1} !s{print} s&&/^\}/{s=0}'; }
BASE="$(git -C "$REPO" show origin/main:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-spawn.sh 2>/dev/null)"
if [ -z "$BASE" ]; then bad "⑤ 기준판(origin/main) 판정 불가"
elif [ "$(printf '%s\n' "$BASE" | strip)" = "$(strip < "$BIN/ft-nano-spawn.sh")" ]; then ok "⑤ 두 함수 밖 diff 0(origin/main 대비)"
else bad "⑤ 두 함수 밖이 바뀜"; fi
[ "$(real_wts)" = "$REAL0" ] && ok "⑤ 실 팩 워크트리 목록 앞뒤 같음($REAL0)" || bad "⑤ 실 팩 워크트리 수 $REAL0 → $(real_wts)"

echo; [ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
