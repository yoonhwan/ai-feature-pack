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
# 가짜 센서(PATH 앞)·가짜 tmux·가짜 회수·임시 FT_RES_ROOT 만 쓴다 — 실 좌석·실 회수·실 spawn 0.
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
LOW="FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999"
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
    FT_NANO_PREFIX=byz-r921-nano- FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 \
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
  FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 \
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

# ══ ⓕ 팀 AT-CAP ══
# 가짜 tmux 세션 목록 = «파일» — 회수 스텁이 그 파일에서 1줄 지우면(=끝난 나노를 닫았다) 자리가 나고, 못 지우면 AT-CAP 이 남는다.
mkdir -p "$R/design/alpha/indices/대기" && echo "# 카드" > "$R/design/alpha/indices/대기/f.md"
printf '{"_master":"byz-alpha-master-claude#1"}\n' > "$R/.fable-team/seats-alpha.json"
printf '# 표\n## 표 1 — 역할\n| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |\n|---|---|---|---|---|---|---|\n| nano | 상한 N | `m` | high | — | a | b |\n- 나노 상한 기본: 3\n## 표 2 — 팀\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 2 | 0 | 아니오 |\n' > "$T/TEAMSET.md"
SESSF="$T/sessions.txt"
capspawn() { # [--nodry] <env…> — 팀 상한 칸까지 지나간 spawn 1회(기본 dry-run · 회수 호출은 dry-run 에서 0 이므로 ⓕ-1 은 --nodry)
  local dry="--dry-run"; [ "${1:-}" = --nodry ] && { dry=""; shift; }
  printf 'byz-alpha-nano-a#0\nbyz-alpha-nano-b#0\n' > "$SESSF"
  rm -f "$T/low" "$R/.fable-team/state/spawn-queue-alpha.tsv" "$R/.fable-team/state/spawn-queue-alpha.notified"; : > "$CALL_LOG"
  OUT="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE HOME="$T/home" PATH="$S:$PATH" FT_RES_ROOT="$R" FT_ROOT="$R" FAKE_TOPDIR="$R" \
    TMUX_SESS_FILE="$SESSF" FT_TEAMSET_MD="$T/TEAMSET.md" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$R/.fable-team/seats-alpha.json" \
    FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 FAKE_LOWFILE="$T/low" \
    "$@" bash "$B/ft-nano-spawn.sh" "$R/design/alpha/indices/대기/f.md" --from byz-alpha-master-claude#1 $dry 2>&1)"; RC=$?
}
# ⓕ-1 끝난 나노 1 → 회수(--team)가 1석 닫음 → AT-CAP 아닌 CAP 로 열림(회수 호출은 정확히 1회)
cat > "$B/ft-resource-reclaim.sh" <<'X'
#!/bin/sh
echo "reclaim $*" >> "${CALL_LOG:-/dev/null}"
[ -f "$TMUX_SESS_FILE" ] && { tail -n +2 "$TMUX_SESS_FILE" > "$TMUX_SESS_FILE.n" && mv "$TMUX_SESS_FILE.n" "$TMUX_SESS_FILE"; }
echo "RECLAIMED 1"
X
chmod 755 "$B/ft-resource-reclaim.sh"
capspawn --nodry
{ case "$OUT" in *"AT-CAP alpha"*) false;; *) true;; esac && case "$OUT" in *"WARN resource teamset"*) false;; *) true;; esac; } \
  && ok "ⓕ-1 회수(--team) 1회로 자리가 나면 CAP 로 열린다(AT-CAP·WARN 0)" || bad "ⓕ-1 rc=$RC $OUT"
{ [ "$(grep -c '^reclaim ' "$CALL_LOG" 2>/dev/null || true)" = 1 ] && has "$(cat "$CALL_LOG")" "reclaim --caller byz-alpha-master-claude#1" "ⓕ-1 회수 호출 = --caller + 1회"; } \
  || bad "ⓕ-1 회수 호출 인자 — $(cat "$CALL_LOG")"
# ⓕ-2 끝난 나노 0 → 회수해도 AT-CAP → WARN + 연다 · 순번 큐 적재 0
printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\necho "RECLAIMED 0"\nexit 0\n' > "$B/ft-resource-reclaim.sh"; chmod 755 "$B/ft-resource-reclaim.sh"
capspawn
{ case "$OUT" in *"AT-CAP alpha live=2 cap=2"*) true;; *) false;; esac && case "$OUT" in *"WARN resource teamset"*) true;; *) false;; esac \
  && ! case "$OUT" in *QUEUED*) true;; *) false;; esac && [ ! -f "$R/.fable-team/state/spawn-queue-alpha.tsv" ]; } \
  && ok "ⓕ-2 AT-CAP + 회수 0 → WARN + 연다(큐 적재 0)" || bad "ⓕ-2 rc=$RC $OUT"
