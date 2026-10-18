#!/usr/bin/env bash
# ft-resource-gate.sh <check [--succession]|status>
#   Res-1014 · 머신 자원(디스크·스왑·메모리·에이전트 수)이 한계를 넘으면 새 좌석 spawn 을 막는다.
#   계기: 2026-10-14 03:31 watchdog 패닉(스왑 23개·디스크 748MiB·활성 claude jsonl ~100).
#   bash 3.2 호환(declare -A 금지) · macOS 전용.
#   check  : 하나라도 넘으면 `REJECT resource <항목>=<값> limit=<문턱>` + exit 3. 통과면 `OK disk=.. swap=.. memfree=.. level=.. rate=.. agents=..` + exit 0.
#            --succession = 승계(1석 교대 · 순증 0)용 별 한도(에이전트 수 면제 · 압력 4 만 거절 · 메모리 10% · 속도 512).
#   status : `disk=.. swap=.. memfree=.. level=.. rate=.. agents=.. freeze=0|1` 1줄 + exit 0.
#   level = kern.memorystatus_vm_pressure_level(1 정상·2 경고·4 위험) · rate = 최근 6표본(pressure.tsv · ft-resource-sample.sh 가 60초마다 씀) 스왑 MiB/분 증가 속도.
#   표본 없음·낡음(>180초) = 문지기가 ft-resource-sample.sh 를 1회 직접 돌려 잰다(실패 rc4) · 줄 5칸 숫자·시각 순서 위반·미래 시각 = exit 4 · 측정 명령 rc≠0 = 출력이 숫자여도 exit 4.
#   rate=na(+stderr WARN 1줄 · 속도 칸만 건너뜀) = 검증 통과한 «1줄뿐»(180초 안)일 때만 — 지나면 다시 재서 2줄이 되므로 영구 예외 아님.
#   측정 실패(명령 없음·파싱 실패)는 통과시키지 않고 `ERROR resource measure <무엇>` + exit 4 (BYZ #0 NO SILENT FALLBACK).
#   동결 파일(.fable-team/state/RESOURCE_FREEZE)이 있으면 check 는 무조건 REJECT.
#   R357: swap 은 «swap>FT_SWAP_HARD_MIB AND level>=FT_SWAP_LEVEL_MIN(2)» 일 때만 거절(`REJECT resource swap=<N>MiB level=<L> limit=<M>MiB@level>=<K>`) · 승계(--succession)는 swap 축 면제 — level 4·memfree·rate 는 그대로. FT_SWAP_LEVEL_MIN 은 양의 정수(아니면 기본 2 + WARN).
#   문턱(env 덮어쓰기): FT_DISK_MIN_GIB=30 · FT_SWAP_HARD_MIB=12288 · FT_SWAP_RATE_MAX=512(승계 FT_SWAP_RATE_MAX_SUCC=1024) · FT_PRESSURE_MAX=2(= level 4 만 거절 · 승계 FT_PRESSURE_MAX_SUCC=3)
#            · FT_MEM_FREE_MIN_PCT=15(승계 FT_MEM_FREE_MIN_SUCC=10) · FT_AGENT_MAX=65 (판정 1699 → 판정 1832 실측 재조정 64 → 오빠 판정 1839 로 55 · 라이브와 일치 · design/harness/staged-r213/RETUNE-1832-20261015.md → 오빠 판정 1883 ②·1885 로 65)
#   FT_SWAP_MAX_MIB(옛 스왑 절대량 8192)는 폐기 · R213 — 읽지 않는다. 절대량 단독 거절 폐기(R357).
#   시험용 env: FT_RES_ROOT(동결 파일이 놓이는 리포 루트 — 기본은 스크립트 위치에서 역산)
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec

CMD="${1:-}"; SUCC=0
case "$CMD" in check|status) ;; *) echo "usage: $0 <check [--succession]|status>" >&2; exit 2;; esac
case "${2:-}" in "") ;; --succession) [ "$CMD" = check ] && SUCC=1 || SUCC=x;; *) SUCC=x;; esac
[ "$SUCC" != x ] || { echo "usage: $0 <check [--succession]|status>" >&2; exit 2; }

