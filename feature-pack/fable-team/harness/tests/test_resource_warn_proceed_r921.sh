#!/usr/bin/env bash
# test_resource_warn_proceed_r921.sh — r921 «회수 먼저 → 그래도 넘으면 WARN 1줄 + 진행» 카드의 시험 입력 ⓐ~ⓖ.
#   오빠 원문(2026-10-25): «이런 제약하지마라. 컴퓨터가 죽어버려도 개발은해야지 멈춰있으면 머할건데. 더 스마트하게 움직여라.»
#   갈래: OK(exit 0) / WARN(넘음·못 잼 → `WARN resource …` 1줄 + exit 0) / REJECT(디스크 하드 하한·디스크 측정 실패만 exit 3)
#   ⓐ 각 축이 넘으면 회수 1회 → 다시 재고 → 여전히 넘으면 WARN 1줄 + spawn 진행
#   ⓑ 회수로 문턱 아래 → WARN 0 + 진행
#   ⓒ 디스크 < FT_DISK_HARD_MIN_MIB → REJECT · 디스크 측정 실패 → REJECT (유일한 거절)
#   ⓓ 그 밖 측정 실패(swap·level·memfree·agents) → WARN + 진행
#   ⓔ 동결 파일 → WARN + 진행(일반·승계·리서치 모두)
#   ⓕ 팀 AT-CAP: 끝난 나노 1 → 회수 후 열림 · 끝난 나노 0 → WARN + 열림(큐 적재 0) · 쌓인 큐는 다음 알림에 맨 앞부터
#   ⓖ tick 죽은 좌석 재개: 자원 넘음 → WARN + 재개 진행
#   ⓝ 팀 좌석 상한(FT_TEAM_SEAT_CAP) cap=4·live=4·회수 rc42 → 개설 1 · rc0 · WARN · live=cap+1 → 회수 1회 → 큐 rc7
#   ⓞ 하한 큰 수(18446744073709551617) → rc3 · 디스크 비교 오류 → rc3 «디스크 측정 실패»
#   ⓟ 회수 입구가 «;» 뒤 항목까지 본다(freeze=…; agents=99 limit=65 → agents 후보 평가) · 회수 직접 호출 0(grep)
#   ⓠ 잠금 + abort 등록 → exit 1 → 잠금 폴더 0 · abort 1회(EXIT 정리 목록)
# 가짜 센서(PATH 앞)·가짜 tmux·가짜 회수·임시 FT_RES_ROOT 만 쓴다 — 실 좌석·실 회수·실 spawn 0.
# ★git 쓰기(git init·add·commit·update-ref·worktree add)는 전부 mktemp 임시 리포($T/world) 안에서만 한다 — 실 리포·실 ref 쓰기 0(DA 는 «임시 리포 git 쓰기 허용» 으로 전체를 돌려도 된다).★
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있음: «${2}» ← ${1:0:300}";; *) ok "$3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; B="$T/bin"; mkdir -p "$S" "$ST" "$B" "$T/home" "$T/cwd" "$R/.fable-team/comm"   # spawn·tick 이 comm 폴더를 먼저 푼다(r459)
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$ST/all-stop.log"   # 전팀 정지 원장 init(꺼짐) — 없으면 spawn 이 정지로 읽는다
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"
# 임시 bin = 키트 통째 복사(도구 사이 의존 누락 0) — 문지기·spawn·reclaim 이 «진짜 코드» 로 돈다
bash "$HERE/lib/kit_bin_copy.sh" "$B" >/dev/null || { echo "FAIL kit_bin_copy"; exit 1; }

# ── 가짜 센서: 값은 FAKE_* env · «LOW 파일» 이 있으면 모든 축이 문턱 아래(회수가 실제로 풀었음을 흉내) ──
cat > "$S/sysctl" <<'X'
#!/bin/sh
[ -f "$FAKE_LOWFILE" ] && low=1
case "$2" in
  vm.swapusage) [ -n "${FAKE_RC_SWAP:-}" ] && exit "$FAKE_RC_SWAP"; echo "total = 14336.00M  used = $([ -n "${low:-}" ] && echo 100 || echo "${FAKE_SWAP:-6133}").00M  free = 1000.00M  (encrypted)";;
  kern.memorystatus_vm_pressure_level) [ -n "${FAKE_RC_LEVEL:-}" ] && exit "$FAKE_RC_LEVEL"; [ -n "${low:-}" ] && echo 1 || echo "${FAKE_LEVEL:-1}";;
  *) exit 1;;
esac
X
cat > "$S/memory_pressure" <<'X'
#!/bin/sh
[ -n "${FAKE_RC_MEM:-}" ] && exit "$FAKE_RC_MEM"
if [ -f "$FAKE_LOWFILE" ]; then echo "System-wide memory free percentage: 66%"; else echo "System-wide memory free percentage: ${FAKE_MEMFREE:-51}%"; fi
X
cat > "$S/vm_stat" <<'X'
#!/bin/sh
echo "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
echo "Swapouts:                          2303978."
X
cat > "$S/df" <<'X'
#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
[ -n "${FAKE_RC_DF:-}" ] && { echo "/dev/x 999999999 1 ${FAKE_DISK_KIB:-104857600} 1% /System/Volumes/Data"; exit "$FAKE_RC_DF"; }
echo "/dev/x 999999999 1 ${FAKE_DISK_KIB:-104857600} 1% /System/Volumes/Data"
X
cat > "$S/pgrep" <<'X'
#!/bin/sh
[ -n "${FAKE_RC_AGENTS:-}" ] && exit "$FAKE_RC_AGENTS"
[ "$1" = "-a" ] && shift
case "$*" in
  "-x claude") n="${FAKE_AGENTS:-35}"; [ -f "$FAKE_LOWFILE" ] && n=5; [ "$n" -gt 0 ] && { seq 101 $((100+n)); exit 0; }; exit 1;;
  "-x codex") exit 1;;
  *) exit 99;;
esac
X
cat > "$S/tmux" <<'X'
#!/bin/sh
case "$1" in
  list-sessions) rc="${TMUX_RC:-0}"; [ "$rc" = 0 ] || exit "$rc"
    if [ -n "${TMUX_SESS_FILE:-}" ]; then [ ! -f "$TMUX_SESS_FILE" ] || cat "$TMUX_SESS_FILE"; else [ -z "${TMUX_SESSIONS:-}" ] || printf '%s\n' "$TMUX_SESSIONS" | tr ' ' '\n'; fi
    exit 0;;
  has-session) exit "${TMUX_HAS_RC:-1}";;
  *) exit 1;;
