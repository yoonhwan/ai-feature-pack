#!/usr/bin/env bash
# test_cherry_gate_time_cap_r1470.sh — r1470: cherry 게이트 자체 시간 상한(FT_CHERRY_GATE_SEC · 기본 25) + spawn ②-0 timeout 감싸기.
# 전부 mktemp — 임시 git 리포 + PATH 앞 가짜 git(log --raw·cherry 만 sleep 2 뒤 진짜 git 위임) + 가짜 tmux·tmuxc·형제 도구. 실 리포·실 가지·실 좌석 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_TEAMSET=0 FT_CARD_FLOW=0 FT_NANO_SPARSE=0 FT_RECLAIM=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CHERRY_GATE_SEC
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export FT_SEND_FROM='byz-v65-master-claude#1'
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PACK="$HERE/../.."; SRCBIN="$PACK/harness/bin"; KIT="$PACK/harness/kit/fable-team/bin"; G="$SRCBIN/ft-nano-cherry-gate.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}» ← ${1:0:600}";; *) ok "$3";; esac; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }

for f in ft-nano-cherry-gate.sh ft-nano-spawn.sh; do
  bash -n "$SRCBIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$SRCBIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"
done

# ── 가짜 git: 호출 기록 + FAKE_SLOW=log(log --raw 만) | cherry 면 sleep 2 뒤 진짜 git ──
REAL_GIT="$(command -v git)"; mkdir -p "$T/fk"
cat > "$T/fk/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${FAKE_GIT_LOG:-/dev/null}"
case " \$* " in
  *" log "*"--raw"*) [ "\${FAKE_SLOW:-}" = log ] && sleep 2 ;;
  *" cherry "*) [ "\${FAKE_SLOW:-}" = cherry ] && sleep 2 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/fk/git"

# ── 리포: main 과 nano/x 가 app/a·b·c 를 서로 다르게 고침 → merge-tree 충돌 → «+» 경로 3개를 경로별 log 로 판정(끝까지 돌면 REJECT) ──
R="$T/repo"; git init -q -b main "$R"
w() { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }
cm() { git -C "$R" add -A && git -C "$R" commit -qm "$1"; }
w app/a.py a0; w app/b.py b0; w app/c.py c0; cm base
git -C "$R" checkout -q -b nano/x; w app/a.py a1; w app/b.py b1; w app/c.py c1; cm "[feature] nano"
git -C "$R" checkout -q main; w app/a.py a2; w app/b.py b2; w app/c.py c2; cm "main moved"
gate() { # gate <FT_CHERRY_GATE_SEC> <FAKE_SLOW> — OUT·RC·LOG
  : > "$T/git.log"
  OUT="$(PATH="$T/fk:$PATH" FAKE_GIT_LOG="$T/git.log" FAKE_SLOW="$2" FT_CHERRY_GATE_SEC="$1" bash "$G" main nano/x --repo "$R" 2>&1)"; RC=$?
  LOG="$(cat "$T/git.log")"
}
nraw() { printf '%s\n' "$LOG" | grep -c -- '--raw' || true; }

# T1 상한 1초 · log --raw 만 느림 → 첫 경로 뒤 단계 paths 1/3 에서 1줄 rc1 · 그 뒤 log --raw 0
s=$SECONDS; gate 1 log
eq "$RC" 1 "T1 rc1"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "T1 출력 정확히 1줄"
has "$OUT" "REJECT cherry 게이트 — 판정 불가(상한 1초 · 단계 paths · 경로 1/3) · 옛 가지 nano/x · 우회 = --cherry-override \"<사유>\"(원장 기록) 또는 새 슬러그" "T1 판정 불가 1줄 원문"
eq "$(nraw)" 1 "T1 log --raw 호출 1번뿐(상한 뒤 git log 0)"
echo "  T1 $((SECONDS-s))초"

# T1b 같은 상한 + --override "<사유>" → 문구가 말하는 우회가 실제로 통한다 = OVERRIDE 1줄 · rc0 · 원장 1행(kind=time-cap · stage=paths · reason)
: > "$T/git.log"; LG="$T/ov.log"
OUT="$(PATH="$T/fk:$PATH" FAKE_GIT_LOG="$T/git.log" FAKE_SLOW=log FT_CHERRY_GATE_SEC=1 FT_CHERRY_OVERRIDE_LEDGER="$LG" bash "$G" main nano/x --repo "$R" --override "옛 가지 폐기 확인" 2>&1)"; RC=$?
eq "$RC" 0 "T1b rc0(사람 우회)"
has "$OUT" "OVERRIDE cherry 게이트 — 판정 불가(상한 1초 · 단계 paths · 경로 1/3) · 옛 가지 nano/x · 사람 사유로 통과: 옛 가지 폐기 확인" "T1b OVERRIDE 줄"
eq "$(grep -c 'kind=time-cap	cap=1	stage=paths	reason=옛 가지 폐기 확인' "$LG" 2>/dev/null)" 1 "T1b 원장 1행"

# T2 상한 0 = 무상한(지금 그대로) → 끝까지 돌아 기존 REJECT · «판정 불가» 0
s=$SECONDS; gate 0 log
eq "$RC" 1 "T2 rc1(기존 REJECT)"
has "$OUT" "tip 내용이 main 역사에 없는 경로" "T2 기존 판정 문구"
hasnt "$OUT" "판정 불가" "T2 판정 불가 0"
eq "$(nraw)" 3 "T2 log --raw 경로 3개 전부"
echo "  T2 $((SECONDS-s))초"

