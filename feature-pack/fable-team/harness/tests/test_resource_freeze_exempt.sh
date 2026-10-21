#!/usr/bin/env bash
# test_resource_freeze_exempt.sh — r672: 동결·스왑 거절 판정식 = «swap>12288 ∧ level≥2 ∧ memfree<FT_SWAP_MEMFREE_MAX(30)» +
#   동결 중에도 승계(--succession)·리서치 나노 1석(--research)은 통과(WARN 1줄) · 다른 축(disk·level4·memfree<15·rate)은 그대로.
#   DA⑥ r1(H1~H3) 반영: 리서치 상한 = 조회 실패 거절·동시 spawn 잠금·상한 1 고정 · 문지기/감시자가 «같은 판정 함수 한 곳» ·
#   통과 칸은 «성공 출력 있음» 단언 + 변이 대조.
# 가짜 센서(PATH 앞)·임시 FT_RES_ROOT 만 쓴다 — 실 동결 파일·실 tmux·실 spawn 0. 값은 FAKE_* env 로 준다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_RECLAIM_PREVENT_SEC=0   # 선제 회수 호출 0 — 이 시험은 문지기·감시자·spawn 문만 본다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있음: «${2}» ← ${1:0:300}";; *) ok "$3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST" "$T/home" "$T/cwd" "$T/root/.fable-team/comm" "$T/root/.fable-team/state" "$T/root/design"
. "$HERE/lib/fake_resource_env.sh"; fake_comm_root "$T/root" || { echo "FAIL fake_comm_root"; exit 1; }
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"; WLOG="$ST/resource-watch.log"
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo "$FAKE_LEVEL";;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 ${FAKE_DISK_KIB:-104857600} 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 135; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' > "$S/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
# tmux 대역 — list-sessions 만 진짜로 흉내낸다(rc = TMUX_RC 기본 0 · 세션 이름 = TMUX_SESSIONS 공백 구분). 그 밖 명령은 rc 1.
cat > "$S/tmux" <<'TM'
#!/bin/sh
case "$1" in
  list-sessions) rc="${TMUX_RC:-0}"; if [ "$rc" != 0 ]; then [ -z "${TMUX_STDERR:-}" ] || echo "$TMUX_STDERR" >&2; exit "$rc"; fi; if [ -n "${TMUX_SESSIONS_FILE:-}" ]; then cat "$TMUX_SESSIONS_FILE"; else [ -z "${TMUX_SESSIONS:-}" ] || printf '%s\n' "${TMUX_SESSIONS}" | tr ' ' '\n'; fi; exit 0;;
  has-session) exit "${TMUX_HAS_RC:-1}";;
  *) exit 1;;