# ⓕ-3 쌓인 큐 — AT-CAP(빈 석 0)이어도 맨 앞 카드를 master 에게 알린다(다음 tick 이 앞에서부터 연다)
mkdir -p "$R/.fable-team/state"
printf '%s\t%s\n' "$R/design/alpha/indices/대기/f.md" "byz-alpha-master-claude#1" > "$R/.fable-team/state/spawn-queue-alpha.tsv"
rm -f "$R/.fable-team/state/spawn-queue-alpha.notified"
printf '#!/bin/sh\necho "mbox $*" >> "${CALL_LOG:-/dev/null}"\nexit 0\n' > "$R/.fable-team/comm/mbox.sh"; chmod 755 "$R/.fable-team/comm/mbox.sh"
: > "$CALL_LOG"
OUT="$(cd "$R" && env PATH="$S:$PATH" python3 "$B/ft_spawn_queue.py" notify --root "$R" --prefix byz-alpha-nano- --mbox "$R/.fable-team/comm/mbox.sh" --to byz-alpha-master-claude#1 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && has "$(cat "$CALL_LOG")" "mbox send byz-alpha-master-claude#1" "ⓕ-3 쌓인 큐 → 맨 앞 카드를 master 에게 알린다(AT-CAP 이어도)"; } || bad "ⓕ-3 큐 알림 rc=$RC $OUT"
# ⓕ-4 free 가 0/음수여도 알림이 나간다(옛 코드는 free<=0 이면 침묵 — 큐가 영영 안 열리던 회귀를 고정)
rm -f "$R/.fable-team/state/spawn-queue-alpha.notified"; : > "$CALL_LOG"
cat > "$T/q.py" <<'PP'
import sys
sys.path.insert(0, sys.argv[1])
import ft_spawn_queue as q
print(repr(q.notify_master(sys.argv[2], "byz-alpha-nano-", -1, "byz-alpha-master-claude#1")))
PP
OUT="$(cd "$R" && env PATH="$S:$PATH" python3 "$T/q.py" "$B" "$R" 2>&1)"
{ case "$OUT" in *"''"*) false;; *) true;; esac && has "$(cat "$CALL_LOG")" "mbox send byz-alpha-master-claude#1" "ⓕ-4 free=-1(초과) 여도 큐 알림이 나간다(r921)"; } || bad "ⓕ-4 free=-1 침묵 — 큐가 영영 안 열린다 «$OUT»"

# ══ ⓖ tick 죽은 좌석 재개 — 자원 넘음 → WARN + 재개 진행 ══
grep -q '자원 WARN — 재개 진행' "$BIN/ft-tick.sh" && ok "ⓖ tick 재개 경로가 «WARN + 진행» 갈래를 갖는다" || bad "ⓖ tick 에 WARN 갈래 없음"
grep -q '(REJECT|WARN) resource' "$BIN/ft-tick.sh" && ok "ⓖ tick 이 문지기 WARN 줄을 읽는다" || bad "ⓖ tick WARN 판독 없음"
# 문지기 단독: 재개 전 호출이 WARN(rc0)이면 «재개 0» 이 아니라 «진행» 으로 읽히는지 — 판정식 그대로
rm -f "$T/low"; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" FAKE_LEVEL=4 FT_PRESSURE_MAX=2 bash "$B/ft-resource-gate.sh" check 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && case "$OUT" in *"WARN resource level=4"*) true;; *) false;; esac; } && ok "ⓖ 재개 전 문지기 판정 = WARN rc0(멈춤 아님)" || bad "ⓖ 재개 전 판정 rc=$RC $OUT"

# ══ 변이 대조 — 고침을 되돌리면 그 칸이 «빨강» 이어야 한다(카드 완료 조건) ══
MB="$T/mbin"
mutbin() { # <이름> <파일> <old> <new> — 임시 bin 사본에 치환 1회(치환 0 = 준비 실패)
  rm -rf "$MB"; cp -R "$B" "$MB"
  python3 - "$B/$1" "$MB/$1" "$2" "$3" <<'PP'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit("MUT-OLD 없음")
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PP
}
# 변이1 «WARN 을 REJECT 로 복귀» → ⓐ(축 넘김 = WARN+진행) 가 빨강
if mutbin ft-resource-gate.sh '[ -z "$WARNS" ] || { echo "WARN resource $WARNS"; exit 0; }' '[ -z "$WARNS" ] || { echo "REJECT resource $WARNS"; exit 3; }' 2>"$T/m.err"; then
  rm -f "$T/low"
  OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" $LOW FAKE_AGENTS=99 FT_AGENT_MAX=65 bash "$MB/ft-resource-gate.sh" check 2>&1)"; RC=$?
  { [ "$RC" = 3 ]; } && ok "변이1(WARN→REJECT 복귀) → ⓐ 빨강(rc3)" || bad "변이1 이 안 잡힘 rc=$RC $OUT"