DISK_MIN="${FT_DISK_MIN_GIB:-30}"
SWAP_HARD="${FT_SWAP_HARD_MIB:-12288}"
AGENT_MAX="${FT_AGENT_MAX:-65}"
SWAP_LEVEL_MIN="${FT_SWAP_LEVEL_MIN:-2}"
case "$SWAP_LEVEL_MIN" in ''|*[!0-9]*) _slm_bad=1;; *) [ "$((10#$SWAP_LEVEL_MIN))" -ge 1 ] && _slm_bad=0 || _slm_bad=1;; esac
[ "$_slm_bad" = 0 ] || { [ -z "${FT_SWAP_LEVEL_MIN:-}" ] || echo "WARN resource FT_SWAP_LEVEL_MIN=${FT_SWAP_LEVEL_MIN} 무효(양의 정수 아님) — 기본 2 사용" >&2; SWAP_LEVEL_MIN=2; }
if [ "$SUCC" = 1 ]; then
  MEM_MIN="${FT_MEM_FREE_MIN_SUCC:-10}"; RATE_MAX="${FT_SWAP_RATE_MAX_SUCC:-1024}"; LEVEL_MAX="${FT_PRESSURE_MAX_SUCC:-3}"
else
  MEM_MIN="${FT_MEM_FREE_MIN_PCT:-15}"; RATE_MAX="${FT_SWAP_RATE_MAX:-512}"; LEVEL_MAX="${FT_PRESSURE_MAX:-2}"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 리포 루트 = git common-dir — 워크트리 bin 에서 불러도 메인 리포 루트로 통일(동결·tsv 한 곳). git 미가용 대비 FT_RES_ROOT 우선 · 최종 fallback $HERE/../..
RES_ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$RES_ROOT" ] || RES_ROOT="$(cd -- "$HERE/../.." && pwd)"
FREEZE="$RES_ROOT/.fable-team/state/RESOURCE_FREEZE"
PTSV="$RES_ROOT/.fable-team/state/pressure.tsv"

is_int() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

measure_fail() { echo "ERROR resource measure $1"; exit 4; }

# 필수 명령 존재 확인 (없으면 측정 실패로 본다 — 통과 금지)
for _c in df sysctl memory_pressure pgrep awk sort grep; do
  command -v "$_c" >/dev/null 2>&1 || measure_fail "command-missing=$_c"
done

# 측정 명령 1개 실행 — rc≠0 이면 출력이 숫자여도 측정 실패(R213 DA⑥ H1). 출력 = M_OUT.
mrun() { local n="$1"; shift; M_OUT="$("$@" 2>/dev/null)"; [ $? -eq 0 ] || measure_fail "$n rc≠0"; }

# 디스크 여유 GiB = Available(KiB) / 1048576. -P 로 한 줄 고정 포맷 보장.
mrun "disk df" df -Pk /System/Volumes/Data
DISK_KIB="$(printf '%s\n' "$M_OUT" | awk 'NR==2{print $4}')"
is_int "$DISK_KIB" || measure_fail "disk df=$DISK_KIB"
DISK_GIB=$((DISK_KIB/1048576))

# 스왑 사용 MiB — "used = 1234.50M" / "used = 1.50G" 파싱, 단위 환산.
mrun "swap sysctl" sysctl -n vm.swapusage; SWAPLINE="$M_OUT"
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
mrun "memfree memory_pressure" memory_pressure
MEMFREE="$(printf '%s\n' "$M_OUT" | awk -F': ' '/free percentage/{v=$2; gsub(/[^0-9]/,"",v); print v; exit}')"
is_int "$MEMFREE" || measure_fail "memfree memory_pressure=$MEMFREE"

# 커널 압력 단계 — macOS 가 «지금» 판정한 값(후행 없음).
mrun "level sysctl" sysctl -n kern.memorystatus_vm_pressure_level; LEVEL="$M_OUT"
is_int "$LEVEL" || measure_fail "level sysctl=$LEVEL"

# 스왑 증가 속도 MiB/분 — pressure.tsv 마지막 6줄의 첫·끝 표본 기울기 (R213 DA⑥ r2).
#   표본 없음·마지막 표본 180초 넘게 낡음 = 감시자 정지 → 문지기가 ft-resource-sample.sh 를 그 자리에서 1회 돌려 직접 잰다(실패 = rc4 · WARN 1줄로 감시자 확인 요청).
#   줄 검증(1줄이어도 5칸 전부 숫자 · 시각 비내림) 깨짐 · 시각 역행 · 미래 시각(age<0) · 샘플 뒤에도 180초 넘게 낡음 = rc4.
#   rate=na = 검증을 통과한 «1줄뿐»(방금 잰 1줄 또는 감시자 첫 줄 — 180초 안 · 지나면 다시 재서 2줄이 되므로 영구 예외 아님) 일 때만 · 속도 칸만 건너뛴다.
_ptl() { if [ -f "$PTSV" ]; then wc -l < "$PTSV" | tr -d ' '; else echo 0; fi; }
_pt_now="$(date +%s)"; _plines="$(_ptl)"; _plast=""
[ "$_plines" -lt 1 ] || _plast="$(tail -n 1 "$PTSV" | awk -F'\t' '$1~/^[0-9]+$/{print $1}')"
if [ "$_plines" -lt 1 ] || { is_int "$_plast" && [ $((_pt_now - _plast)) -gt 180 ]; }; then
  [ -f "$HERE/ft-resource-sample.sh" ] || measure_fail "pressure sample ft-resource-sample.sh 없음: $HERE"
  _perr="$(FT_RES_ROOT="$RES_ROOT" bash "$HERE/ft-resource-sample.sh" 2>&1 >/dev/null)" || measure_fail "pressure sample 실패: $(printf '%s' "$_perr" | head -c 120) — com.byz.ft-resource-watch 확인"
  echo "WARN resource pressure.tsv 없음/낡음 — 문지기가 표본 1회 직접 측정(com.byz.ft-resource-watch 확인)" >&2
  _pt_now="$(date +%s)"; _plines="$(_ptl)"