esac
X
cat > "$S/git" <<'X'
#!/bin/sh
echo "git $*" >> "${CALL_LOG:-/dev/null}"
[ "$1" = -C ] && shift 2
case "$1" in rev-parse) echo "${FAKE_TOPDIR:-/tmp}"; exit 0;; *) exit 1;; esac
X
cat > "$S/tmuxc" <<'X'
#!/bin/sh
echo "tmuxc $*" >> "${CALL_LOG:-/dev/null}"
exit 1
X
chmod 755 "$S"/*
# 가짜 회수 두 종류 — noop: 불렀지만 아무것도 못 닫았다(RECLAIMED 0) · free: 닫아서 문턱 아래로 만들었다(touch LOW)
reclaim_stub() { # <noop|free>
  { echo '#!/bin/sh'; echo 'echo "reclaim $*" >> "${CALL_LOG:-/dev/null}"';
    [ "$1" = free ] && echo 'touch "$FAKE_LOWFILE"';
    [ "$1" = free ] && echo 'echo "RECLAIMED 1"' || echo 'echo "RECLAIMED 0"'; echo 'exit 0'; } > "$B/ft-resource-reclaim.sh"
  chmod 755 "$B/ft-resource-reclaim.sh"
}
reclaim_stub noop
printf '#!/bin/sh\nexit 0\n' > "$B/ft-resource-sample.sh"; chmod 755 "$B/ft-resource-sample.sh"
export CALL_LOG="$T/calls.log" FAKE_LOWFILE="$T/low"
seed() { local n; n="$(date +%s)"; printf '%s\t%s\t50\t1\t2303978\n%s\t%s\t50\t1\t2303978\n' "$((n-60))" "${1:-6133}" "$n" "${1:-6133}" > "$PTSV"; }
# rate 씨앗 — 60초 사이 +<분당 MiB> (rate 축만 움직인다)
seed_rate() { local n; n="$(date +%s)"; printf '%s\t%s\t50\t1\t2303978\n%s\t%s\t50\t1\t2303978\n' "$((n-60))" "${1:-6133}" "$n" "$(( ${1:-6133} + ${2:-900} ))" > "$PTSV"; }
frz()  { echo "시험 동결" > "$FREEZE"; }
rmfrz() { rm -f "$FREEZE"; }
# g <check 인자…> [env…] — 진짜 문지기
g() { local args="$1"; shift; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" "$@" bash "$B/ft-resource-gate.sh" $args 2>&1)"; RC=$?; }
LOW="FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999"
rmfrz; seed

# ══ ⓐ 각 축이 넘으면 «회수 1회 → 재검 → WARN 1줄 + 진행» ══
# 문지기 축 5개 — 각각 단독으로 넘긴다(다른 축은 LOW 로 꺼 둔다).
axis_case() { # <이름> <WARN 조각> <env…>
  local name="$1" frag="$2"; shift 2; rm -f "$T/low"; : > "$CALL_LOG"
  OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" $LOW "$@" bash "$B/ft-resource-gate.sh" check 2>&1)"; RC=$?
  { [ "$RC" = 0 ] && echo "$OUT" | grep -qF -- "$frag"; } && ok "ⓐ $name → WARN 1줄 + rc0(진행)" || bad "ⓐ $name rc=$RC $OUT"
}
axis_case "swap"   "swap=13000MiB level=2 memfree=20%" FAKE_SWAP=13000 FAKE_LEVEL=2 FAKE_MEMFREE=20 FT_SWAP_HARD_MIB=12288 FT_SWAP_MEMFREE_MAX=30
axis_case "memfree" "memfree=9% limit=15%"           FAKE_MEMFREE=9 FT_MEM_FREE_MIN_PCT=15
axis_case "level"   "level=4 limit=2"                FAKE_LEVEL=4 FT_PRESSURE_MAX=2
seed_rate 6133 900; axis_case "rate" "rate=900MiB/min limit=512MiB/min" FAKE_SWAP=6133 FT_SWAP_RATE_MAX=512; seed
axis_case "agents"  "agents=99 limit=65"             FAKE_AGENTS=99 FT_AGENT_MAX=65

# spawn 경로 — 넘으면 회수 1회를 «먼저» 부르고, 그래도 넘으면 WARN 1줄을 남기고 다음 단계로 간다
spawn_case() { # <이름> <기대: warn|silent> <env…>  (want=warn → noop 회수 · want=silent → free 회수)
  local name="$1" want="$2"; shift 2; rm -f "$T/low"; : > "$CALL_LOG"
  [ "$want" = silent ] && reclaim_stub free || reclaim_stub noop
  OUT="$(cd "$T/R" && env -u GIT_DIR -u GIT_WORK_TREE HOME="$T/home" PATH="$S:$PATH" FT_RES_ROOT="$R" FAKE_TOPDIR="$R" FT_TEAMSET=0 \
    FT_NANO_PREFIX=byz-r921-nano- FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 \
    FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=65 "$@" bash "$B/ft-nano-spawn.sh" "$T/card.md" --dry-run 2>&1)"; RC=$?
  local calls; calls="$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)"
  if [ "$want" = warn ]; then
    { [ "$calls" = 1 ] && case "$OUT" in *"WARN resource"*) true;; *) false;; esac && ! case "$OUT" in *"REJECT resource"*) true;; *) false;; esac; } \
      && ok "ⓐ spawn $name → 회수 1회 → WARN 1줄 + 진행(REJECT 아님)" || bad "ⓐ spawn $name calls=$calls rc=$RC $OUT"
  else
    { [ "$calls" = 1 ] && ! case "$OUT" in *"WARN resource"*) true;; *) false;; esac; } \
      && ok "ⓑ spawn $name → 회수 1회로 문턱 아래 → WARN 0 + 진행" || bad "ⓑ spawn $name calls=$calls rc=$RC $OUT"
  fi
}
echo "# 카드" > "$T/card.md"
spawn_case "agents 넘김" warn FAKE_AGENTS=99

# ══ ⓑ 회수로 문턱 아래 → WARN 0 · 진행 (회수 단계에서 LOW 파일이 생긴다) ══
spawn_case "회수가 풀어냄" silent FAKE_AGENTS=99

# ══ ⓒ 디스크 = 유일한 거절 ══
g check FAKE_DISK_KIB=$((500*1024)) FT_DISK_HARD_MIN_MIB=1024
{ [ "$RC" = 3 ] && case "$OUT" in "REJECT resource disk=500MiB limit=1024MiB"*) true;; *) false;; esac; } && ok "ⓒ 디스크 500MiB < 1024MiB → REJECT(exit 3)" || bad "ⓒ 디스크 하드 하한 rc=$RC $OUT"
g check FAKE_DISK_KIB=$((4096*1024)) FT_DISK_HARD_MIN_MIB=1024 FT_DISK_MIN_GIB=30
{ [ "$RC" = 0 ] && case "$OUT" in *"WARN resource disk=4GiB limit=30GiB"*) true;; *) false;; esac; } && ok "ⓒ 디스크 4GiB(하드 하한 위·소프트 아래) → WARN + 진행" || bad "ⓒ 디스크 소프트 rc=$RC $OUT"
g check FAKE_RC_DF=42
{ [ "$RC" = 3 ] && case "$OUT" in "REJECT resource disk-measure"*) true;; *) false;; esac; } && ok "ⓒ 디스크 측정 실패(df rc42) → REJECT" || bad "ⓒ 디스크 측정 실패 rc=$RC $OUT"
# spawn 도 디스크 REJECT 면 «회수 0» 으로 즉시 선다
rm -f "$T/low"; : > "$CALL_LOG"
OUT="$(cd "$T/R" && env -u GIT_DIR -u GIT_WORK_TREE HOME="$T/home" PATH="$S:$PATH" FT_RES_ROOT="$R" FAKE_TOPDIR="$R" FT_TEAMSET=0 FT_NANO_PREFIX=byz-r921-nano- \
  FAKE_DISK_KIB=$((500*1024)) FT_DISK_HARD_MIN_MIB=1024 "$@" bash "$B/ft-nano-spawn.sh" "$T/card.md" --dry-run 2>&1)"; RC=$?
{ [ "$RC" = 3 ] && [ "$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)" = 0 ] && case "$OUT" in *"REJECT resource disk="*) true;; *) false;; esac; } \
  && ok "ⓒ spawn 디스크 REJECT → rc3 · 회수 0(회수로 안 풀린다)" || bad "ⓒ spawn 디스크 rc=$RC $OUT"

# ══ ⓓ 그 밖 측정 실패 → WARN + 진행 ══
d_case() { # <이름> <env…>
  local name="$1"; shift; rm -f "$T/low"
  OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" "$@" bash "$B/ft-resource-gate.sh" check 2>&1)"; RC=$?
  { [ "$RC" = 0 ] && case "$OUT" in "WARN resource "*) true;; *) false;; esac && case "$OUT" in *"측정실패"*) true;; *) false;; esac; } \
    && ok "ⓓ $name 측정 실패 → WARN + 진행(rc0)" || bad "ⓓ $name rc=$RC $OUT"
}
d_case "swap"   FAKE_RC_SWAP=42
d_case "level"  FAKE_RC_LEVEL=42
d_case "memfree" FAKE_RC_MEM=42
d_case "agents" FAKE_RC_AGENTS=2
rm -f "$T/low"; : > "$CALL_LOG"
OUT="$(cd "$T/R" && env -u GIT_DIR -u GIT_WORK_TREE HOME="$T/home" PATH="$S:$PATH" FT_RES_ROOT="$R" FAKE_TOPDIR="$R" FT_TEAMSET=0 FT_NANO_PREFIX=byz-r921-nano- \
  FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 \
  FAKE_RC_LEVEL=42 bash "$B/ft-nano-spawn.sh" "$T/card.md" --dry-run 2>&1)"; RC=$?
{ case "$OUT" in *"WARN resource"*"측정실패"*) true;; *) false;; esac && [ "$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)" = 0 ]; } \
  && ok "ⓓ spawn: level 측정 실패 → WARN + 진행(못 잰 축은 회수 대상 아님 — 회수 0)" || bad "ⓓ spawn 측정 실패 rc=$RC $OUT"

# ══ ⓔ 동결 파일 → WARN + 진행(일반·승계·리서치) ══
frz
for m in "" "--succession" "--research"; do
  g "check $m"; { [ "$RC" = 0 ] && case "$OUT" in *"WARN resource freeze=시험 동결 limit=0"*) true;; *) false;; esac; } \
    && ok "ⓔ 동결(${m:-일반}) → WARN + 진행" || bad "ⓔ 동결(${m:-일반}) rc=$RC $OUT"
done
rmfrz

# ══ ⓕ 팀 AT-CAP = «cap+1 까지 열고, 그 위는 회수 → 큐»(W4) ══
# 가짜 tmux 세션 목록 = «파일» — 회수 스텁이 그 파일에서 1줄 지우면 자리가 나고, 못 지우면 포화가 남는다.
mkdir -p "$R/design/alpha/indices/대기" && echo "# 카드" > "$R/design/alpha/indices/대기/f.md"
printf '{"_master":"byz-alpha-master-claude#1"}\n' > "$R/.fable-team/seats-alpha.json"
printf '# 표\n## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| nano | 상한 N | `m` | high | — | a | b |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 2 | 0 | 아니오 |\n' > "$T/TEAMSET.md"
SESSF="$T/sessions.txt"
capspawn() { # <세션들> [--nodry] <env…> — 팀 상한 칸까지 지나간 spawn 1회
  local sess="$1"; shift; local dry="--dry-run"; [ "${1:-}" = --nodry ] && { dry=""; shift; }
  printf '%s\n' "$sess" | tr ' ' '\n' > "$SESSF"
  rm -f "$T/low" "$R/.fable-team/state/spawn-queue-alpha.tsv" "$R/.fable-team/state/spawn-queue-alpha.notified"; : > "$CALL_LOG"
  OUT="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE HOME="$T/home" PATH="$S:$PATH" FT_RES_ROOT="$R" FT_ROOT="$R" FAKE_TOPDIR="$R" \
    TMUX_SESS_FILE="$SESSF" FT_TEAMSET_MD="$T/TEAMSET.md" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$R/.fable-team/seats-alpha.json" \
    FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 FAKE_LOWFILE="$T/low" \
    "$@" bash "$B/ft-nano-spawn.sh" "$R/design/alpha/indices/대기/f.md" --from byz-alpha-master-claude#1 $dry 2>&1)"; RC=$?
}
reclaim_del() {  # 회수 스텁 — 세션 1줄 지운다(끝난 나노를 닫았다)
  cat > "$B/ft-resource-reclaim.sh" <<'X'
#!/bin/sh
echo "reclaim $*" >> "${CALL_LOG:-/dev/null}"
[ -f "$TMUX_SESS_FILE" ] && { tail -n +2 "$TMUX_SESS_FILE" > "$TMUX_SESS_FILE.n" && mv "$TMUX_SESS_FILE.n" "$TMUX_SESS_FILE"; }
echo "RECLAIMED 1"
X
  chmod 755 "$B/ft-resource-reclaim.sh"
}
reclaim_noop() { printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\necho "RECLAIMED 0"\nexit 0\n' > "$B/ft-resource-reclaim.sh"; chmod 755 "$B/ft-resource-reclaim.sh"; }
# ⓕ-1 live=cap(2/2) → 회수 없이 WARN + 진행(cap+1 까지 · 순번 큐 적재 0)
reclaim_noop
capspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0"
{ case "$OUT" in *"AT-CAP alpha live=2 cap=2"*) true;; *) false;; esac && case "$OUT" in *"WARN resource teamset"*"cap+1"*) true;; *) false;; esac \
  && ! case "$OUT" in *QUEUED*) true;; *) false;; esac && [ "$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)" = 0 ] \
  && [ ! -f "$R/.fable-team/state/spawn-queue-alpha.tsv" ]; } \
  && ok "ⓕ-1 live=cap → WARN(cap+1 까지) + 진행 · 회수 0 · 큐 0" || bad "ⓕ-1 rc=$RC $OUT"
# ⓕ-2 live=cap+1(3/2) → 회수 1회(--team)가 1석 닫음 → live=cap → 진행 · 큐 0
reclaim_del
capspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0 byz-alpha-nano-c#0" --nodry
{ ! case "$OUT" in *QUEUED*) true;; *) false;; esac && [ "$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)" = 1 ]; } \
  && ok "ⓕ-2 cap+1 → 회수 1회(--caller)로 자리가 나서 진행 · 큐 0" || bad "ⓕ-2 rc=$RC $OUT"
has "$(cat "$CALL_LOG")" "reclaim --caller byz-alpha-master-claude#1" "ⓕ-2 회수 호출 인자 = --caller <나>"
# ⓕ-3 live=cap+1 · 회수 0 → 순번 큐 + rc7(정지 아니라 «순서 바꿈»)
reclaim_noop
capspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0 byz-alpha-nano-c#0" --nodry
{ [ "$RC" = 7 ] && case "$OUT" in *QUEUED*) true;; *) false;; esac && [ -s "$R/.fable-team/state/spawn-queue-alpha.tsv" ]; } \
  && ok "ⓕ-3 cap+1 포화 + 회수 0 → 순번 큐 rc7(순서 바꿈)" || bad "ⓕ-3 rc=$RC $OUT"
# ⓕ-4 쌓인 큐 — 빈 석 0(AT-CAP)이어도 맨 앞 카드를 master 에게 알린다(다음 tick 이 앞에서부터 연다)
mkdir -p "$R/.fable-team/state"
printf '%s\t%s\n' "$R/design/alpha/indices/대기/f.md" "byz-alpha-master-claude#1" > "$R/.fable-team/state/spawn-queue-alpha.tsv"
rm -f "$R/.fable-team/state/spawn-queue-alpha.notified"
printf '#!/bin/sh\necho "mbox $*" >> "${CALL_LOG:-/dev/null}"\nexit 0\n' > "$R/.fable-team/comm/mbox.sh"; chmod 755 "$R/.fable-team/comm/mbox.sh"
: > "$CALL_LOG"
OUT="$(cd "$R" && env PATH="$S:$PATH" python3 "$B/ft_spawn_queue.py" notify --root "$R" --prefix byz-alpha-nano- --mbox "$R/.fable-team/comm/mbox.sh" --to byz-alpha-master-claude#1 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "$(cat "$CALL_LOG")" "mbox send byz-alpha-master-claude#1" "ⓕ-4 쌓인 큐 → 맨 앞 카드를 master 에게 알린다(AT-CAP 이어도)"; } || bad "ⓕ-4 큐 알림 rc=$RC $OUT"
rm -f "$R/.fable-team/state/spawn-queue-alpha.notified"; : > "$CALL_LOG"
cat > "$T/q.py" <<'PP'
import sys
sys.path.insert(0, sys.argv[1])
import ft_spawn_queue as q
print(repr(q.notify_master(sys.argv[2], "byz-alpha-nano-", -1, "byz-alpha-master-claude#1")))
PP
OUT="$(cd "$R" && env PATH="$S:$PATH" python3 "$T/q.py" "$B" "$R" 2>&1)"
{ case "$OUT" in *"''"*) false;; *) true;; esac && has "$(cat "$CALL_LOG")" "mbox send byz-alpha-master-claude#1" "ⓕ-5 free=-1(초과) 여도 큐 알림이 나간다"; } || bad "ⓕ-5 free=-1 침묵 «$OUT»"

# ══ ⓖ tick 죽은 좌석 재개 — 자원 넘음 → WARN + 재개 진행 ══
grep -q '자원 WARN — 재개 진행' "$BIN/ft-tick.sh" && ok "ⓖ tick 재개 경로가 «WARN + 진행» 갈래를 갖는다" || bad "ⓖ tick 에 WARN 갈래 없음"
grep -q '(REJECT|WARN) resource' "$BIN/ft-tick.sh" && ok "ⓖ tick 이 문지기 WARN 줄을 읽는다" || bad "ⓖ tick WARN 판독 없음"
# 문지기 단독: 재개 전 호출이 WARN(rc0)이면 «재개 0» 이 아니라 «진행» 으로 읽히는지 — 판정식 그대로
rm -f "$T/low"; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" FAKE_LEVEL=4 FT_PRESSURE_MAX=2 bash "$B/ft-resource-gate.sh" check 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && case "$OUT" in *"WARN resource level=4"*) true;; *) false;; esac; } && ok "ⓖ 재개 전 문지기 판정 = WARN rc0(멈춤 아님)" || bad "ⓖ 재개 전 판정 rc=$RC $OUT"

# ══ ⓐ'·ⓗ·ⓘ·ⓛ — 개설 «결과» 로 증명하는 대역 세계(대역 tmuxc 가 좌석 개설 기록을 남긴다) ══
#   DA⑥ r1: «rc0» 만 보면 rc42·문법 오류도 통과한다 — 개설 기록이 있을 때만 «진행» 으로 인정한다.
W="$T/world"; SESSD="$T/sess"; WF="$T/wfake"; WB="$T/wbin"; mkdir -p "$SESSD" "$WF"
mkdir -p "$W/.fable-team/state" "$W/.fable-team/comm" "$W/design/alpha/indices/대기" "$W/design/alpha/indices/진행"
bash "$HERE/lib/kit_bin_copy.sh" "$WB" >/dev/null || { echo "FAIL kit_bin_copy(world)"; exit 1; }
for f in ft-index-lint.sh ft-proposal-gate.sh ft-index-move.sh ft-send-verified.sh ft-agent-ready.sh ft-spawn-issue-gate.sh ft-nano-spawn-undo.sh; do printf '#!/bin/sh\nexit 0\n' > "$WB/$f"; chmod 755 "$WB/$f"; done
cat > "$WF/tmuxc" <<'X'
#!/bin/sh
echo "tmuxc $*" >> "$CALL_LOG"
case "$1" in
  open) [ -z "${FAKE_OPEN_FAIL:-}" ] || exit 1   # ⓠ: 열기 실패(세션 0) → spawn exit 1
    n=""; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; shift; done; : > "$SESSD/$n"; echo "OPEN $n" >> "$T/open.log"; exit 0;;
  *) exit 1;;
esac
X
cat > "$WF/tmux" <<'X'
#!/bin/sh
case "$1" in
  has-session) [ -e "$SESSD/${3#=}" ] && exit 0 || exit 1;;
  list-sessions) for s in "$SESSD"/*; do [ -e "$s" ] && basename "$s"; done; exit 0;;
  list-panes) for s in "$SESSD"/*; do [ -e "$s" ] && echo "$(basename "$s")|%1|1700000000"; done; exit 0;;
  show-options|show-option) echo 1; exit 0;;
  *) exit 0;;
esac
X
for f in sysctl memory_pressure vm_stat df pgrep; do cp "$S/$f" "$WF/$f"; done   # 센서 대역만 — git·tmux 는 $WF 판(실 git 이 필요하다)
chmod 755 "$WF"/*
git -C "$W" init -q -b main
printf '# 인덱스: x\n## 상태\n' > "$W/design/alpha/indices/대기/x.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n| alpha | `design/alpha/` | x | 현역 |\n' > "$W/design/TEAMS.md"
mkdir -p "$W/design/v65"; printf 'x\n' > "$W/design/v65/SEATBELT-README.md"   # ⑦ 첫 발주가 참조하는 부팅 안내
printf '{"_name":"alpha","_master":"byz-alpha-master-claude#1"}\n' > "$W/.fable-team/seats-alpha.json"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$W/.fable-team/state/all-stop.log"
printf '#!/bin/sh\nexit 0\n' > "$W/.fable-team/comm/mbox.sh"; chmod 755 "$W/.fable-team/comm/mbox.sh"
git -C "$W" add -A >/dev/null 2>&1; git -C "$W" -c user.email=t@t -c user.name=t commit -q -m init; git -C "$W" update-ref refs/remotes/origin/main HEAD
printf '# 표\n## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| nano | 상한 N | `m` | high | — | a | b |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 4 | 0 | 아니오 |\n' > "$T/TS4.md"
runspawn() { # <세션들> <env…> — 실제 spawn 1회(개설 경로 · 실 git worktree)
  local sess="$1"; shift
  rm -rf "$SESSD"/*; rm -f "$T/low"; : > "$T/open.log"; : > "$CALL_LOG"   # LOW 파일은 앞 절의 잔재 — 없으면 «넘김» 이 재현된다
  local s; for s in $sess; do : > "$SESSD/$s"; done
  OUT="$(cd "$W" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY HOME="$T/home" \
    PATH="$WF:$WB:$PATH" CALL_LOG="$CALL_LOG" SESSD="$SESSD" T="$T" FT_ROOT="$W" FT_RES_ROOT="$W" FT_TEAMS_REF=HEAD \
    FT_NANO_PREFIX=byz-alpha-nano- FT_SEATS_JSON="$W/.fable-team/seats-alpha.json" FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 \
    FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 FAKE_LOWFILE="$T/low" \
    "$@" bash "$WB/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 2>&1)"; RC=$?
}
opened() { ls "$SESSD" 2>/dev/null | grep -c '^byz-alpha-nano-'; }
reclaim_exit() { printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\nexit %s\n' "$1" > "$WB/ft-resource-reclaim.sh"; chmod 755 "$WB/ft-resource-reclaim.sh"; }
# ⓐ' 넘김(WARN)인데 회수가 rc42 로 죽어도 → 개설 1 · WARN 1줄
reclaim_exit 42
runspawn "" FAKE_AGENTS=99 FT_AGENT_MAX=65 FT_TEAMSET=0
{ [ "$RC" = 0 ] && [ "$(opened)" = 1 ] && case "$OUT" in *"WARN resource agents=99"*) true;; *) false;; esac && ! case "$OUT" in *"REJECT resource"*) true;; *) false;; esac; } \
  && ok "ⓐ' 자원 넘김 + 회수 rc42 → rc0 ∧ 개설 1(개설 기록) · WARN 1줄 · 문지기 REJECT 0" || bad "ⓐ' opened=$(opened) rc=$RC $OUT"
# ⓐ'' 정상 자원 → 개설 1 · WARN 0 (대조군: 개설 기록이 «진행» 을 실제로 뜻한다)
reclaim_exit 0
runspawn "" FT_TEAMSET=0
{ [ "$(opened)" = 1 ] && ! case "$OUT" in *"WARN resource agents="*|*"WARN resource swap="*|*"WARN resource level="*|*"WARN resource disk="*) true;; *) false;; esac; } \
  && ok "ⓐ'' 정상 자원 → 개설 1 · 넘김 WARN 0" || bad "ⓐ'' opened=$(opened) rc=$RC $OUT"
# ⓗ 팀 cap=4 · live=4(AT-CAP) + 자원 회수 rc42 → cap+1 개설 1 · WARN(teamset) 1줄
reclaim_exit 42
runspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0 byz-alpha-nano-c#0 byz-alpha-nano-d#0" FT_TEAMSET=1 FT_TEAMSET_MD="$T/TS4.md"
{ [ "$(opened)" = 5 ] && case "$OUT" in *"AT-CAP alpha live=4 cap=4"*) true;; *) false;; esac && case "$OUT" in *"WARN resource teamset"*"cap+1"*) true;; *) false;; esac; } \
  && ok "ⓗ cap=4·live=4 → cap+1 개설(총 5석) · WARN 1줄" || bad "ⓗ opened=$(opened) rc=$RC $OUT"
# ⓘ 팀셋 측정 실패(표 없음) → WARN + 개설(W1: 정지는 디스크뿐)
reclaim_exit 0
runspawn "" FT_TEAMSET=1 FT_TEAMSET_MD="$T/없는표.md"
{ [ "$(opened)" = 1 ] && case "$OUT" in *"WARN 팀셋 측정 실패"*) true;; *) false;; esac && ! case "$OUT" in *"REJECT 팀셋"*) true;; *) false;; esac; } \
  && ok "ⓘ 팀셋 측정 실패 → WARN + 개설 1(rc=$RC)" || bad "ⓘ opened=$(opened) rc=$RC $OUT"
# ⓙ 하한 값 이상(abc·-1·0) → REJECT «하한 값 이상» · 개설 0
for v in abc -1 0; do
  runspawn "" FT_TEAMSET=0 FT_DISK_HARD_MIN_MIB="$v"
  { [ "$RC" = 3 ] && [ "$(opened)" = 0 ] && case "$OUT" in *"하한 값 이상($v)"*) true;; *) false;; esac; } \
    && ok "ⓙ FT_DISK_HARD_MIN_MIB=$v → REJECT(개설 0)" || bad "ⓙ $v opened=$(opened) rc=$RC $OUT"
done

# ⓚ 회수 상한(W3) — 회수 대역이 9초 자면 7초±1 에 끊고 WARN 1줄 + 진행(개설 기록)
cat > "$WB/ft-resource-reclaim.sh" <<'X'
#!/bin/sh
echo "reclaim $*" >> "${CALL_LOG:-/dev/null}"
sleep 9
echo "RECLAIMED 0"
X
chmod 755 "$WB/ft-resource-reclaim.sh"
_t0=$SECONDS
runspawn "" FAKE_AGENTS=99 FT_AGENT_MAX=65 FT_TEAMSET=0
_dt=$((SECONDS - _t0))
{ [ "$_dt" -ge 6 ] && [ "$_dt" -le 10 ] && [ "$(opened)" = 1 ] && case "$OUT" in *"WARN 회수 시간 초과"*) true;; *) false;; esac; } \
  && ok "ⓚ 회수 9초 대역 → ${_dt}초에 끊고 WARN 1줄 + 개설 1" || bad "ⓚ dt=${_dt} opened=$(opened) rc=$RC $OUT"
# ⓛ 동시 spawn 2개(live=cap=2) → 잠금으로 직렬화 · 1석만 개설(cap+1) · 나머지 1장은 순번 큐(이중 개설 0)
sed 's/| alpha | 4 |/| alpha | 2 |/' "$T/TS4.md" > "$T/TS2.md"
printf '# 인덱스: y\n## 상태\n' > "$W/design/alpha/indices/대기/y.md"
printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\necho "RECLAIMED 0"\nexit 0\n' > "$WB/ft-resource-reclaim.sh"; chmod 755 "$WB/ft-resource-reclaim.sh"
rm -rf "$SESSD"/*; : > "$CALL_LOG"; : > "$T/open.log"; rm -f "$T/low"
: > "$SESSD/byz-alpha-nano-a#0"; : > "$SESSD/byz-alpha-nano-b#0"
rm -f "$W/.fable-team/state/spawn-queue-alpha.tsv"
wspawn_card() { # <카드 상대경로> — 실제 spawn 1회(백그라운드용)
  ( cd "$W" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY HOME="$T/home" \
    PATH="$WF:$WB:$PATH" CALL_LOG="$CALL_LOG" SESSD="$SESSD" T="$T" FT_ROOT="$W" FT_RES_ROOT="$W" FT_TEAMS_REF=HEAD \
    FT_NANO_PREFIX=byz-alpha-nano- FT_SEATS_JSON="$W/.fable-team/seats-alpha.json" FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 \
    FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 FAKE_LOWFILE="$T/low" \
    FT_TEAMSET=1 FT_TEAMSET_MD="$T/TS2.md" bash "$WB/ft-nano-spawn.sh" "$1" --from byz-alpha-master-claude#1 >"$T/conc-$2.out" 2>&1; echo $? > "$T/conc-$2.rc" )
}
wspawn_card design/alpha/indices/대기/x.md A & 
sleep 0.2
wspawn_card design/alpha/indices/대기/y.md B &
wait
_new="$(ls "$SESSD" 2>/dev/null | grep -c '^byz-alpha-nano-')"
_q="$(grep -c . "$W/.fable-team/state/spawn-queue-alpha.tsv" 2>/dev/null || echo 0)"
{ [ "$_new" = 3 ] && [ "$_q" = 1 ]; } \
  && ok "ⓛ 동시 2 spawn(live=cap=2) → 개설 1(총 3=cap+1) · 큐 1 · cap+2 0" \
  || bad "ⓛ 세션=$_new 큐=$_q A=$(cat "$T/conc-A.rc" 2>/dev/null) B=$(cat "$T/conc-B.rc" 2>/dev/null) $(tail -2 "$T/conc-A.out" 2>/dev/null) $(tail -2 "$T/conc-B.out" 2>/dev/null)"
# ⓛ' live=cap+1 직렬 → 회수 1회 → 큐(개설 0)
printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\necho "RECLAIMED 0"\nexit 0\n' > "$WB/ft-resource-reclaim.sh"; chmod 755 "$WB/ft-resource-reclaim.sh"
rm -rf "$SESSD"/*; : > "$T/open.log"; : > "$CALL_LOG"; rm -f "$W/.fable-team/state/spawn-queue-alpha.tsv"
for s in a b c; do : > "$SESSD/byz-alpha-nano-$s#0"; done
( cd "$W" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY HOME="$T/home" \
  PATH="$WF:$WB:$PATH" CALL_LOG="$CALL_LOG" SESSD="$SESSD" T="$T" FT_ROOT="$W" FT_RES_ROOT="$W" FT_TEAMS_REF=HEAD \
  FT_NANO_PREFIX=byz-alpha-nano- FT_SEATS_JSON="$W/.fable-team/seats-alpha.json" FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=1 \
  FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 FAKE_LOWFILE="$T/low" \
  FT_TEAMSET=1 FT_TEAMSET_MD="$T/TS2.md" bash "$WB/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 >"$T/ser.out" 2>&1; echo $? > "$T/ser.rc" )
{ [ "$(cat "$T/ser.rc")" = 7 ] && [ "$(ls "$SESSD" | grep -c '^byz-alpha-nano-')" = 3 ] && [ "$(grep -c . "$W/.fable-team/state/spawn-queue-alpha.tsv" 2>/dev/null || echo 0)" = 1 ] \
  && [ "$(grep -c '^reclaim ' "$CALL_LOG")" = 1 ]; } \
  && ok "ⓛ' live=cap+1 직렬 → 회수 1회 뒤에도 포화 → 순번 큐 rc7 · 개설 0" || bad "ⓛ' rc=$(cat "$T/ser.rc") 세션=$(ls "$SESSD" | grep -c '^byz-alpha-nano-') $(tail -2 "$T/ser.out")"

# ══ ⓝ 팀 좌석 상한 길(FT_TEAM_SEAT_CAP · W1 r2) — 판정기 REJECT 여도 큐로 가지 않는다(cap+1 까지 연다) ══
QA="$W/.fable-team/state/spawn-queue-alpha.tsv"
reclaim_exit 42; rm -f "$QA"
runspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0 byz-alpha-nano-c#0 byz-alpha-nano-d#0" FT_TEAMSET=0 FT_TEAM_SEAT_CAP=4
{ [ "$RC" = 0 ] && [ "$(opened)" = 5 ] && [ ! -f "$QA" ] && [ "$(grep -c '^reclaim .*--team alpha' "$CALL_LOG")" = 1 ] \
  && case "$OUT" in *"REJECT 좌석 상한 alpha 4/4"*) true;; *) false;; esac && case "$OUT" in *"WARN resource seat-cap"*) true;; *) false;; esac \
  && ! case "$OUT" in *QUEUED*) true;; *) false;; esac; } \
  && ok "ⓝ cap=4·live=4 · 회수 rc42 → 회수 1회 · rc0 · 개설 1(총 5) · WARN 1줄 · 큐 0" || bad "ⓝ cap=4·live=4 rc=$RC opened=$(opened) q=$([ -f "$QA" ] && echo 1 || echo 0) $OUT"
reclaim_exit 0; rm -f "$QA"
runspawn "byz-alpha-nano-a#0 byz-alpha-nano-b#0 byz-alpha-nano-c#0 byz-alpha-nano-d#0 byz-alpha-nano-e#0" FT_TEAMSET=0 FT_TEAM_SEAT_CAP=4
{ [ "$RC" = 7 ] && [ "$(opened)" = 5 ] && [ "$(grep -c . "$QA" 2>/dev/null || echo 0)" = 1 ] && [ "$(grep -c '^reclaim .*--team alpha' "$CALL_LOG")" = 1 ]; } \
  && ok "ⓝ' cap=4·live=5(cap+1) → 회수 1회 뒤에도 포화 → 순번 큐 rc7 · 개설 0" || bad "ⓝ' rc=$RC opened=$(opened) $OUT"

# ══ ⓞ 하한 큰 수 · 디스크 비교 오류(W2 r2) ══
reclaim_exit 0
runspawn "" FT_TEAMSET=0 FT_DISK_HARD_MIN_MIB=18446744073709551617
{ [ "$RC" = 3 ] && [ "$(opened)" = 0 ] && case "$OUT" in *"하한 값 이상(18446744073709551617)"*) true;; *) false;; esac; } \
  && ok "ⓞ 큰 수 하한 18446744073709551617 → rc3 «하한 값 이상» · 개설 0" || bad "ⓞ 큰 수 rc=$RC opened=$(opened) $OUT"
g check FT_DISK_HARD_MIN_MIB=10000000
{ [ "$RC" = 3 ] && case "$OUT" in *"하한 값 이상(10000000)"*) true;; *) false;; esac; } && ok "ⓞ' 8자리 하한 10000000 → rc3 «하한 값 이상»" || bad "ⓞ' rc=$RC $OUT"
g check FT_DISK_HARD_MIN_MIB=9999999
{ [ "$RC" = 3 ] && case "$OUT" in *"REJECT resource disk="*"limit=9999999MiB"*) true;; *) false;; esac; } && ok "ⓞ'' 7자리 하한 9999999 = 유효(디스크 비교 REJECT)" || bad "ⓞ'' rc=$RC $OUT"
g check FT_DISK_MIN_GIB=abc
{ [ "$RC" = 3 ] && case "$OUT" in *"REJECT resource disk-measure"*"디스크 측정 실패"*) true;; *) false;; esac; } && ok "ⓞ''' 디스크 비교 오류(FT_DISK_MIN_GIB=abc) → rc3 «디스크 측정 실패»(WARN rc0 새는 길 0)" || bad "ⓞ''' rc=$RC $OUT"

# ══ ⓟ 회수 입구가 «모든» 항목을 본다(W3 r2) — 진짜 ft-resource-reclaim.sh · --dry-run(kill·로그·mbox 0) ══
PB="$T/pbin"; bash "$HERE/lib/kit_bin_copy.sh" "$PB" >/dev/null || bad "ⓟ kit_bin_copy"
printf '{}\n' > "$R/.fable-team/seats.json"; printf '#!/bin/sh\nexit 0\n' > "$R/.fable-team/comm/mbox.sh"; chmod 755 "$R/.fable-team/comm/mbox.sh"
pr() { OUT="$(env FT_RES_ROOT="$R" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_MBOX_SH="$R/.fable-team/comm/mbox.sh" ZC_RESUME_DIR="$T/resume" FT_PRESS_PERMIT_DIR="$T/permits" \
  PATH="$S:$PATH" bash "$PB/ft-resource-reclaim.sh" --dry-run --caller byz-test-nano-x#0 --on-reject "$1" --gate "$PB/ft-resource-gate.sh" 2>&1)"; RC=$?; }
pr "WARN resource freeze=시험 동결 limit=0; agents=99 limit=65"
{ [ "$RC" = 3 ] && case "$OUT" in *"dry-run:"*) true;; *) false;; esac; } \
  && ok "ⓟ freeze 뒤 agents → 조기 종료 0 · agents 후보 평가(dry-run 표 · rc3)" || bad "ⓟ freeze 뒤 agents rc=$RC $OUT"
pr "WARN resource freeze=시험 동결 limit=0; disk=12GiB limit=30GiB"
{ [ "$RC" = 0 ] && ! case "$OUT" in *"dry-run:"*) true;; *) false;; esac; } \
  && ok "ⓟ' 좌석으로 안 풀리는 항목뿐(freeze·disk) → 그대로 통과 rc0(대조군)" || bad "ⓟ' rc=$RC $OUT"
_dcall=0
for f in ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh ft-tick.sh; do
  _n="$(grep -E 'bash +"[^"]*ft-resource-reclaim\.sh' "$BIN/$f" | grep -vc ft_reclaim_capped)"; _dcall=$((_dcall + _n))
done
{ [ "$_dcall" = 0 ] && [ "$(grep -c 'ft_reclaim_capped .*ft-resource-reclaim\.sh' "$BIN/ft-nano-spawn.sh")" = 3 ]; } \
  && ok "ⓟ'' 회수 직접 호출 0(spawn·role·successor·tick) · spawn 의 회수 3곳 전부 ft_reclaim_capped 경유" || bad "ⓟ'' 직접 호출 $_dcall"

# ══ ⓠ EXIT 정리 목록(W4 r2) — 잠금 → abort 등록 → exit 1 → 잠금 폴더 0 · abort 1회 ══
reclaim_exit 0; rm -f "$QA"; rm -rf "$W/.fable-team/state/nano-cap.lock.d"
mv "$WB/ft-sheet-events.sh" "$WB/ft-sheet-events.real.sh"
printf '#!/bin/sh\necho "sheet $1" >> "$CALL_LOG"\nexec bash "%s" "$@"\n' "$WB/ft-sheet-events.real.sh" > "$WB/ft-sheet-events.sh"; chmod 755 "$WB/ft-sheet-events.sh"
runspawn "" FT_TEAMSET=1 FT_TEAMSET_MD="$T/TS4.md" FAKE_OPEN_FAIL=1
{ [ "$RC" = 1 ] && [ "$(opened)" = 0 ] && [ ! -e "$W/.fable-team/state/nano-cap.lock.d" ] \
  && [ "$(grep -c '^sheet prepare' "$CALL_LOG")" = 1 ] && [ "$(grep -c '^sheet abort' "$CALL_LOG")" = 1 ]; } \
  && ok "ⓠ 잠금+abort+exit1 → 잠금 폴더 0 · abort 1회 · 개설 0" \
  || bad "ⓠ 잠금+abort+exit1 rc=$RC lock=$([ -e "$W/.fable-team/state/nano-cap.lock.d" ] && echo 남음 || echo 0) sheet=$(grep '^sheet' "$CALL_LOG" | tr '\n' ' ') $(printf '%s' "$OUT" | tail -2)"
mv -f "$WB/ft-sheet-events.real.sh" "$WB/ft-sheet-events.sh"

# ══ 변이 대조 — ★DA⑥ r1★ 각 변이는 «전체 시험 재실행» 으로 판정한다(단일 칸·문법 오류·rc 만 보는 검출은 인정 0) ══
#   판정 = 변이 사본에서 «그 칸은 FAIL» ∧ «대조 칸은 PASS» ∧ «문법 오류 없음». 재실행 사본은 R921_NO_MUT=1 로 변이 절을 끈다.
if [ "${R921_NO_MUT:-0}" = 1 ]; then
  echo "SKIP 변이 — 내부 재실행(R921_NO_MUT=1)"
else
mutcase() { # <이름> <harness 상대경로 파일> <old> <new> <빨강 라벨 조각> <초록 라벨 조각>
  local name="$1" f="$2" old="$3" new="$4" redl="$5" greenl="$6"
  local st="$T/mstage"; rm -rf "$st"; mkdir -p "$st/harness"
  cp -R "$REPO/harness/bin" "$st/harness/" && cp -R "$REPO/harness/kit" "$st/harness/" && cp -R "$REPO/harness/tests" "$st/harness/" || { bad "변이 $name 준비 실패(copy)"; return; }
  local kf="${f/bin\//kit/fable-team/bin/}"   # bin/ → kit/fable-team/bin/ 짝도 같이 변이한다(시험은 kit 사본을 $B 로 쓰고 kit cmp 도 초록이어야 한다)
  python3 - "$REPO/harness/$f" "$st/harness/$f" "$old" "$new" "$REPO/harness/$kf" "$st/harness/$kf" <<'PP' || { bad "변이 $name 준비 실패(치환 0)"; return; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit("MUT-OLD 없음")
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
if len(sys.argv) == 7:
    k_src, k_dst = sys.argv[5], sys.argv[6]
    ks = open(k_src, encoding="utf-8").read()
    if old in ks:
        open(k_dst, "w", encoding="utf-8").write(ks.replace(old, new, 1))
PP
  local out; out="$(cd "$st/harness" && R921_NO_MUT=1 bash "$st/harness/tests/test_resource_warn_proceed_r921.sh" 2>&1)"
  local syn=0; case "$out" in *"syntax error"*|*"command not found"*) syn=1;; esac
  if [ "$syn" = 1 ]; then bad "변이 $name — 문법 오류라 검출로 안 친다"; return; fi
  local rd=0 gr=0
  case "$out" in *"FAIL ${redl}"*) rd=1;; esac     # 파이프 대신 case — pipefail + grep -q 조기종료의 EPIPE 헛빨강을 피한다
  case "$out" in *"PASS ${greenl}"*) gr=1;; esac
  { [ "$rd" = 1 ] && [ "$gr" = 1 ]; } \
    && ok "변이 $name → «${redl}» 만 빨강(대조 «${greenl}» 초록 · 전체 재실행)" \
    || bad "변이 $name — red=$rd green=$gr syntax=$syn :: $(printf '%s\n' "$out" | grep -E '^FAIL' | head -2 | tr '\n' ' ')"
}
# 변이1 «WARN 을 REJECT 로 복귀» → ⓐ 빨강 · 대조 ⓙ 초록
mutcase "WARN→REJECT 복귀(문지기)" "bin/ft-resource-gate.sh" \
  '[ -z "$WARNS" ] || { echo "WARN resource $WARNS"; exit 0; }' \
  '[ -z "$WARNS" ] || { echo "REJECT resource $WARNS"; exit 3; }' \
  "ⓐ swap" "ⓙ FT_DISK_HARD_MIN_MIB=abc"
# 변이2 «하한 값 검증 끔» → ⓙ 빨강 · 대조 ⓒ 디스크 소프트 초록
mutcase "하한 값 검증 끔" "bin/ft-resource-gate.sh" \
  '[ "$_dh_ok" = 1 ] || { echo "ERROR 하한 값 이상' \
  '[ "$_dh_ok" = 1 ] || [ -n x ] || { echo "ERROR 하한 값 이상' \
  "ⓙ abc" "ⓒ 디스크 4GiB"
# 변이3 «회수 상한 끔» → ⓚ 빨강 · 대조 ⓐ' 초록
mutcase "회수 7초 상한 끔" "bin/ft-reclaim-capped.sh" \
  '  local lim="$FT_RECLAIM_TIMEOUT_SEC"' \
  '  local lim=999' \
  "ⓚ dt=" "ⓐ' 자원 넘김"
# 변이4 «상한 잠금 끔» → ⓛ 빨강 · 대조 ⓗ 초록
mutcase "cap 잠금 끔" "bin/ft-nano-spawn.sh" \
  '    _ts_lock_take "$ROOT/.fable-team/state/nano-cap.lock.d" || _ts_lock_fail=1' \
  '    true' \
  "ⓛ 세션=" "ⓗ cap=4"
# 변이5 «좌석 상한 = cap 에서 큐»(W1 복귀) → ⓝ 빨강 · 대조 ⓗ 초록
mutcase "좌석 상한 cap 에서 큐" "bin/ft-nano-spawn.sh" \
  '          elif [ "$_cl" -ge "$((_cc + 1))" ]; then' \
  '          elif [ "$_cl" -ge "$_cc" ]; then' \
  "ⓝ cap=4·live=4" "ⓗ cap=4"
# 변이6 «하한 자릿수 검사 끔»(W2 큰 수) → ⓞ 빨강 · 대조 ⓙ abc 초록
mutcase "하한 7자리 검사 끔" "bin/ft-resource-gate.sh" \
  '=~ ^[0-9]{1,7}$ ]]' \
  '=~ ^[0-9]+$ ]]' \
  "ⓞ 큰 수" "ⓙ FT_DISK_HARD_MIN_MIB=abc"
# 변이7 «회수 입구 첫 항목만»(W3 복귀) → ⓟ 빨강 · 대조 ⓐ' 초록
mutcase "회수 입구 첫 항목만" "bin/ft-resource-reclaim.sh" \
  "_items0=\"\$(printf '%s\\n' \"\$ONREJ\" | sed -nE 's/^(REJECT|WARN) resource //p' | tr ';' '\\n'" \
  "_items0=\"\$(printf '%s\\n' \"\$ONREJ\" | sed -nE 's/^(REJECT|WARN) resource //p' | sed 's/;.*//'" \
  "ⓟ freeze 뒤 agents" "ⓐ' 자원 넘김"
# 변이8 «abort trap 덮어쓰기»(W4 복귀) → ⓠ 빨강 · 대조 ⓗ 초록
mutcase "abort trap 덮어쓰기" "bin/ft-nano-spawn.sh" \
  '_ON_EXIT+=(_sheet_abort)' \
  'trap _sheet_abort EXIT' \
  "ⓠ 잠금+abort+exit1" "ⓗ cap=4"
fi

# ── 키트 짝 · 문법 ──
for f in ft-resource-gate.sh ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft-research-seat-lib.sh ft-resource-reclaim.sh ft-successor-open.sh ft_spawn_queue.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 cmp 0 $f" || bad "키트 사본 불일치 $f"
done
for f in ft-resource-gate.sh ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft-research-seat-lib.sh ft-resource-reclaim.sh ft-successor-open.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done

echo "fail=$fail"; [ $fail -eq 0 ]