else bad "변이1 준비 실패 — $(cat "$T/m.err")"; fi
# 변이2 «동결을 다시 REJECT» → ⓔ 가 빨강
if mutbin ft-resource-gate.sh '[ "$FREEZE_FLAG" = 1 ] && warn_add "freeze=$(sed -n '"'"'1p'"'"' "$FREEZE" 2>/dev/null) limit=0"' '[ "$FREEZE_FLAG" = 1 ] && { echo "REJECT resource freeze=시험 동결 limit=0"; exit 3; }' 2>"$T/m.err"; then
  frz
  OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" $LOW bash "$MB/ft-resource-gate.sh" check 2>&1)"; RC=$?; rmfrz
  { [ "$RC" = 3 ]; } && ok "변이2(동결 REJECT 복귀) → ⓔ 빨강(rc3)" || bad "변이2 가 안 잡힘 rc=$RC $OUT"
else bad "변이2 준비 실패 — $(cat "$T/m.err")"; fi
# 변이3 «AT-CAP 을 순번 큐로 복귀» → ⓕ 가 빨강(QUEUED · rc7 · 큐 파일 생김)
if mutbin ft-nano-spawn.sh '    4) echo "WARN resource teamset $(printf '"'"'%s'"'"' "$_tso" | head -1) — 팀 나노 상한을 넘긴 채 연다(r921: 회수 1회 뒤에도 AT-CAP · 순번 큐 적재 0)" >&2;;' '    4) python3 "$HERE/ft_spawn_queue.py" add --root "$ROOT" --prefix "$_tsp" --card "$IDX" --from "$FROM"; exit 7;;' 2>"$T/m.err"; then
  printf '#!/bin/sh\necho "reclaim $*" >> "${CALL_LOG:-/dev/null}"\necho "RECLAIMED 0"\nexit 0\n' > "$MB/ft-resource-reclaim.sh"; chmod 755 "$MB/ft-resource-reclaim.sh"
  BSV="$B"; B="$MB"; export B; capspawn; B="$BSV"; export B   # 변이 bin 으로 같은 ⓕ 상황을 다시 돌린다
  { case "$OUT" in *QUEUED*) true;; *) false;; esac || [ "$RC" = 7 ]; } && ok "변이3(AT-CAP→순번 큐 복귀) → ⓕ 빨강(QUEUED/rc7)" || bad "변이3 이 안 잡힘 rc=$RC $OUT"
else bad "변이3 준비 실패 — $(cat "$T/m.err")"; fi
# 변이4 «디스크 하드 하한 끔» → ⓒ 가 빨강(거절 0)
if mutbin ft-resource-gate.sh 'if [ "$DISK_MIB" != na ] && [ "$DISK_MIB" -lt "$DISK_HARD_MIB" ]; then echo "REJECT resource disk=${DISK_MIB}MiB limit=${DISK_HARD_MIB}MiB"; exit 3; fi' ':' 2>"$T/m.err"; then
  OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" FAKE_LOWFILE="$T/low" FAKE_DISK_KIB=$((500*1024)) FT_DISK_HARD_MIN_MIB=1024 FT_DISK_MIN_GIB=0 bash "$MB/ft-resource-gate.sh" check 2>&1)"; RC=$?
  { [ "$RC" != 3 ]; } && ok "변이4(디스크 하한 끔) → ⓒ 빨강(거절 사라짐)" || bad "변이4 가 안 잡힘 rc=$RC $OUT"
else bad "변이4 준비 실패 — $(cat "$T/m.err")"; fi

# ── 키트 짝 · 문법 ──
for f in ft-resource-gate.sh ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft-research-seat-lib.sh ft-resource-reclaim.sh ft-successor-open.sh ft_spawn_queue.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 cmp 0 $f" || bad "키트 사본 불일치 $f"
done
for f in ft-resource-gate.sh ft-nano-spawn.sh ft-role-spawn.sh ft-tick.sh ft-research-seat-lib.sh ft-resource-reclaim.sh ft-successor-open.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done

echo "fail=$fail"; [ $fail -eq 0 ]
