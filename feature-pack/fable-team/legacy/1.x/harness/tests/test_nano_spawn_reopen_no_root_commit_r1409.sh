#!/usr/bin/env bash
# test_nano_spawn_reopen_no_root_commit_r1409.sh — r1409: ft-nano-spawn.sh --reopen 이 «공용 루트» 카드에 로컬 커밋을 남기지 않는다
#   루트 판별 = 기계 루트 명부(roots.tsv · FT_ROOTS_TSV)의 경로 = 카드 체크아웃. 루트면 origin/main 사본에서 커밋 → docs push(루트 커밋 0 · 루트 작업본 쓰기 0).
#   전부 mktemp — bare 원격 + «루트» 클론 + 전용 워크트리 + 가짜 tmux·tmuxc·형제 도구. 실 좌석·실 명부·실 tmux·mbox 0. 자기 재호출 0(변이 = R1409_BIN 사본).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
[ -z "${R1409_REENTRY:-}" ] || { echo "ERROR r1409 재진입 차단(R1409_REENTRY)"; exit 2; }; export R1409_REENTRY=1
export FT_TEAMSET=0 FT_CARD_FLOW=0 FT_NANO_SPARSE=0 FT_RECLAIM=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_SEND_FROM='byz-v65-master-claude#1'
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; SRCBIN="${R1409_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-v65-master-claude#1
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
export FT_HEAVY_DIR="$T/heavy"
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

