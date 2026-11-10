#!/usr/bin/env bash
# test_nano_spawn_reopen_r1335.sh — r1335: ft-nano-spawn.sh <진행/ 카드> --reopen (닫힌 나노를 같은 카드에 다시 연다)
# 전부 mktemp — 임시 git 리포 + 가짜 tmux·tmuxc·형제 도구. 실 좌석·실 명부·실 tmux·mbox 0. 자기 재호출 0(변이 시험은 R1335_BIN=<변이 복사본 폴더> 로 같은 파일을 한 번 부른다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
[ -z "${R1335_REENTRY:-}" ] || { echo "ERROR r1335 재진입 차단(R1335_REENTRY)"; exit 2; }; export R1335_REENTRY=1
export FT_TEAMSET=0 FT_CARD_FLOW=0 FT_NANO_SPARSE=0 FT_RECLAIM=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_SEND_FROM='byz-v65-master-claude#1'
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; SRCBIN="${R1335_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
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
[ -n "${R1335_BIN:-}" ] || { cmp -s "$SRCBIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "키트 사본 cmp 0" || bad "키트 사본 어긋남"; }

# ── 임시 리포 + 가짜 도구 ──
R="$T/repo"; B="$T/bin"; SEATS="$R/.fable-team/seats.json"
mkdir -p "$R/.fable-team/state" "$R/.fable-team/comm" "$R/design/v65/indices/대기" "$R/design/v65/indices/진행" "$B" "$T/sess" "$T/fake"
git -C "$R" init -q -b main && : > "$R/.gitkeep"
printf 'x\n' > "$R/design/v65/SEATBELT-README.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
card() { printf '# 인덱스: %s\n- Issue: #1\n- 배정: %s\n## 상태\n- 2026-11-03 진행\n' "$1" "$2"; }   # $1=이름 $2=거울 값
for s in r1335a r1335b r1335c r1335d r1335e r1335f; do card "$s" "없음" > "$R/design/v65/indices/진행/$s.md"; done
card r1335w "없음" > "$R/design/v65/indices/대기/r1335w.md"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init; export FT_TEAMS_REF=HEAD
git -C "$R" config user.email t@t; git -C "$R" config user.name t
cp -p "$SRCBIN"/* "$B"/ 2>/dev/null
for f in ft-index-lint.sh ft-proposal-gate.sh ft-send-verified.sh ft-agent-ready.sh ft-spawn-issue-gate.sh ft-resource-sample.sh ft-all-stop.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\nexit 0\n' > "$B/ft-sheet-events.sh"
printf '#!/bin/bash\necho "$*" >> "%s/move.log"\nexit 0\n' "$T" > "$B/ft-index-move.sh"                                  # 이동 호출 기록(변이 3 = 이동을 그대로 → V1 FAIL)
printf '#!/bin/bash\necho "$*" >> "%s/gate.log"\n[ -e "%s/gate-yes" ] && { echo "LANDED"; exit 0; }\necho "NOT-LANDED"\nexit 1\n' "$T" "$T" > "$B/ft-nano-cherry-gate.sh"   # 미반입 게이트 대역 = 기본 거절(gate-yes 파일이 있으면 «반입») + 호출 기록
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/send.log"\nexit 0\n' "$T" > "$B/ft-send-verified.sh"
printf '#!/bin/bash\necho "tmuxc $*" >> "%s/calls.log"\nif [ "$1" = open ]; then n=""; dry=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && dry=1; shift; done; [ $dry = 1 ] || : > "%s/sess/$n"; fi\n' "$T" "$T" > "$T/fake/tmuxc"
printf '#!/bin/bash\necho "tmux $*" >> "%s/calls.log"\ncase "$1" in\n has-session) [ -e "%s/sess/${3#=}" ];;\n list-sessions) ls "%s/sess" 2>/dev/null; exit 0;;\n list-panes) for s in "%s"/sess/*; do [ -e "$s" ] && echo "$(basename "$s")|%%1|1700000000"; done; exit 0;;\n show-option) echo 1;;\n *) exit 0;;\nesac\n' "$T" "$T" "$T" "$T" > "$T/fake/tmux"
printf '#!/bin/bash\necho "reclaim $*" >> "%s/reclaim.log"\nexit 0\n' "$T" > "$B/ft-resource-reclaim.sh"
chmod +x "$B"/*.sh "$T/fake/tmuxc" "$T/fake/tmux"
ST_SEATS='{"_master":"byz-v65-master-claude#1","byz-v65-master-claude#1":{"role":"master","agent":"claude","tick":null}}'
reset() { printf '%s\n' "$ST_SEATS" > "$SEATS"; rm -rf "$T/sess" "$R/.worktrees" "$R/.fable-team/state/card-assign"; mkdir -p "$T/sess"; : > "$T/calls.log"; rm -f "$T/move.log" "$T/gate.log" "$T/gate-yes" "$T/send.log" "$T/reclaim.log"
  git -C "$R" worktree prune; for b in $(git -C "$R" for-each-ref --format='%(refname:short)' 'refs/heads/nano/*'); do git -C "$R" branch -D -q "$b" >/dev/null 2>&1; done
  git -C "$R" checkout -q -- design 2>/dev/null; git -C "$R" reset -q --hard HEAD; }
SP() { local c="$1"; shift; (cd "$R" && PATH="$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" bash "$B/ft-nano-spawn.sh" "$R/design/v65/indices/$c" "$@" 2>&1); }
seat_names() { ls "$T/sess" | tr '\n' ' '; }
wt() { echo "$R/.worktrees/v65-$1"; }
mkbranch() { git -C "$R" branch "nano/$1" main; git -C "$R" worktree add -q "$(wt "$1")" "nano/$1" && printf 'w\n' > "$(wt "$1")/w.txt" && git -C "$(wt "$1")" add w.txt && git -C "$(wt "$1")" -c user.email=t@t -c user.name=t commit -q -m work; }
untouched() {  # $1=라벨 — 카드·명부·원장·워크트리·tmux·회수 변경 0
  eq "$(cat "$SEATS")" "$ST_SEATS" "$1: 명부 불변"; [ ! -d "$R/.fable-team/state/card-assign" ] && ok "$1: 원장 생성 0" || bad "$1: 원장 생김"
  [ ! -d "$R/.worktrees" ] && ok "$1: 워크트리 0" || bad "$1: 워크트리 생김"; [ -z "$(seat_names)" ] && ok "$1: 세션 0" || bad "$1: 세션 생김 $(seat_names)"
  [ -z "$(git -C "$R" status --porcelain design)" ] && ok "$1: 카드 변경 0" || bad "$1: 카드 변경됨"; [ ! -e "$T/reclaim.log" ] && ok "$1: 회수 호출 0" || bad "$1: 회수 호출됨"; }

# V1 진행 카드 · 워크트리 있음 · 옛 좌석 죽음 → wt=재사용 · 카드 진행/ 그대로 · 거울 = 새 좌석 · 상태 줄 1
reset; mkbranch r1335a; card r1335a "좌석 byz-v65-nano-r1335a#0" > "$R/design/v65/indices/진행/r1335a.md"; git -C "$R" commit -qam c
printf '{"_master":"byz-v65-master-claude#1","byz-v65-nano-r1335a#1":{"role":"nano","_replaced_by":"x"}}\n' > "$SEATS"; OTHER_ROW='"byz-v65-nano-r1335a#1": {"role": "nano", "_replaced_by": "x"}'
o="$(SP 진행/r1335a.md --reopen)"; rc=$?
rc_is "$rc" 0 "V1 rc"; has "$o" "REOPEN design/v65/indices/진행/r1335a.md seat=byz-v65-nano-r1335a#2 wt=재사용 branch=nano/r1335a head=$(git -C "$(wt r1335a)" rev-parse HEAD)" "V1 REOPEN 원문(닫힌 행 #1 을 건너뛴 번호 #2)"
CARDF="$R/design/v65/indices/진행/r1335a.md"; [ -f "$CARDF" ] && [ ! -e "$R/design/v65/indices/대기/r1335a.md" ] && ok "V1 카드 진행/ 그대로" || bad "V1 카드 위치"
[ ! -e "$T/move.log" ] && ok "V1 이동 도구 호출 0" || bad "V1 이동 호출됨: $(cat "$T/move.log")"
eq "$(grep -c '^- 배정: ' "$CARDF")" 1 "V1 거울 줄 1개"; has "$(grep '^- 배정: ' "$CARDF")" "좌석 byz-v65-nano-r1335a#2" "V1 거울 = 새 좌석"
eq "$(grep -c '재개(--reopen)' "$CARDF")" 1 "V1 상태 줄 1"; has "$(grep '재개(--reopen)' "$CARDF")" "좌석 byz-v65-nano-r1335a#2 · wt=재사용" "V1 상태 줄 내용"
eq "$(git -C "$R" log -1 --format=%s)" "[docs] r1335a 재개(--reopen) — 좌석 byz-v65-nano-r1335a#2 · wt=재사용" "V1 카드 커밋 1개"
has "$(python3 -c 'import json;d=json.load(open("'"$SEATS"'"));print(json.dumps(d["byz-v65-nano-r1335a#1"],ensure_ascii=False))')" '"_replaced_by": "x"' "V1 명부의 다른 행(닫힌 #1) 바이트 그대로"
has "$(cat "$SEATS")" '"byz-v65-nano-r1335a#2"' "V1 명부에 새 행"; has "$(cat "$T/send.log")" "재개 — 카드 «상태» 절 마지막 줄부터" "V1 첫 발주에 재개 문장"
[ -e "$T/sess/byz-v65-nano-r1335a#2" ] && ok "V1 새 세션 열림" || bad "V1 새 세션 없음"

# V2 진행 카드 · 워크트리 없음 + nano 가지 미반입 · 옛 좌석 죽음 → wt=가지 재부착 · HEAD = 가지 tip · -r2 가지 0 · 미반입 게이트 호출 0
reset; mkbranch r1335b; TIP="$(git -C "$R" rev-parse nano/r1335b)"; git -C "$R" worktree remove --force "$(wt r1335b)"
o="$(SP 진행/r1335b.md --reopen)"; rc=$?
rc_is "$rc" 0 "V2 rc"; has "$o" "seat=byz-v65-nano-r1335b#0 wt=가지 재부착 branch=nano/r1335b head=$TIP" "V2 REOPEN 원문"
eq "$(git -C "$(wt r1335b)" rev-parse HEAD)" "$TIP" "V2 워크트리 HEAD = 가지 tip"; eq "$(git -C "$R" for-each-ref 'refs/heads/nano/r1335b-r*' | wc -l | tr -d ' ')" 0 "V2 -rN 새 가지 0"
[ ! -e "$T/gate.log" ] && ok "V2 미반입 게이트 건너뜀(--reopen)" || bad "V2 게이트 호출됨"
eq "$(git -C "$R" rev-parse nano/r1335b)" "$TIP" "V2 옛 가지 tip 그대로(덮기 0)"

# V3 진행 카드 · 워크트리·가지 둘 다 없음 → wt=새로
reset; BASE0="$(git -C "$R" rev-parse main)"; o="$(SP 진행/r1335c.md --reopen)"; rc=$?
rc_is "$rc" 0 "V3 rc"; has "$o" "seat=byz-v65-nano-r1335c#0 wt=새로 branch=nano/r1335c head=$BASE0" "V3 REOPEN 원문(base 에서 새로)"
[ -d "$(wt r1335c)" ] && ok "V3 워크트리 생김" || bad "V3 워크트리 없음"

# V4 옛 좌석 살아 있음(거울) → REJECT 살아 있음 — ring · 변경 0
reset; card r1335d "좌석 byz-v65-nano-r1335d#0" > "$R/design/v65/indices/진행/r1335d.md"; git -C "$R" commit -qam c; : > "$T/sess/byz-v65-nano-r1335d#0"; : > "$T/calls.log"; SESS0="$(seat_names)"
o="$(SP 진행/r1335d.md --reopen)"; rc=$?
rc_is "$rc" 1 "V4 rc"; has "$o" "REJECT byz-v65-nano-r1335d#0 살아 있음 — ring" "V4 REJECT 문구"
eq "$(cat "$SEATS")" "$ST_SEATS" "V4 명부 불변"; [ ! -d "$R/.worktrees" ] && ok "V4 워크트리 0" || bad "V4 워크트리 생김"; eq "$(seat_names)" "$SESS0" "V4 세션 그대로"
[ -z "$(git -C "$R" status --porcelain design)" ] && ok "V4 카드 변경 0" || bad "V4 카드 변경됨"; [ ! -d "$R/.fable-team/state/card-assign" ] && ok "V4 원장 0" || bad "V4 원장 생김"
! grep -q 'tmuxc' "$T/calls.log" && ok "V4 tmuxc 호출 0" || bad "V4 tmuxc 호출됨"

# V4b 거울 «없음» · tmux 에 접두-nano-슬러그#0 세션 살아 있음 · 워크트리 있음 → REJECT · 변경 0
reset; mkbranch r1335e; : > "$T/sess/byz-v65-nano-r1335e#0"; SESS0="$(seat_names)"; ST0="$(cat "$SEATS")"
o="$(SP 진행/r1335e.md --reopen)"; rc=$?
rc_is "$rc" 1 "V4b rc"; has "$o" "REJECT byz-v65-nano-r1335e#0 살아 있음 — ring" "V4b REJECT 문구(세션 이름 접두)"
eq "$(cat "$SEATS")" "$ST0" "V4b 명부 불변"; eq "$(seat_names)" "$SESS0" "V4b 세션 그대로"; [ -z "$(git -C "$R" status --porcelain design)" ] && ok "V4b 카드 변경 0" || bad "V4b 카드 변경됨"
[ ! -d "$R/.fable-team/state/card-assign" ] && ok "V4b 원장 0" || bad "V4b 원장 생김"

# V5 대기 카드 + --reopen → REJECT · 변경 0   /  V5b 원장 없는 대기 카드 → 원장 파일 생성 0 · 카드 거울 줄 변경 0 · 회수 호출 0
reset; o="$(SP 대기/r1335w.md --reopen)"; rc=$?
rc_is "$rc" 1 "V5 rc"; has "$o" "REJECT 대기 카드는 --reopen 없이" "V5 REJECT 문구"; untouched "V5/V5b"

# V6 진행 카드 · --reopen 없음 → 지금 REJECT «대기/ 에 있는 인덱스만»
reset; o="$(SP 진행/r1335f.md)"; rc=$?
rc_is "$rc" 1 "V6 rc"; has "$o" "REJECT 대기/ 에 있는 인덱스만 연다" "V6 옛 REJECT 그대로"

# V7 대기 카드 · --reopen 없음 · 워크트리 없음 + 미반입 가지 → 지금처럼 미반입 REJECT(게이트가 --reopen 밖에선 그대로)
reset; mkbranch r1335w; git -C "$R" worktree remove --force "$(wt r1335w)"; : > "$T/gate.log"; rm -f "$T/gate.log"
o="$(SP 대기/r1335w.md)"; rc=$?
rc_is "$rc" 1 "V7 rc"; has "$o" "REJECT 옛 브랜치 미반입 — nano/r1335w" "V7 미반입 REJECT 그대로"; [ -e "$T/gate.log" ] && ok "V7 게이트 호출됨" || bad "V7 게이트 호출 0"

# V8 --reopen --research → usage rc 2
reset; o="$(SP 진행/r1335f.md --reopen --research)"; rc=$?
rc_is "$rc" 2 "V8 rc"; has "$o" "usage: --reopen 과 --research" "V8 usage 문구"; untouched "V8"

# 판정 불가(tmux 목록 못 읽음) → REJECT · 변경 0
reset; printf '#!/bin/bash\ncase "$1" in list-sessions) exit 1;; *) exit 0;; esac\n' > "$T/fake/tmux-broken"; chmod +x "$T/fake/tmux-broken"; mkdir -p "$T/fake2"; cp "$T/fake/tmuxc" "$T/fake2/"; cp "$T/fake/tmux-broken" "$T/fake2/tmux"
o="$( (cd "$R" && PATH="$T/fake2:$T/fake:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$SEATS" bash "$B/ft-nano-spawn.sh" "$R/design/v65/indices/진행/r1335f.md" --reopen 2>&1) )"; rc=$?
rc_is "$rc" 1 "tmux 목록 실패 rc"; has "$o" "REJECT 판정 불가 — tmux 세션 목록을 못 읽었다" "tmux 목록 실패 → 판정 불가 REJECT"; untouched "판정 불가"

# ── 단계 2 (W1~W4): ②-0 -rN 루프가 BRANCH·WTDIR 을 바꾼 «뒤» 에 worktree add 인자를 계산한다 ──
# W1 옛 nano/<슬러그> 가지 실재 · 워크트리 없음 · 반입 yes → 새 가지 -r2 · 워크트리 -r2 · worktree add rc0
reset; mkbranch r1335w; git -C "$R" worktree remove --force "$(wt r1335w)"; : > "$T/gate-yes"; OLD="$(git -C "$R" rev-parse nano/r1335w)"
o="$(SP 대기/r1335w.md)"; rc=$?
rc_is "$rc" 0 "W1 rc"; hasnt "$o" "already exists" "W1 «already exists» 0"
git -C "$R" rev-parse --verify -q refs/heads/nano/r1335w-r2 >/dev/null && ok "W1 새 가지 nano/r1335w-r2" || bad "W1 -r2 가지 없음"
[ -d "$(wt r1335w-r2)" ] && ok "W1 워크트리 -r2" || bad "W1 -r2 워크트리 없음"; eq "$(git -C "$R" rev-parse nano/r1335w)" "$OLD" "W1 옛 가지 tip 그대로"
# W2 -r2 가지도 실재(반입) → -r3
reset; mkbranch r1335w; git -C "$R" worktree remove --force "$(wt r1335w)"; git -C "$R" branch nano/r1335w-r2 main; : > "$T/gate-yes"
o="$(SP 대기/r1335w.md)"; rc=$?
rc_is "$rc" 0 "W2 rc"; hasnt "$o" "already exists" "W2 «already exists» 0"
git -C "$R" rev-parse --verify -q refs/heads/nano/r1335w-r3 >/dev/null && ok "W2 새 가지 nano/r1335w-r3" || bad "W2 -r3 가지 없음"; [ -d "$(wt r1335w-r3)" ] && ok "W2 워크트리 -r3" || bad "W2 -r3 워크트리 없음"
# W3 옛 가지 없음 → nano/<슬러그> 그대로(회귀)
reset; : > "$T/gate-yes"; o="$(SP 대기/r1335w.md)"; rc=$?
rc_is "$rc" 0 "W3 rc"; git -C "$R" rev-parse --verify -q refs/heads/nano/r1335w >/dev/null && ok "W3 가지 nano/r1335w" || bad "W3 가지 없음"
eq "$(git -C "$R" for-each-ref 'refs/heads/nano/r1335w-r*' | wc -l | tr -d ' ')" 0 "W3 -rN 가지 0"; [ -d "$(wt r1335w)" ] && ok "W3 워크트리" || bad "W3 워크트리 없음"
# W4 --reopen + 진행 카드 · 가지 실재 · 워크트리 없음 → 가지 재부착(-b 없음 · -rN 0)
reset; mkbranch r1335b; TIP="$(git -C "$R" rev-parse nano/r1335b)"; git -C "$R" worktree remove --force "$(wt r1335b)"; : > "$T/gate-yes"
o="$(SP 진행/r1335b.md --reopen)"; rc=$?
rc_is "$rc" 0 "W4 rc"; has "$o" "wt=가지 재부착 branch=nano/r1335b head=$TIP" "W4 가지 재부착"; eq "$(git -C "$R" for-each-ref 'refs/heads/nano/r1335b-r*' | wc -l | tr -d ' ')" 0 "W4 -rN 가지 0"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
