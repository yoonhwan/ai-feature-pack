#!/usr/bin/env bash
# test_spawn_hold.sh — R320 ft-spawn-hold.sh(set|clear|status [--check]) + spawn 3종 연결.
# 가짜 문지기·가짜 mbox·임시 루트만 쓴다 — 실 tmux·실 좌석·실 정지 파일 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; ST="$R/.fable-team/state"; HF="$ST/SPAWN_HOLD"; mkdir -p "$ST" "$T/fake"
printf '#!/bin/bash\n[ -f "%s/gate.rc" ] && { echo "ERROR resource measure x"; exit 4; }\ncat "%s/gate.status"\n' "$T" "$T" > "$T/fake/gate.sh"
printf '#!/bin/bash\n[ "$1" = send ] && echo "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$T/fake/mbox.sh"
chmod +x "$T/fake"/*
echo '{"_hil_route": "byz-t-planner-claude#1"}' > "$T/seats-planner.json"
: > "$T/mbox.log"
NOW="$(date +%s)"; ISO() { python3 -c 'import sys,datetime;print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
gate() { echo "disk=105 swap=${1:-6666} memfree=39 level=2 rate=96 agents=49 freeze=0" > "$T/gate.status"; rm -f "$T/gate.rc"; }
H() { env FT_RES_ROOT="$R" FT_HOLD_GATE="$T/fake/gate.sh" FT_MBOX_SH="$T/fake/mbox.sh" FT_HOLD_PLANNER_SEATS="$T/seats-planner.json" bash "$BIN/ft-spawn-hold.sh" "$@" 2>&1; }   # 추가 env 는 `FT_HOLD_NOW=… H status`
bash -n "$BIN/ft-spawn-hold.sh" && ok "bash -n ft-spawn-hold.sh" || bad "bash -n"
for f in ft-spawn-hold.sh ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
[ -x "$BIN/ft-spawn-hold.sh" ] && ok "실행 권한" || bad "실행 권한 없음"
GOOD=(set --verdict 2104 --until "$(ISO 180)" --release "swap<8192&memfree>=15" --reason "swap 13G 초과 임시 정지")

# ── set 거절 ──
gate 12000
out="$(H set --verdict 2104 --until "$(ISO 300)" --release "swap<8192" --reason "swap 13G 초과 임시 정지")"; rc=$?
{ [ "$rc" = 1 ] && [ ! -f "$HF" ]; } && has "$out" "지금+4시간" "set REJECT: until 5시간 뒤" || bad "until 5시간 rc=$rc $out"
out="$(H set --verdict 2104 --until "$(ISO 60)" --release "swap<8G" --reason "swap 13G 초과 임시 정지")"; rc=$?
{ [ "$rc" = 1 ] && [ ! -f "$HF" ]; } && has "$out" "문법 위반" "set REJECT: release 비문법(8G)" || bad "release 비문법 rc=$rc $out"
for bad_rel in 'foo<3' 'swap<5;ls' 'swap<5&' 'swap=5' '$(id)<1'; do
  out="$(H set --verdict 2104 --until "$(ISO 60)" --release "$bad_rel" --reason "swap 13G 초과 임시 정지")"; rc=$?
  { [ "$rc" = 1 ] && [ ! -f "$HF" ]; } && ok "set REJECT: release «${bad_rel}»" || bad "release «${bad_rel}» 통과 rc=$rc"
done
out="$(H set --verdict 2104 --until "$(ISO 60)" --release "swap<8192" --reason "아홉글자임시정")"; rc=$?
{ [ "$rc" = 1 ] && [ ! -f "$HF" ]; } && has "$out" "10자 이상" "set REJECT: reason 9자" || bad "reason 9자 rc=$rc $out"
out="$(H set --verdict abc --until "$(ISO 60)" --release "swap<8192" --reason "swap 13G 초과 임시 정지")"; rc=$?
[ "$rc" = 1 ] && ok "set REJECT: verdict 비숫자" || bad "verdict 비숫자 rc=$rc"
out="$(H set --verdict 2104 --until "2020-01-01T00:00:00Z" --release "swap<8192" --reason "swap 13G 초과 임시 정지")"; rc=$?
[ "$rc" = 1 ] && ok "set REJECT: until 과거" || bad "until 과거 rc=$rc"
out="$(H set --verdict 2104 --until "내일" --release "swap<8192" --reason "swap 13G 초과 임시 정지")"; rc=$?
[ "$rc" = 1 ] && ok "set REJECT: until 형식 오류" || bad "until 형식 rc=$rc"

# ── set 성공 · status ── (swap 12000 > 8192 → 해제 조건 거짓)
out="$(H "${GOOD[@]}")"; rc=$?
{ [ "$rc" = 0 ] && [ -f "$HF" ]; } && has "$out" "SET hold=2104" "set 성공 → SPAWN_HOLD 생성" || bad "set 성공 rc=$rc $out"
out="$(H "${GOOD[@]}")"; rc=$?
{ [ "$rc" = 1 ] && has "$out" "이미 있다" "한 번에 1개 — 둘째 set REJECT"; } || bad "둘째 set rc=$rc"
out="$(H status)"; rc=$?
eq "$rc" 3 "정지 유효 → status rc3"; has "$out" "REJECT hold 2104 until=" "status REJECT hold 판정 번호"; has "$out" "release=swap<8192&memfree>=15" "status 에 해제 조건"
[ -f "$HF" ] && ok "유효 정지는 status 가 지우지 않음" || bad "유효 정지가 지워짐"
out="$(H status --check 2104)"; rc=$?; eq "$rc" 0 "--check 일치 번호 rc0"; has "$out" "OK hold=2104" "--check OK"
out="$(H status --check 9999)"; rc=$?; eq "$rc" 3 "--check 다른 번호 rc3"; has "$out" "유효한 정지 없음" "--check 불일치 사유"

# ── 해제 조건 참 → 자동 삭제 + 쪽지 1 ──
: > "$T/mbox.log"; gate 6000   # 해제 조건: swap<8192 & memfree>=15 → 참
out="$(H status --check 2104)"; rc=$?
{ [ "$rc" = 3 ] && [ -f "$HF" ] && [ ! -s "$T/mbox.log" ]; } && ok "--check = 해제 조건 참이어도 삭제·쪽지 0(부작용 0)·rc3" || bad "--check 부작용 rc=$rc"
out="$(H status)"; rc=$?
eq "$rc" 0 "해제 조건 참 → rc0(spawn 통과)"; has "$out" "RELEASED hold=2104" "RELEASED 출력"
[ ! -f "$HF" ] && ok "해제 조건 참 → 파일 삭제" || bad "해제 후에도 파일 있음"
eq "$(grep -c '^send byz-t-planner-claude#1 ft-spawn-hold \[정지 자동 해제\]' "$T/mbox.log")" 1 "planner 쪽지 1통 «정지 자동 해제»"
out="$(H status)"; has "$out" "hold=none" "정지 없음 → hold=none"

# ── 기한 지남 → 통과 + 삭제 + 쪽지 1 ──
: > "$T/mbox.log"; gate 12000; H "${GOOD[@]}" >/dev/null
out="$(FT_HOLD_NOW=$((NOW+14000)) H status)"; rc=$?
eq "$rc" 0 "기한 지남 → rc0"; has "$out" "EXPIRED hold=2104" "EXPIRED 출력"
[ ! -f "$HF" ] && ok "기한 지남 → 파일 삭제" || bad "기한 지나도 파일 있음"
eq "$(grep -c '\[정지 기한 만료\]' "$T/mbox.log")" 1 "planner 쪽지 1통 «정지 기한 만료»"
# ── 기한 지난 번호는 --check 불가 · 파일 유지 ──
H "${GOOD[@]}" >/dev/null; out="$(FT_HOLD_NOW=$((NOW+14000)) H status --check 2104)"; rc=$?
{ [ "$rc" = 3 ] && [ -f "$HF" ]; } && has "$out" "기한 지남" "--check 만료 → rc3 · 파일 유지(부작용 0)" || bad "--check 만료 rc=$rc $out"
# ── 문지기 측정 실패 → rc4 정지 유지 ──
touch "$T/gate.rc"; out="$(H status)"; rc=$?
{ [ "$rc" = 4 ] && [ -f "$HF" ]; } && has "$out" "측정 실패" "문지기 측정 실패 → rc4 · 정지 유지(통과 0)" || bad "측정 실패 rc=$rc $out"
gate 12000; H clear >/dev/null; [ ! -f "$HF" ] && ok "clear → 파일 삭제" || bad "clear 실패"
# ── 파일 손상 → rc4 ──
echo '{"verdict": "x"' > "$HF"; out="$(H status)"; rc=$?
{ [ "$rc" = 4 ] && has "$out" "파일 손상" "손상 파일 → rc4(통과 0)"; } || bad "손상 rc=$rc"
rm -f "$HF"

# ── 교차 워크트리: 다른 워크트리(cwd)에서 건 정지를 리포 루트(cwd=main)의 다른 사본이 본다 (r385b: cwd git common-dir 역산 · 사본 위치 무관) ──
G="$T/g"; mkdir -p "$G/main/scripts/b" "$G/main/.fable-team"; git -C "$G/main" init -q && git -C "$G/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
git -C "$G/main" worktree add -q "$G/wt1" -b wt1 2>/dev/null; mkdir -p "$G/wt1/scripts/b"
cp "$BIN/ft-spawn-hold.sh" "$BIN/ft-harness-root.sh" "$G/main/scripts/b/"; cp "$BIN/ft-spawn-hold.sh" "$BIN/ft-harness-root.sh" "$G/wt1/scripts/b/"
xh() { (cd "$1" && env -u FT_RES_ROOT FT_HOLD_GATE="$T/fake/gate.sh" FT_MBOX_SH="$T/fake/mbox.sh" FT_HOLD_PLANNER_SEATS="$T/seats-planner.json" bash "$1/scripts/b/ft-spawn-hold.sh" "${@:2}" 2>&1); }
xh "$G/wt1" set --verdict 7 --until "$(ISO 60)" --release "swap<8192" --reason "교차 워크트리 시험용 정지" >/dev/null
[ -f "$G/main/.fable-team/state/SPAWN_HOLD" ] && [ ! -e "$G/wt1/.fable-team/state/SPAWN_HOLD" ] && ok "교차: 워크트리에서 건 정지 = 리포 루트 파일 하나" || bad "교차: 파일 위치 어긋남"
gate 12000; has "$(xh "$G/main" status)" "REJECT hold 7" "교차: 루트 사본이 워크트리의 정지를 봄"

# ── spawn 3종 연결: 임시 bin 에 도구와 가짜 문지기(check=REJECT 로 부작용 전 중단)를 두고 부른다 ──
CB="$T/cb"; mkdir -p "$CB"; cp "$BIN/ft-spawn-hold.sh" "$BIN/ft-nano-spawn.sh" "$BIN/ft-role-spawn.sh" "$BIN/ft-successor-open.sh" "$CB/"
printf '#!/bin/bash\n[ "$1" = status ] && { cat "%s/gate.status"; exit 0; }\necho "REJECT resource agents=99 limit=65"; exit 3\n' "$T" > "$CB/ft-resource-gate.sh"; chmod +x "$CB/ft-resource-gate.sh"
cb() { local s="$1"; shift; env FT_RES_ROOT="$R" FT_HOLD_GATE="$CB/ft-resource-gate.sh" FT_MBOX_SH="$T/fake/mbox.sh" FT_HOLD_PLANNER_SEATS="$T/seats-planner.json" FT_RECLAIM=0 bash "$CB/$s" "$@" 2>&1; }
echo "x" > "$T/card.md"; echo "b" > "$T/body.txt"; rm -f "$HF"; gate 12000
out="$(cb ft-nano-spawn.sh "$T/card.md" --dry-run)"; rc=$?
{ [ "$rc" = 3 ] && has "$out" "hold=none" "ft-nano-spawn: 정지 파일 없음 → 출력에 hold=none"; } || bad "nano-spawn hold=none rc=$rc $out"
H "${GOOD[@]}" >/dev/null
for tool in "ft-nano-spawn.sh $T/card.md --dry-run" "ft-role-spawn.sh master --dry-run"; do
  out="$(cb $tool)"; rc=$?
  { [ "$rc" = 3 ] && has "$out" "REJECT hold 2104" "${tool%% *}: 정지 유효 → REJECT hold (문지기 도달 전)"; } || bad "${tool%% *} 정지 rc=$rc $out"
  case "$out" in *"REJECT resource"*) bad "${tool%% *}: 정지인데 문지기까지 감";; *) ok "${tool%% *}: 정지가 문지기보다 앞";; esac
done
out="$(cb ft-successor-open.sh old-claude#1 "$T" --name old-claude#2 --agent claude --model m --body-file "$T/body.txt")"; rc=$?
has "$out" "WARN spawn 정지 중이나 승계는 막지 않는다" "ft-successor-open: 정지 중에도 WARN 1줄만"
case "$out" in *"REJECT hold"*"REJECT resource"*|*"REJECT resource"*) ok "ft-successor-open: 정지에 막히지 않고 문지기 단계까지 진행";; *) bad "ft-successor-open 이 정지에 막힘 rc=$rc $out";; esac
rm -f "$HF"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
