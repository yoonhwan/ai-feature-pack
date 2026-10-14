#!/usr/bin/env bash
# ft-resource-gate.sh <check|status>
#   Res-1014 · 머신 자원(디스크·스왑·메모리·에이전트 수)이 한계를 넘으면 새 좌석 spawn 을 막는다.
#   계기: 2026-10-14 03:31 watchdog 패닉(스왑 23개·디스크 748MiB·활성 claude jsonl ~100).
#   bash 3.2 호환(declare -A 금지) · macOS 전용.
#   check  : 하나라도 넘으면 `REJECT resource <항목>=<값> limit=<문턱>` + exit 3. 통과면 `OK disk=.. swap=.. memfree=.. agents=..` + exit 0.
#   status : `disk=.. swap=.. memfree=.. agents=.. freeze=0|1` 1줄 + exit 0.
#   측정 실패(명령 없음·파싱 실패)는 통과시키지 않고 `ERROR resource measure <무엇>` + exit 4 (BYZ #0 NO SILENT FALLBACK).
#   동결 파일(.fable-team/state/RESOURCE_FREEZE)이 있으면 check 는 무조건 REJECT.
#   문턱(env 덮어쓰기): FT_DISK_MIN_GIB=30 · FT_SWAP_MAX_MIB=8192 · FT_MEM_FREE_MIN_PCT=15 · FT_AGENT_MAX=30
#   시험용 env: FT_RES_ROOT(동결 파일이 놓이는 리포 루트 — 기본은 스크립트 위치에서 역산)
set -uo pipefail

CMD="${1:-}"
case "$CMD" in check|status) ;; *) echo "usage: $0 <check|status>" >&2; exit 2;; esac

DISK_MIN="${FT_DISK_MIN_GIB:-30}"
SWAP_MAX="${FT_SWAP_MAX_MIB:-8192}"
MEM_MIN="${FT_MEM_FREE_MIN_PCT:-15}"
AGENT_MAX="${FT_AGENT_MAX:-30}"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 리포 루트 = git common-dir — 워크트리 bin 에서 불러도 메인 리포 루트로 통일(동결·tsv 한 곳). git 미가용 대비 FT_RES_ROOT 우선 · 최종 fallback $HERE/../..
RES_ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$RES_ROOT" ] || RES_ROOT="$(cd -- "$HERE/../.." && pwd)"
FREEZE="$RES_ROOT/.fable-team/state/RESOURCE_FREEZE"

is_int() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

measure_fail() { echo "ERROR resource measure $1"; exit 4; }

# 필수 명령 존재 확인 (없으면 측정 실패로 본다 — 통과 금지)
for _c in df sysctl memory_pressure pgrep awk sort grep; do
  command -v "$_c" >/dev/null 2>&1 || measure_fail "command-missing=$_c"
done

# 디스크 여유 GiB = Available(KiB) / 1048576. -P 로 한 줄 고정 포맷 보장.
DISK_KIB="$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')"
is_int "$DISK_KIB" || measure_fail "disk df=$DISK_KIB"
DISK_GIB=$((DISK_KIB/1048576))

# 스왑 사용 MiB — "used = 1234.50M" / "used = 1.50G" 파싱, 단위 환산.
SWAPLINE="$(sysctl -n vm.swapusage 2>/dev/null)"
SWAP_PAIR="$(printf '%s' "$SWAPLINE" | sed -n 's/.*used = \([0-9][0-9.]*\)\([A-Za-z]\).*/\1 \2/p')"
[ -n "$SWAP_PAIR" ] || measure_fail "swap swapusage=$SWAPLINE"
SWAP_VAL="${SWAP_PAIR% *}"; SWAP_UNIT="${SWAP_PAIR#* }"
SWAP_MIB="$(awk -v v="$SWAP_VAL" -v u="$SWAP_UNIT" 'BEGIN{
  if(v==""){exit 1}
  m=v+0
  if(u=="G"||u=="g") m=v*1024
  else if(u=="K"||u=="k") m=v/1024
  if(m<0) m=0
  printf "%d", m
}')" || measure_fail "swap convert=$SWAP_PAIR"
is_int "$SWAP_MIB" || measure_fail "swap value=$SWAP_MIB"

# 메모리 여유 % — "System-wide memory free percentage: 90%" 끝줄.
MEMFREE="$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{v=$2; gsub(/[^0-9]/,"",v); print v; exit}')"
is_int "$MEMFREE" || measure_fail "memfree memory_pressure=$MEMFREE"

# 에이전트 프로세스 수 — claude(-x) + codex 벤더 바이너리(-x) 의 PID 합집합. 이 세션 자신도 셈. (codex -f 는 npm·node·셸 헬퍼까지 셈 — R169) -a = 조상 포함 · macOS pgrep 기본은 호출 조상 제외.
#   pgrep 은 센서별로 rc·출력을 따로 본다: rc0=출력 전부 숫자 PID · rc1=정상 no-match(빈 출력) · rc≥2·비정상 출력=측정 실패(통과 금지).
PIDS=""
agent_scan() {
  local name="$1" out rc; shift
  out="$(pgrep "$@" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) [ -z "$out" ] || [ -z "$(printf '%s\n' "$out" | grep -v '^[0-9][0-9]*$')" ] || measure_fail "agents pgrep-$name output=$(printf '%s' "$out" | head -c 60 | tr '\n' ' ')";;
    1) [ -z "$out" ] || measure_fail "agents pgrep-$name output=$(printf '%s' "$out" | head -c 60 | tr '\n' ' ')";;
    *) measure_fail "agents pgrep-$name rc=$rc";;
  esac
  PIDS="$PIDS
$out"
}
agent_scan claude -a -x claude
agent_scan codex -a -x codex
AGENTS="$(printf '%s\n' "$PIDS" | grep '^[0-9][0-9]*$' | sort -u | grep -c .)"
is_int "$AGENTS" || measure_fail "agents pgrep=$AGENTS"

FREEZE_FLAG=0; [ -f "$FREEZE" ] && FREEZE_FLAG=1

if [ "$CMD" = status ]; then
  echo "disk=$DISK_GIB swap=$SWAP_MIB memfree=$MEMFREE agents=$AGENTS freeze=$FREEZE_FLAG"
  exit 0
fi

# check
if [ "$FREEZE_FLAG" = 1 ]; then
  echo "REJECT resource freeze=$(sed -n '1p' "$FREEZE" 2>/dev/null) limit=0"
  exit 3
fi
if [ "$DISK_GIB" -lt "$DISK_MIN" ]; then echo "REJECT resource disk=${DISK_GIB}GiB limit=${DISK_MIN}GiB"; exit 3; fi
if [ "$SWAP_MIB" -gt "$SWAP_MAX" ]; then echo "REJECT resource swap=${SWAP_MIB}MiB limit=${SWAP_MAX}MiB"; exit 3; fi
if [ "$MEMFREE" -lt "$MEM_MIN" ]; then echo "REJECT resource memfree=${MEMFREE}% limit=${MEM_MIN}%"; exit 3; fi
if [ "$AGENTS" -gt "$AGENT_MAX" ]; then echo "REJECT resource agents=$AGENTS limit=$AGENT_MAX"; exit 3; fi

echo "OK disk=${DISK_GIB}GiB swap=${SWAP_MIB}MiB memfree=${MEMFREE}% agents=$AGENTS"
exit 0