bash -n "$SRCBIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n"
[ -n "${R1409_BIN:-}" ] || { cmp -s "$SRCBIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "키트 사본 cmp 0" || bad "키트 사본 어긋남"; }

# ── 임시 원격(bare) + «루트» 클론 + 가짜 도구 ──
O="$T/origin.git"; R="$T/root"; B="$T/bin"; SEATS="$R/.fable-team/seats.json"
git init -q --bare -b main "$O"
git clone -q "$O" "$R" 2>/dev/null
mkdir -p "$R/.fable-team/state" "$R/.fable-team/comm" "$R/design/v65/indices/대기" "$R/design/v65/indices/진행" "$B" "$T/sess" "$T/fake"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
: > "$R/.gitkeep"; printf 'x\n' > "$R/design/v65/SEATBELT-README.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
# 루트 명부 — 이 파일의 «경로 칸» 이 공용 루트 판별의 유일 출처다(탭 6칸)
printf '# 기계 루트 명부 (r1409 시험)\nr1409\t%s\t현역\torigin/main\t.\t기본\n' "$R" > "$T/roots.tsv"
printf '# 인덱스: r1409w\n- Issue: #1\n- 배정: 없음\n## 상태\n- 2026-11-05 대기\n' > "$R/design/v65/indices/대기/r1409w.md"
git -C "$R" add -A && git -C "$R" commit -q -m init && git -C "$R" push -q origin main; export FT_TEAMS_REF=origin/main
cp -p "$SRCBIN"/* "$B"/ 2>/dev/null
for f in ft-index-lint.sh ft-proposal-gate.sh ft-agent-ready.sh ft-spawn-issue-gate.sh ft-resource-sample.sh ft-all-stop.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\nexit 0\n' > "$B/ft-sheet-events.sh"
printf '#!/bin/bash\necho "$*" >> "%s/move.log"\nexit 0\n' "$T" > "$B/ft-index-move.sh"                                             # 이동 호출 기록(E4)
printf '#!/bin/bash\necho "NOT-LANDED"\nexit 1\n' > "$B/ft-nano-cherry-gate.sh"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/send.log"\nexit 0\n' "$T" > "$B/ft-send-verified.sh"
printf '#!/bin/bash\necho "reclaim $*" >> "%s/reclaim.log"\nexit 0\n' "$T" > "$B/ft-resource-reclaim.sh"
printf '#!/bin/bash\necho "tmuxc $*" >> "%s/calls.log"\nif [ "$1" = open ]; then n=""; dry=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && dry=1; shift; done; [ $dry = 1 ] || : > "%s/sess/$n"; fi\n' "$T" "$T" > "$T/fake/tmuxc"
printf '#!/bin/bash\necho "tmux $*" >> "%s/calls.log"\ncase "$1" in\n has-session) [ -e "%s/sess/${3#=}" ];;\n list-sessions) ls "%s/sess" 2>/dev/null; exit 0;;\n list-panes) for s in "%s"/sess/*; do [ -e "$s" ] && echo "$(basename "$s")|%%1|1700000000"; done; exit 0;;\n show-option) echo 1;;\n *) exit 0;;\nesac\n' "$T" "$T" "$T" "$T" > "$T/fake/tmux"
chmod +x "$B"/*.sh "$T/fake/tmuxc" "$T/fake/tmux"
ST_SEATS='{"_master":"byz-v65-master-claude#1","byz-v65-master-claude#1":{"role":"master","agent":"claude","tick":null}}'
reset() {
  git -C "$R" fetch -q origin; git -C "$R" reset -q --hard origin/main
  for w in $(git -C "$R" worktree list --porcelain | sed -n 's|^worktree ||p'); do case "$w" in "$R") ;; *) git -C "$R" worktree remove --force "$w" >/dev/null 2>&1;; esac; done
  rm -rf "$R/.worktrees" "$T/teamwt" "$T/sess" "$R/.fable-team/state/card-assign"; mkdir -p "$T/sess"
  git -C "$R" worktree prune
  for b in $(git -C "$R" for-each-ref --format='%(refname:short)' 'refs/heads/nano/*' 'refs/heads/cardwt'); do git -C "$R" branch -D -q "$b" >/dev/null 2>&1; done
  printf '%s\n' "$ST_SEATS" > "$SEATS"; : > "$T/calls.log"; rm -f "$T/move.log" "$T/send.log" "$T/reclaim.log"
  git -C "$R" remote set-url --push origin "$O"
}
newcard() {  # $1 = slug — 진행/ 카드 1장을 «원격 카드» 로(루트 main == origin/main) · base_sha = 있음(진짜 재개 카드는 첫 spawn 에서 이미 찍혔다)
  printf '# 인덱스: %s\n- Issue: #1\n- base_sha: %s (spawn 2026-11-05)\n- 배정: 없음\n## 상태\n- 2026-11-05 진행\n' "$1" "$(git -C "$R" rev-parse origin/main)" > "$R/design/v65/indices/진행/$1.md"
  git -C "$R" add -A; git -C "$R" commit -q -m "card $1"; git -C "$R" push -q origin main
}
SP()  { local c="$1"; shift; (cd "$R" && PATH="$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" FT_ROOTS_TSV="$T/roots.tsv" bash "$B/ft-nano-spawn.sh" "$R/design/v65/indices/$c" "$@" 2>&1); }
SPW() { local c="$1"; shift; (cd "$T/teamwt" && PATH="$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" FT_ROOTS_TSV="$T/roots.tsv" bash "$B/ft-nano-spawn.sh" "$T/teamwt/design/v65/indices/$c" "$@" 2>&1); }
SPM() { local m="$1" c="$2"; shift 2; (cd "$R" && PATH="$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" FT_ROOTS_TSV="$T/roots.tsv" bash "$T/mut-$m/ft-nano-spawn.sh" "$R/design/v65/indices/$c" "$@" 2>&1); }
mutant() {  # $1 = 이름 $2 = 찾을 글자 $3 = 바꿀 글자 — 마커 글자가 정확히 1회 있어야 한다(없으면 변이 실패 = 시험 실패)
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; find "$B" -maxdepth 1 -type f -exec cp -p {} "$d"/ \;
  python3 - "$d/ft-nano-spawn.sh" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    print(f"MUTANT-BAD 찾을 글자 {s.count(old)}회: {old[:60]}")
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
root_extra() { git -C "$R" rev-list --count main --not --remotes=origin; }   # 루트에만 있는 커밋 수
origin_card() { git -C "$R" show "origin/main:design/v65/indices/진행/$1.md" 2>/dev/null; }

# ── E1 공용 루트 카드 + --reopen → origin 사본 커밋·push · 루트 커밋 0 · origin 카드에 재개 줄 1 ──
reset; newcard r1409a
o="$(SP 진행/r1409a.md --reopen)"; rc=$?
rc_is "$rc" 0 "E1 rc"
has "$o" "REOPEN-CARD origin ←" "E1 origin/main 사본에서 커밋·push"
has "$o" "wt=" "E1 REOPEN 원문 유지"
eq "$(root_extra)" 0 "E1 루트에 origin 에 없는 커밋 0"
[ -z "$(git -C "$R" status --porcelain -- design)" ] && ok "E1 루트 카드 변경 0" || bad "E1 루트 카드 변경됨: $(git -C "$R" status --porcelain -- design)"
eq "$(grep -c '재개(--reopen)' "$R/design/v65/indices/진행/r1409a.md")" 0 "E1 루트 카드에 재개 줄 0"
eq "$(origin_card r1409a | grep -c '재개(--reopen)')" 1 "E1 origin 카드에 재개 줄 1"
has "$(origin_card r1409a)" "좌석 byz-v65-nano-r1409a#0" "E1 origin 카드 거울 = 새 좌석"
eq "$(origin_card r1409a | grep -c '^- 배정: ')" 1 "E1 origin 카드 거울 줄 1개(사본에서 같은 함수로) "
[ -e "$T/sess/byz-v65-nano-r1409a#0" ] && ok "E1 좌석 열림" || bad "E1 좌석 없음"

# ── E2 E1 꼴 + push 실패(대역 원격 막음) → WARN 1줄 · 루트 커밋 0 · 루트 작업본 변경 0 ──
reset; newcard r1409b; git -C "$R" remote set-url --push origin "$T/없는원격.git"
o="$(SP 진행/r1409b.md --reopen)"; rc=$?
rc_is "$rc" 0 "E2 rc(좌석은 열린다)"
has "$o" "WARN 재개 줄 push 실패 — 좌석은 열렸다 · 카드 변경은 사본에만" "E2 WARN 1줄"
eq "$(root_extra)" 0 "E2 루트에 origin 에 없는 커밋 0"
[ -z "$(git -C "$R" status --porcelain -- design)" ] && ok "E2 루트 카드 변경 0" || bad "E2 루트 카드 변경됨"
eq "$(origin_card r1409b | grep -c '재개(--reopen)')" 0 "E2 origin 카드 불변(push 실패)"
[ -e "$T/sess/byz-v65-nano-r1409b#0" ] && ok "E2 좌석은 열렸다" || bad "E2 좌석 없음"

# ── E3 전용 워크트리 카드 + --reopen → 지금처럼 그 워크트리에 커밋 1(동작 불변) ──
reset; git -C "$R" worktree add -q "$T/teamwt" -b cardwt origin/main
cardwt() { printf '# 인덱스: r1409c\n- Issue: #1\n- base_sha: %s (spawn 2026-11-05)\n- 배정: 없음\n## 상태\n- 2026-11-05 진행\n' "$(git -C "$T/teamwt" rev-parse origin/main)" > "$T/teamwt/design/v65/indices/진행/r1409c.md"; git -C "$T/teamwt" add -A; git -C "$T/teamwt" commit -q -m "card r1409c"; }
cardwt
o="$(SPW 진행/r1409c.md --reopen)"; rc=$?
rc_is "$rc" 0 "E3 rc"
hasnt "$o" "REOPEN-CARD origin ←" "E3 사본 길 안 씀(전용 워크트리)"
eq "$(git -C "$T/teamwt" log -1 --format=%s)" "[docs] r1409c 재개(--reopen) — 좌석 byz-v65-nano-r1409c#0 · wt=새로" "E3 그 워크트리에 카드 커밋 1"
eq "$(git -C "$T/teamwt" log --oneline origin/main..cardwt | wc -l | tr -d ' ')" 2 "E3 카드 커밋 + 재개 커밋(지금 그대로)"
eq "$(origin_card r1409c | grep -c '재개(--reopen)')" 0 "E3 origin 카드 불변(push 는 기존 호출자 몫)"

# ── E4 --reopen 아님(대기→진행) → 지금과 같음(ft-index-move 1회) ──
reset
o="$(SP 대기/r1409w.md)"; rc=$?
rc_is "$rc" 0 "E4 rc"
eq "$(grep -c '' "$T/move.log" 2>/dev/null || echo 0)" 1 "E4 ft-index-move 1회"
has "$(cat "$T/move.log" 2>/dev/null)" "대기/r1409w.md 진행" "E4 이동 인자 그대로"
hasnt "$o" "REOPEN-CARD" "E4 사본 길 0"

# ── E5 r1390: 공용 루트 --reopen + origin/main 위 아닌 --base + --base-reason → origin 카드에 base_reason 1줄 · 명부 base_reason · 루트 카드 0 ──
unl() { git -C "$R" commit-tree "HEAD^{tree}" -p HEAD -m unlanded; }   # 가지 안 바꾼 미착지 커밋 1개
reset; newcard r1409e; U="$(unl)"
o="$(SP 진행/r1409e.md --reopen --base "$U" --base-reason "선행 카드 위에서")"; rc=$?
rc_is "$rc" 0 "E5 rc"
has "$o" "REOPEN-CARD origin ←" "E5 origin/main 사본에서 커밋·push"
eq "$(origin_card r1409e | grep -c "^- base_reason: $U(${U:0:10}) origin/main 위 아님 — 선행 카드 위에서$")" 1 "E5 origin 카드에 base_reason 줄 1"
eq "$(grep -c 'base_reason' "$R/design/v65/indices/진행/r1409e.md")" 0 "E5 루트 카드에 base_reason 0"
eq "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["byz-v65-nano-r1409e#0"].get("base_reason",""))' "$SEATS")" "선행 카드 위에서" "E5 명부 base_reason 칸"
eq "$(root_extra)" 0 "E5 루트에 origin 에 없는 커밋 0"

# ── E6 r1390: 전용 워크트리 --reopen + 같은 사유 → 그 워크트리 카드에 base_reason 1줄(로컬 길) ──
reset; git -C "$R" worktree add -q "$T/teamwt" -b cardwt origin/main; cardwt; U="$(unl)"
o="$(SPW 진행/r1409c.md --reopen --base "$U" --base-reason "선행 카드 위에서")"; rc=$?
rc_is "$rc" 0 "E6 rc"
eq "$(grep -c "^- base_reason: $U(${U:0:10}) origin/main 위 아님 — 선행 카드 위에서$" "$T/teamwt/design/v65/indices/진행/r1409c.md")" 1 "E6 워크트리 카드에 base_reason 줄 1"

# ── 변이 3개: 계약이 실제로 시험을 통해 잡히나 ──
_rc_old='  local rt p q no=0 name where rest'
mutant m1 "$_rc_old" '  local rt p q no=0 name where rest; return 1' && ok "변이 1 사본(루트 판별 삭제)" || bad "변이 1 사본 실패"
reset; newcard r1409a; SPM m1 진행/r1409a.md --reopen >/dev/null 2>&1
eq "$(root_extra)" 1 "변이 1 → E1 FAIL(루트 로컬 커밋 1)"

mutant m2 'echo "WARN 재개 줄 push 실패 — 좌석은 열렸다 · 카드 변경은 사본에만: $wt (push rc=$rc' \
          'card_note "$IDX_WT/$rel" "$note" >/dev/null 2>&1; git -C "$IDX_WT" add -- "$rel" >/dev/null 2>&1; git -C "$IDX_WT" commit -q -m "[docs] ${SLUG} 재개(--reopen) — 좌석 $NAME" -- "$rel" >/dev/null 2>&1; echo "WARN 재개 줄 push 실패 — 좌석은 열렸다 · 카드 변경은 사본에만: $wt (push rc=$rc' \
  && ok "변이 2 사본(push 실패 때 루트 작업본에 씀)" || bad "변이 2 사본 실패"
reset; newcard r1409b; git -C "$R" remote set-url --push origin "$T/없는원격.git"; SPM m2 진행/r1409b.md --reopen >/dev/null 2>&1
eq "$(root_extra)" 1 "변이 2 → E2 FAIL(루트 커밋 1)"

mutant m3 '_REOPEN_ROOT=0
if [ "$REOPEN" = 1 ]' '_REOPEN_ROOT=1
if [ "$REOPEN" = 1 ]' && ok "변이 3 사본(전용 워크트리까지 사본 길로)" || bad "변이 3 사본 실패"
reset; git -C "$R" worktree add -q "$T/teamwt" -b cardwt origin/main
cardwt
(cd "$R" && PATH="$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" FT_ROOTS_TSV="$T/roots.tsv" bash "$T/mut-m3/ft-nano-spawn.sh" "$T/teamwt/design/v65/indices/진행/r1409c.md" --reopen >/dev/null 2>&1)
eq "$(git -C "$T/teamwt" log --oneline origin/main..cardwt | wc -l | tr -d ' ')" 1 "변이 3 → E3 FAIL(그 워크트리에 재개 커밋 0)"

mutant m4 '  if [ -n "${_BR_LINE:-}" ] && ! card_note "$wt/$rel"' '  if false && ! card_note "$wt/$rel"' && ok "변이 4 사본(origin 사본에 base_reason 안 넘김 · DA R2)" || bad "변이 4 사본 실패"
reset; newcard r1409e; U="$(unl)"; SPM m4 진행/r1409e.md --reopen --base "$U" --base-reason "선행 카드 위에서" >/dev/null 2>&1
eq "$(origin_card r1409e | grep -c '^- base_reason: ')" 0 "변이 4 → E5 FAIL(origin 카드 base_reason 0)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