fi
RATE=na
_pr="$(tail -n 6 "$PTSV" 2>/dev/null | awk -F'\t' '
  NF!=5 || $1!~/^[0-9]+$/ || $2!~/^[0-9]+$/ || $3!~/^[0-9]+$/ || $4!~/^[0-9]+$/ || $5!~/^[0-9]+$/ { bad=1; exit }
  NR>1 && $1+0<p { bad=1; exit }
  { p=$1+0; if(NR==1){t0=p; s0=$2+0} t1=p; s1=$2+0; n=NR }
  END{ if(bad || n<1) print "BAD"; else if(n==1) printf "na %d", t1; else if(t1-t0<=0) print "BAD"; else printf "%d %d", (s1-s0)*60/(t1-t0), t1 }')"
case "$_pr" in [0-9-]*" "[0-9]*|"na "[0-9]*) ;; *) measure_fail "pressure.tsv corrupt — 5칸·숫자·시각 순서 위반(마지막 6줄) com.byz.ft-resource-watch 확인";; esac
_age=$(( _pt_now - ${_pr#* } ))
[ "$_age" -ge 0 ] || measure_fail "pressure.tsv clock-skew(미래 시각 ${_age}s)"
[ "$_age" -le 180 ] || measure_fail "pressure.tsv stale(${_age}s) — com.byz.ft-resource-watch 확인"
RATE="${_pr% *}"
[ "$RATE" != na ] || echo "WARN resource rate=na pressure.tsv 표본 ${_plines}줄 — 속도 칸만 건너뛰고 판정" >&2

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
  echo "disk=$DISK_GIB swap=$SWAP_MIB memfree=$MEMFREE level=$LEVEL rate=$RATE agents=$AGENTS freeze=$FREEZE_FLAG"
  exit 0
fi

# check
if [ "$FREEZE_FLAG" = 1 ]; then
  echo "REJECT resource freeze=$(sed -n '1p' "$FREEZE" 2>/dev/null) limit=0"
  exit 3
fi
if [ "$DISK_GIB" -lt "$DISK_MIN" ]; then echo "REJECT resource disk=${DISK_GIB}GiB limit=${DISK_MIN}GiB"; exit 3; fi
if [ "$LEVEL" -gt "$LEVEL_MAX" ]; then echo "REJECT resource level=$LEVEL limit=$LEVEL_MAX"; exit 3; fi
# R357: swap 절대량은 커널이 경고(level>=SWAP_LEVEL_MIN)라 말할 때만 거절 · 승계(순증 0)는 swap 축 면제 — level·memfree·rate 는 그대로
if [ "$SUCC" != 1 ] && [ "$SWAP_MIB" -gt "$SWAP_HARD" ] && [ "$LEVEL" -ge "$SWAP_LEVEL_MIN" ]; then echo "REJECT resource swap=${SWAP_MIB}MiB level=${LEVEL} limit=${SWAP_HARD}MiB@level>=${SWAP_LEVEL_MIN}"; exit 3; fi
if [ "$MEMFREE" -lt "$MEM_MIN" ]; then echo "REJECT resource memfree=${MEMFREE}% limit=${MEM_MIN}%"; exit 3; fi
if [ "$RATE" != na ] && [ "$RATE" -gt "$RATE_MAX" ]; then echo "REJECT resource rate=${RATE}MiB/min limit=${RATE_MAX}MiB/min"; exit 3; fi
if [ "$SUCC" != 1 ] && [ "$AGENTS" -gt "$AGENT_MAX" ]; then echo "REJECT resource agents=$AGENTS limit=$AGENT_MAX"; exit 3; fi

echo "OK disk=${DISK_GIB}GiB swap=${SWAP_MIB}MiB memfree=${MEMFREE}% level=$LEVEL rate=$RATE agents=$AGENTS"
exit 0