# T3 상한 1초 · cherry 만 느림 → 단계 cherry 1줄 rc1 · merge-tree 호출 0
s=$SECONDS; gate 1 cherry
eq "$RC" 1 "T3 rc1"
eq "$(printf '%s\n' "$OUT" | grep -c .)" 1 "T3 출력 정확히 1줄"
has "$OUT" "판정 불가(상한 1초 · 단계 cherry" "T3 단계 cherry"
has "$OUT" "옛 가지 nano/x · 우회 = --cherry-override" "T3 옛 가지·우회"
eq "$(printf '%s\n' "$LOG" | grep -c 'merge-tree' || true)" 0 "T3 merge-tree 호출 0"
echo "  T3 $((SECONDS-s))초"

# T4 spawn ②-0: 가짜 게이트 sleep 20 → timeout(상한+5 = 6초)이 끊어 rc124 → «REJECT 옛 브랜치 판정 불가(상한)» · rc1 · 카드 바이트 불변 · 워크트리 0
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-v65-master-claude#1
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
export FT_HEAVY_DIR="$T/heavy"
S="$T/sp"; B="$T/bin"; SEATS="$S/.fable-team/seats.json"
mkdir -p "$S/.fable-team/state" "$S/.fable-team/comm" "$S/design/v65/indices/대기" "$B" "$T/sess" "$T/fake"
git init -q -b main "$S" && : > "$S/.gitkeep"
printf 'x\n' > "$S/design/v65/SEATBELT-README.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$S/design/TEAMS.md"
CARD="$S/design/v65/indices/대기/r1470w.md"
printf '# 인덱스: r1470w\n- Issue: #1\n- 배정: 없음\n## 상태\n- 2026-11-15 대기\n' > "$CARD"
git -C "$S" add -A && git -C "$S" commit -q -m init; export FT_TEAMS_REF=HEAD
git -C "$S" branch nano/r1470w main
cp -p "$SRCBIN"/* "$B"/ 2>/dev/null
for f in ft-index-lint.sh ft-proposal-gate.sh ft-send-verified.sh ft-agent-ready.sh ft-spawn-issue-gate.sh ft-resource-sample.sh ft-all-stop.sh ft-index-move.sh ft-resource-reclaim.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\nexit 0\n' > "$B/ft-sheet-events.sh"
printf '#!/bin/bash\necho "$*" >> "%s/gate.log"\nsleep 20\necho NOT-LANDED\nexit 1\n' "$T" > "$B/ft-nano-cherry-gate.sh"
printf '#!/bin/bash\necho "tmuxc $*" >> "%s/calls.log"\n' "$T" > "$T/fake/tmuxc"
printf '#!/bin/bash\ncase "$1" in\n list-sessions) exit 0;;\n has-session) exit 1;;\n *) exit 0;;\nesac\n' > "$T/fake/tmux"
chmod +x "$B"/*.sh "$T/fake/tmuxc" "$T/fake/tmux"
printf '%s\n' '{"_master":"byz-v65-master-claude#1","byz-v65-master-claude#1":{"role":"master","agent":"claude","tick":null}}' > "$SEATS"
C0="$(shasum -a 256 "$CARD" | cut -d' ' -f1)"
s=$SECONDS
o="$(cd "$S" && PATH="$T/fake:$PATH" FT_ROOT="$S" FT_SEATS_JSON="$SEATS" FT_CHERRY_GATE_SEC=1 bash "$B/ft-nano-spawn.sh" "$CARD" 2>&1)"; rc=$?
el=$((SECONDS-s))
eq "$rc" 1 "T4 rc1"
has "$o" "REJECT 옛 브랜치 판정 불가(상한" "T4 판정 불가(상한) 문구"
has "$o" "nano/r1470w · 우회 = --cherry-override" "T4 가지·우회"
hasnt "$o" "REJECT 옛 브랜치 미반입" "T4 «미반입» 오판 0"
[ -e "$T/gate.log" ] && ok "T4 게이트 호출됨" || bad "T4 게이트 호출 0 ← ${o:0:600}"
[ "$el" -lt 15 ] && ok "T4 ${el}초 < 15(게이트 sleep 20 을 끊음)" || bad "T4 ${el}초 — 상한이 안 끊음"
eq "$(shasum -a 256 "$CARD" | cut -d' ' -f1)" "$C0" "T4 카드 바이트 불변"
[ ! -d "$S/.worktrees" ] && ok "T4 워크트리 0" || bad "T4 워크트리 생김"
[ ! -e "$T/calls.log" ] && ok "T4 tmuxc 호출 0" || bad "T4 tmuxc 호출됨"

# T5 기존 cherry 시험 불변 — squash·r1112 rc0 · identical_head 는 base(fe158f7c 뒤 legacy) 에서도 ⑥(spawn directive-roots · 게이트 무관) FAIL 2 → 그 밖 FAIL 0
for t in test_cherry_gate_squash.sh test_nano_close_landed_pr_cherry_r1112.sh; do
  s=$SECONDS; out="$(bash "$HERE/$t" 2>&1)"; r=$?; eq "$r" 0 "T5 $t rc0 ($((SECONDS-s))초)"
done
s=$SECONDS; out="$(bash "$HERE/test_cherry_gate_identical_head.sh" 2>&1)"
eq "$(printf '%s\n' "$out" | grep '^FAIL ' | grep -vc '^FAIL ⑥' || true)" 0 "T5 identical_head ⑥ 밖 FAIL 0 ($((SECONDS-s))초)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