esac
TM
chmod 755 "$S"/*
# 표본 2줄(증가 0 · 180초 안) — 문지기 rate 축을 «na» 로 만들지 않는다
sens() { FAKE_SWAP="$1"; FAKE_MEMFREE="$2"; FAKE_LEVEL="$3"; export FAKE_SWAP FAKE_MEMFREE FAKE_LEVEL; }
seed() { local now; now="$(date +%s)"; printf '%s\t%s\t%s\t%s\t2303978\n%s\t%s\t%s\t%s\t2303978\n' "$((now-60))" "$1" "$2" "$3" "$now" "$1" "$2" "$3" > "$PTSV"; sens "$1" "$2" "$3"; }
frz() { echo "시험 동결" > "$FREEZE"; }
rmfrz() { rm -f "$FREEZE"; }
# g <check|check --succession|check --research|status> [env…] — OUT·RC
g() { local args="$1"; shift; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" "$@" bash "$BIN/ft-resource-gate.sh" $args 2>&1)"; RC=$?; }
# tick [env…] — 감시자 1회
tick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
cnt() { grep -c "$1" "$WLOG" 2>/dev/null || true; }
hasline() { printf '%s\n' "$1" | grep -q -- "$2"; }
# spawn <도구> [env…] -- <인자…> — spawn 문(부작용 «전») 출력·rc
spawnrun() { local tool="$1"; shift; local envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  OUT="$(cd "$T/root" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    HOME="$T/home" PATH="$S:$T/stub:$PATH" FT_ROOT="$T/root" FT_TEAMSET=0 FT_RES_ROOT="$R" \
    FT_DISK_MIN_GIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 \
    ${envs[@]+"${envs[@]}"} bash "$BIN/$tool" "$@" 2>&1)"; RC=$?; }

[ -x "$BIN/ft-resource-gate.sh" ] && [ -x "$BIN/ft-resource-watch.sh" ] || { echo "FAIL 설치본 없음"; exit 1; }

# ── ⓐ swap 13000 · level 2 · memfree 66 → 문지기 통과 · 감시자 동결 0 (옛 코드 = 둘 다 거절/동결) ──
rmfrz; rm -f "$WLOG"; seed 13000 66 2
g check
{ [ "$RC" = 0 ] && hasline "$OUT" '^OK '; } && ok "ⓐ 문지기 swap13000·level2·memfree66 → 통과(OK 줄 있음)" || bad "ⓐ 문지기 rc=$RC $OUT"
tick
eq "$(cnt 'FREEZE created')" 0 "ⓐ 감시자 FREEZE created 0"
[ ! -f "$FREEZE" ] && ok "ⓐ 동결 파일 없음" || bad "ⓐ 동결 파일이 생김"

# ── ⓑ swap 13000 · level 2 · memfree 20 → 문지기 REJECT · 감시자 동결(옛 위험 축 유지) ──
rmfrz; rm -f "$WLOG"; seed 13000 20 2
g check
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource swap=13000MiB level=2 memfree=20% limit=12288MiB@level>=2&memfree<30$'; } && ok "ⓑ 문지기 REJECT — 사유 줄 전문 일치" || bad "ⓑ 문지기 rc=$RC $OUT"
tick
eq "$(cnt 'FREEZE created')" 1 "ⓑ 감시자 FREEZE created 1"
has "$(cat "$FREEZE" 2>/dev/null)" "swap=13000M level=2" "ⓑ 동결 사유에 swap·level"

# ── ⓒ 동결 파일 있음: 일반 check = REJECT 그대로 · --succession = 통과 + WARN 1줄 ──
rm -f "$WLOG"; frz; seed 9000 66 1
g check
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource freeze='; } && ok "ⓒ 일반 check → REJECT freeze 그대로" || bad "ⓒ 일반 check rc=$RC $OUT"
g "check --succession"
{ [ "$RC" = 0 ] && hasline "$OUT" '^OK ' && hasline "$OUT" '^WARN resource freeze=.*승계는 동결 중에도 통과'; } && ok "ⓒ --succession → OK 줄 + WARN 통과 줄(둘 다 있음)" || bad "ⓒ --succession rc=$RC $OUT"
eq "$(printf '%s\n' "$OUT" | grep -c '^WARN resource freeze=')" 1 "ⓒ --succession WARN 1줄"
g "check --research"
{ [ "$RC" = 0 ] && hasline "$OUT" '^OK ' && hasline "$OUT" '^WARN resource freeze=.*리서치는 동결 중에도 통과'; } && ok "ⓒ --research → OK 줄 + WARN 통과 줄" || bad "ⓒ --research rc=$RC $OUT"
# 승계 조건 미충족(tmux 세션 없음) = ft-successor-open 이 --succession 을 안 넘긴다 → REJECT 그대로
spawnrun ft-successor-open.sh -- old "$T/cwd" --name x#1 --agent claude --model m --body-file /dev/null
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT resource freeze='; } && ok "ⓒ 승계 조건 미충족 spawn → REJECT freeze(사유 줄 있음)" || bad "ⓒ 승계 조건 미충족 rc=$RC $OUT"
rmfrz

# ── ⓓ 동결 파일 있음 + ft-nano-spawn --research → 문지기 통과(다음 단계로 감) · 리서치 1석 살아 있으면 REJECT · 일반 spawn = REJECT ──
frz
spawnrun ft-nano-spawn.sh -- "$T/card.md"
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT resource freeze=' && ! hasline "$OUT" '대기/ 에 있는 인덱스만'; } && ok "ⓓ 동결 중 일반 spawn → REJECT freeze(다음 검사까지 안 감)" || bad "ⓓ 일반 spawn rc=$RC $OUT"
spawnrun ft-nano-spawn.sh -- "$T/card.md" --research
hasnt "$OUT" "REJECT resource freeze" "ⓓ 동결 중 --research → 동결 면제(REJECT freeze 없음)"
{ hasline "$OUT" 'WARN resource freeze=' && hasline "$OUT" 'REJECT 인덱스 없음: '; } && ok "ⓓ 동결 중 --research → 문지기 WARN 통과 + 다음 검사(인덱스)까지 감(성공 출력 있음)" || bad "ⓓ --research 통과 뒤 단계 rc=$RC $OUT"
spawnrun ft-nano-spawn.sh TMUX_SESSIONS="ft-v65-temp-old-research#0" -- "$T/card.md" --research
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT 리서치 나노 상한 — 살아 있는 리서치 좌석 1석(한도 1'; } && ok "ⓓ 리서치 1석 살아 있음 → REJECT(사유 줄 있음)" || bad "ⓓ 리서치 1석 상한 rc=$RC $OUT"
spawnrun ft-nano-spawn.sh TMUX_SESSIONS="ft-v65-temp-other#0 ft-v65-temp-x#1" -- "$T/card.md" --research
hasnt "$OUT" "REJECT 리서치" "ⓓ 리서치 아닌 좌석만 있으면 상한 아님"
# H1: 조회 실패 = 0석이 아니라 거절 · 상한 env 우회 0 · 동시 spawn 잠금
spawnrun ft-nano-spawn.sh TMUX_RC=2 -- "$T/card.md" --research
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT 리서치 좌석 수 조회 실패'; } && ok "ⓓH1 tmux 조회 실패(rc2) → REJECT(0석 취급 0)" || bad "ⓓH1 조회 실패 rc=$RC $OUT"
spawnrun ft-nano-spawn.sh TMUX_SESSIONS="ft-v65-temp-old-research#0" FT_RESEARCH_SEAT_MAX=5 -- "$T/card.md" --research
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT 리서치 나노 상한'; } && ok "ⓓH1 FT_RESEARCH_SEAT_MAX=5 주입 → 여전히 1석 상한 REJECT" || bad "ⓓH1 상한 env 우회 rc=$RC $OUT"
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions.txt" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH; : > "$T/sessions.txt"
  . "$BIN/ft-research-seat-lib.sh"; FT_RESEARCH_SEAT_MAX=5
  ft_research_cap_check "$T/lockenv.d" 2>&1; echo "rc=$?"; ft_research_unlock "$T/lockenv.d" ) 2>&1)"
{ hasline "$OUT" 'WARN research FT_RESEARCH_SEAT_MAX=5 무시'; hasline "$OUT" 'rc=0'; } && ok "ⓓH1 상한 env 주입 = WARN + 1 고정(rc0 통과)" || bad "ⓓH1 상한 env 처리 «${OUT}»"
# 동시 두 spawn 이 둘 다 0석을 읽고 여는 길 0 — 라이브러리 단위로 잠금 구간을 직접 돌린다(가짜 세션 목록 = 파일)
LIB="$BIN/ft-research-seat-lib.sh"
[ -f "$LIB" ] && ok "ⓓH1 ft-research-seat-lib.sh 있음(판정 한 곳)" || bad "ⓓH1 ft-research-seat-lib.sh 없음"
SESS="$T/sessions.txt"; : > "$SESS"; LK="$T/lock.d"
race_one() { # race_one <이름> — 잠그고 세고(0석) «개설»(파일에 세션 추가) 뒤 해제
  ( set -uo pipefail; TMUX_SESSIONS_FILE="$SESS" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH
    . "$LIB"
    out="$(ft_research_cap_check "$LK" 2>&1)" || { echo "$out"; exit 0; }
    sleep 0.3; printf '%s\n' "ft-v65-temp-$1-research#0" >> "$SESS"; ft_research_unlock "$LK"; echo "OPENED $1" )
}
( race_one A > "$T/raceA" 2>&1 ) & sleep 0.1; race_one B > "$T/raceB" 2>&1; wait
{ grep -q 'OPENED A' "$T/raceA" && grep -q 'REJECT 리서치 나노 상한' "$T/raceB"; } && ok "ⓓH1 동시 두 리서치 → 하나만 개설·둘째는 상한 거절(잠금 안 재조회)" || bad "ⓓH1 동시 결과 A=«$(cat "$T/raceA")» B=«$(cat "$T/raceB")»"
[ -e "$LK" ] && bad "ⓓH1 잠금이 남음: $LK" || ok "ⓓH1 잠금 해제됨(자국 0)"
# 상한 칸 — tmux rc1 의 «오류» 갈래: «no server running» 만 0석 · 그 밖 rc1(소켓·권한) = 셈 실패(REJECT)
OUT="$( ( set -uo pipefail; TMUX_RC=1 TMUX_STDERR="error connecting to /x (Permission denied)" PATH="$S:$PATH"; export TMUX_RC TMUX_STDERR PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_live_count; echo " rc=$?" ) 2>&1)"
{ hasline "$OUT" 'rc=2'; } && ok "ⓓH1' tmux rc1 + «error connecting» → 셈 실패(rc2)" || bad "ⓓH1' rc1 오류 갈래가 0석으로 통과 «${OUT}»"
OUT="$( ( set -uo pipefail; TMUX_RC=1 TMUX_STDERR="no server running on /private/tmp/tmux-501/default" PATH="$S:$PATH"; export TMUX_RC TMUX_STDERR PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_live_count; echo " rc=$?" ) 2>&1)"
{ hasline "$OUT" '0 rc=0'; } && ok "ⓓH1' tmux rc1 + «no server running» → 0석(정상)" || bad "ⓓH1' 서버 없음이 0석이 아님 «${OUT}»"
spawnrun ft-nano-spawn.sh TMUX_RC=1 TMUX_STDERR="error connecting to /x (Permission denied)" -- "$T/card.md" --research
{ [ "$RC" = 3 ] && hasline "$OUT" 'REJECT 리서치 좌석 수 조회 실패'; } && ok "ⓓH1' spawn: rc1 오류 갈래 → REJECT(0석 통과 0)" || bad "ⓓH1' spawn rc1 오류 갈래 rc=$RC $OUT"

# 잠금 — pid 가 «비어 있으면» 만드는 중이다(다른 spawn 의 잠금을 지우지 않는다) · 폴더가 10초 넘게 묵었을 때만 회수
LK3="$T/lock3.d"; rm -rf "$LK3"; mkdir -p "$LK3"; : > "$LK3/pid"      # 방금 만들어졌고 pid 는 아직 비었다(다른 spawn 이 쓰기 직전)
( sleep 0.6; rm -rf "$LK3" ) &
_t0=$SECONDS
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions2.txt" PATH="$S:$PATH"; export PATH TMUX_SESSIONS_FILE PATH; : > "$T/sessions2.txt"
  . "$BIN/ft-research-seat-lib.sh"; ft_research_cap_check "$LK3" 2>&1 && { echo OK; ft_research_unlock "$LK3"; } ) 2>&1)"
_dt=$((SECONDS - _t0)); wait
{ hasline "$OUT" 'OK' && [ "$_dt" -ge 0 ]; } && ok "ⓓH1'' 빈 pid = 만드는 중 → 지우지 않고 기다려 통과(경과 ${_dt}s)" || bad "ⓓH1'' 빈 pid 처리 «${OUT}»"
[ -e "$LK3" ] && bad "ⓓH1'' 잠금이 남음" || ok "ⓓH1'' 통과 뒤 잠금 해제"
LK3="$T/lock3.d"; rm -rf "$LK3"; mkdir -p "$LK3"; : > "$LK3/pid"; touch -t 202001010000 "$LK3"   # 10초 넘게 묵은 빈 pid = 회수 대상
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions2.txt" PATH="$S:$PATH"; export PATH TMUX_SESSIONS_FILE PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_cap_check "$LK3" 2>&1 && { echo OK; ft_research_unlock "$LK3"; } ) 2>&1)"
{ hasline "$OUT" 'OK'; } && ok "ⓓH1'' 묵은 빈 pid(10초 초과) → 회수하고 통과" || bad "ⓓH1'' 묵은 빈 pid «${OUT}»"
rm -rf "$LK3"
# 잠금 잔재(pid 죽음)는 회수된다 — 굳은 잠금이 리서치를 영구히 막지 않는다
mkdir -p "$LK"; echo 999999 > "$LK/pid"
( . "$LIB"; TMUX_SESSIONS_FILE="$SESS" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH
  : > "$SESS"; out="$(ft_research_cap_check "$LK" 2>&1)" && { echo OK; ft_research_unlock "$LK"; } || echo "REJECT $out" ) > "$T/raceC" 2>&1
grep -q '^OK$' "$T/raceC" && ok "ⓓH1 죽은 pid 잠금 → 회수되고 통과" || bad "ⓓH1 굳은 잠금 회수 실패 «$(cat "$T/raceC")»"
rm -rf "$LK"
rmfrz

# ── ⓔ 진짜 위험 축은 «동결 파일이 있는 상태에서도» 승계·리서치를 막는다 (disk · level 4 · memfree<15) ──
frz; seed 9000 66 1
g "check --research" FAKE_DISK_KIB=$((24*1048576))
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource disk='; } && ok "ⓔ 동결+--research disk 24G → REJECT disk" || bad "ⓔ --research disk rc=$RC $OUT"
g "check --succession" FAKE_DISK_KIB=$((24*1048576))
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource disk='; } && ok "ⓔ 동결+--succession disk 24G → REJECT disk" || bad "ⓔ --succession disk rc=$RC $OUT"
seed 9000 66 4; g "check --research"
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource level=4'; } && ok "ⓔ 동결+--research level 4 → REJECT level" || bad "ⓔ --research level rc=$RC $OUT"
seed 9000 9 1; g "check --research"
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource memfree=9%'; } && ok "ⓔ 동결+--research memfree 9%(<15) → REJECT" || bad "ⓔ --research memfree rc=$RC $OUT"
g "check --succession"
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource memfree=9%'; } && ok "ⓔ 동결+--succession memfree 9%(<10) → REJECT" || bad "ⓔ --succession memfree rc=$RC $OUT"
rmfrz

# ── ⓕ 문지기·감시자가 «같은 변수 하나»(FT_SWAP_MEMFREE_MAX)로 움직인다 — 100 이면 옛 동작(둘 다 문턱 밖) ──
rmfrz; rm -f "$WLOG"; seed 13000 66 2
g check FT_SWAP_MEMFREE_MAX=100
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource swap=13000MiB level=2 memfree=66%'; } && ok "ⓕ FT_SWAP_MEMFREE_MAX=100 → 문지기 REJECT(옛 동작)" || bad "ⓕ 문지기 rc=$RC $OUT"
tick FT_SWAP_MEMFREE_MAX=100
eq "$(cnt 'FREEZE created')" 1 "ⓕ FT_SWAP_MEMFREE_MAX=100 → 감시자 동결(문지기와 같은 문턱)"
# 감시자 전용 옛 변수는 «읽지 않는다» — FT_RES_SWAP_MEMFREE_MAX=100 만 주면 공통 30 으로 동작(어긋남 0)
rmfrz; rm -f "$WLOG"; seed 13000 66 2
tick FT_RES_SWAP_MEMFREE_MAX=100
eq "$(cnt 'FREEZE created')" 0 "ⓕH2 감시자 전용 변수 무시 — 공통 30 기준 동결 0(문지기와 일치)"
# 무효값 = 문지기·감시자 모두 기본 30 + WARN · 감시자는 죽지 않는다(set -u unbound 0)
for v in 0 abc -1; do
  rmfrz; rm -f "$WLOG"; seed 13000 66 2
  g check FT_SWAP_MEMFREE_MAX="$v"
  { [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource FT_SWAP_MEMFREE_MAX='; } && ok "ⓕ 문지기 무효값 «${v}» → 기본 30 + WARN" || bad "ⓕ 문지기 무효값 «${v}» rc=$RC $OUT"
  tick FT_SWAP_MEMFREE_MAX="$v"
  { has "$(cat "$WLOG" 2>/dev/null)" "WARN FT_SWAP_MEMFREE_MAX=${v}" "ⓕH2 감시자 무효값 «${v}» 로그 WARN"; [ ! -f "$FREEZE" ]; } && ok "ⓕH2 감시자 무효값 «${v}» 살아서 종료(기본 30 · 동결 0)" || bad "ⓕH2 감시자 무효값 «${v}» 죽었거나 동결됨"
done

# ── ⓗ 변이 대조 — 고침을 되돌리면 이 시험이 «실패»해야 한다 ──
mutant() { local name="$1" f="$2"; shift 2; M="$T/mut-$name"; mkdir -p "$M"; cp "$BIN"/ft-*.sh "$M"/ 2>/dev/null; cp "$BIN"/ft-resource-swap-lib.sh "$M"/ 2>/dev/null
  python3 - "$BIN/$f" "$M/$f" "$@" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "MUT-OLD 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이1: 문지기 동결 면제를 «항상 통과»로(다른 축 검사까지 건너뛰게) → ⓔ 가 실패해야
if mutant noexempt-check ft-resource-gate.sh 'if [ "$FREEZE_FLAG" = 1 ] && [ "$EXEMPT" != 1 ]; then' 'if [ "$FREEZE_FLAG" = 1 ] && [ "$EXEMPT" != 1 ]; then
  exit 0;'; then
  frz; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_DISK_KIB=$((24*1048576)) bash "$M/ft-resource-gate.sh" check --research 2>&1)"; RC=$?; rmfrz
  { [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource disk='; } && ok "ⓗ 변이1(동결 면제=조기 성공) 검출" || bad "ⓗ 변이1 검출 실패 rc=$RC $OUT"
else bad "ⓗ 변이1 준비 실패"; fi
# 변이2: spawn 이 조회 실패를 0석으로 → ⓓH1 이 실패해야
if mutant failopen-count ft-research-seat-lib.sh '    1) case "$err" in *"no server running"*) out="" ;; *) return 2;; esac;;' '    1) out="" ;;'; then
  OUT="$(cd "$T/root" && env HOME="$T/home" PATH="$S:$T/stub:$PATH" FT_ROOT="$T/root" FT_TEAMSET=0 FT_RES_ROOT="$R" TMUX_RC=1 TMUX_STDERR="error connecting to /x (Permission denied)" \
    FT_DISK_MIN_GIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 \
    bash "$M/ft-nano-spawn.sh" "$T/card.md" --research 2>&1)"; RC=$?
  { [ "$RC" = 3 ] && hasline "$OUT" 'REJECT 리서치 좌석 수 조회 실패'; } && bad "ⓗ 변이2 검출 실패(0석 통과)" || ok "ⓗ 변이2(조회 실패=0석) 검출"
else bad "ⓗ 변이2 준비 실패"; fi
# 변이3: 감시자가 전용 변수를 우선(문지기와 어긋남) → ⓕH2 가 실패해야
if mutant watchsplit ft-resource-watch.sh 'SWAP_MEMFREE_MAX="$FT_SWAP_MEMFREE_MAX_VAL"' 'SWAP_MEMFREE_MAX="${FT_RES_SWAP_MEMFREE_MAX:-$FT_SWAP_MEMFREE_MAX_VAL}"'; then
  rmfrz; : > "$WLOG"; seed 13000 66 2
  env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FT_RES_SWAP_MEMFREE_MAX=100 bash "$M/ft-resource-watch.sh" tick >/dev/null 2>&1
  [ -f "$FREEZE" ] && ok "ⓗ 변이3(감시자 전용 변수 우선 = 문지기와 어긋남) 검출" || bad "ⓗ 변이3 검출 실패(전용 변수 우선인데 동결 0)"
else bad "ⓗ 변이3 준비 실패"; fi
rmfrz

# 변이4: 상한 상수를 2로(동시 두 spawn 이 둘 다 열림) → 동시성 칸이 잡아야
if mutant cap2 ft-research-seat-lib.sh 'FT_RESEARCH_SEAT_LIMIT=1' 'FT_RESEARCH_SEAT_LIMIT=2'; then
  : > "$SESS"; LK2="$T/lock2.d"
  race2() { ( set -uo pipefail; TMUX_SESSIONS_FILE="$SESS" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH
    . "$M/ft-research-seat-lib.sh"
    out="$(ft_research_cap_check "$LK2" 2>&1)" || { echo "REJECT $out"; exit 0; }
    sleep 0.3; printf '%s\n' "ft-v65-temp-$1-research#0" >> "$SESS"; ft_research_unlock "$LK2"; echo "OPENED $1" ) ; }
  ( race2 A > "$T/m2A" 2>&1 ) & sleep 0.1; race2 B > "$T/m2B" 2>&1; wait
  { grep -q 'OPENED A' "$T/m2A" && grep -q 'OPENED B' "$T/m2B"; } && ok "ⓗ 변이4(상한 2) 검출" || bad "ⓗ 변이4 검출 실패 A=«$(cat "$T/m2A")» B=«$(cat "$T/m2B")»"
  rm -rf "$LK2"
else bad "ⓗ 변이4 준비 실패"; fi

# ── ⓖ 키트 두 사본 일치 (harness/bin = kit) ──
for f in ft-resource-gate.sh ft-resource-watch.sh ft-nano-spawn.sh ft-resource-swap-lib.sh ft-research-seat-lib.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓖ cmp $f" || bad "ⓖ cmp $f"
done
for f in ft-resource-gate.sh ft-resource-watch.sh ft-nano-spawn.sh ft-resource-swap-lib.sh ft-research-seat-lib.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245" || bad "감시자 줄 수 >245"

echo "fail=$fail"; [ $fail -eq 0 ]
