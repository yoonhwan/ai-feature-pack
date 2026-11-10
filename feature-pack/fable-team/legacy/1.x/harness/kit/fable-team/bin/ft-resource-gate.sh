#!/usr/bin/env bash
# ft-resource-gate.sh <check [--succession|--research]|status>
#   Res-1014 · 머신 자원(디스크·스왑·메모리·압력·에이전트 수)을 재서 «쓸 수 있나» 를 판정한다.
#   계기: 2026-10-14 03:31 watchdog 패닉(스왑 23개·디스크 748MiB·활성 claude jsonl ~100).
#   bash 3.2 호환(declare -A 금지) · macOS 전용.
# ★r921(오빠 2026-10-25 «컴퓨터가 죽어버려도 개발은 해야지 멈춰 있으면 머할건데») — 판정 갈래 3개★
#   check  : OK    = `OK disk=.. swap=.. memfree=.. level=.. rate=.. agents=..` + exit 0
#            WARN  = 문턱을 넘었거나 못 쟀다 → `WARN resource <항목>=<값> limit=<문턱>; …` 1줄 + exit 0. ★진행한다★
#                    (넘은 항목마다 한 조각 · «; » 로 잇는다 · 조각 = `disk=12GiB limit=30GiB` 또는 `swap 측정실패(df rc≠0)`)
#                    부르는 쪽(spawn·tick)이 WARN 을 받으면 회수(ft-resource-reclaim) 1회 → 다시 check → 그래도 WARN 이면 그대로 진행한다.
#            REJECT = 새 파일을 못 쓰는 «진짜 못 쓰는» 두 경우만 → `REJECT resource …` + exit 3
#                    ⓐ 디스크 여유 < FT_DISK_HARD_MIN_MIB(기본 1024 MiB) ⓑ 디스크 측정 실패(못 재면 새 파일 쓸 수 있는지도 모른다)
#            하한 env(FT_DISK_HARD_MIN_MIB)가 1~7자리 양의 정수가 아니면(문자·0·음수·큰 수) «ERROR 하한 값 이상(<값>)» + exit 3 — 기본값으로 떨어뜨리지 않는다(W2).
#            디스크 비교에서 정수 비교 오류가 나면(측정값·문턱 이상) «디스크 측정 실패» REJECT + exit 3(W2 r2).
#            그 밖의 측정 실패(swap·level·memfree·rate·agents)는 REJECT 가 아니라 WARN + 그 축만 건너뛴다(rc0 · BYZ #0 은 «조용한 통과» 만 금지 — 낼 수 없는 판정으로 팀을 세우지 않는다 · 오빠 21:5x).
#            ★exit 4 는 없어졌다★ — 옛 호출자(tick·reclaim)의 «ERROR resource measure» 갈래는 이제 WARN rc0 이다.
#            --succession = 승계(1석 교대 · 순증 0)용 별 한도(에이전트 수 면제 · 압력 4 만 넘음 · 메모리 10% · 속도 1024).
#            --research   = 리서치 나노(r672 의 동결 면제 표식) — r921 부터 동결도 WARN(모든 갈래가 WARN)이라 표식은 출력 문구에만 남는다.
#   status : `disk=.. swap=.. memfree=.. level=.. rate=.. agents=.. freeze=0|1` 1줄 + exit 0 · 못 잰 축은 `na`.
#   level = kern.memorystatus_vm_pressure_level(1 정상·2 경고·4 위험) · rate = 최근 6표본(pressure.tsv · ft-resource-sample.sh 가 60초마다 씀) 스왑 MiB/분 증가 속도.
#   표본 없음·낡음(>180초) = 문지기가 ft-resource-sample.sh 를 1회 직접 돌려 잰다(실패 = WARN rate). 줄 5칸 숫자·시각 순서 위반·미래 시각 = WARN rate.
#   동결 파일(.fable-team/state/RESOURCE_FREEZE)이 있으면 check 는 WARN r672 는 승계·리서치만 통과시켰지만 **r921 부터 모든 spawn 이 WARN + 진행** — 동결은 «알림용» 표식으로 강등(오빠 10-19 «동결 표식이 머냐고 또 막고 앉았네»).
#   R357: swap 은 «swap>FT_SWAP_HARD_MIB AND level>=FT_SWAP_LEVEL_MIN(2) AND memfree<FT_SWAP_MEMFREE_MAX» 일 때만 넘음(넘어도 WARN) · 승계(--succession)는 swap 축 면제 — level 4·memfree·rate 는 그대로.
#   문턱(env 덮어쓰기): FT_DISK_HARD_MIN_MIB=1024(유일한 REJECT 문턱) · FT_DISK_MIN_GIB=30(WARN) · FT_SWAP_HARD_MIB=12288 · FT_SWAP_RATE_MAX=512(승계 FT_SWAP_RATE_MAX_SUCC=1024)
#            · FT_PRESSURE_MAX=2(= level 4 가 넘음 · 승계 FT_PRESSURE_MAX_SUCC=3) · FT_SWAP_MEMFREE_MAX=30 · FT_MEM_FREE_MIN_PCT=15(승계 FT_MEM_FREE_MIN_SUCC=10) · FT_AGENT_MAX=65(오빠 판정 1883 ②·1885)
#   FT_SWAP_MAX_MIB(옛 스왑 절대량 8192)는 폐기 · R213 — 읽지 않는다.
#   시험용 env: FT_RES_ROOT(동결 파일이 놓이는 리포 루트 — 기본은 스크립트 위치에서 역산)
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec

CMD="${1:-}"; SUCC=0; RESEARCH=0
case "$CMD" in check|status) ;; *) echo "usage: $0 <check [--succession|--research]|status>" >&2; exit 2;; esac
case "${2:-}" in "") ;; --succession) [ "$CMD" = check ] && SUCC=1 || SUCC=x;; --research) [ "$CMD" = check ] && RESEARCH=1 || SUCC=x;; *) SUCC=x;; esac
[ "$SUCC" != x ] || { echo "usage: $0 <check [--succession|--research]|status>" >&2; exit 2; }

. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-resource-swap-lib.sh" || { echo "ERROR resource ft-resource-swap-lib.sh 없음(r672: swap 축 판정 한 곳)"; exit 4; }   # r672 H2: 문지기·감시자가 같은 함수를 쓴다
# ★W2(DA⑥ r1 · r2)★ 하한 값 검증 — 빈 값 = 1024 · 유효 = 숫자 1~7자리(최대 9,999,999 MiB) ∧ 1 이상 · 그 밖(문자·0·음수·큰 수)은 «기본으로 떨어뜨리지 않고» ERROR + rc3
#   (큰 수는 산술 넘침으로 작은 값이 된다 — 18446744073709551617 → 1 · 설정 오류를 «여유 있음» 으로 읽으면 문이 열린다 · BYZ #0 NO SILENT FALLBACK)
DISK_HARD_MIB="${FT_DISK_HARD_MIN_MIB:-1024}"
_dh_ok=0; [[ "$DISK_HARD_MIB" =~ ^[0-9]{1,7}$ ]] && [ "$((10#$DISK_HARD_MIB))" -ge 1 ] && _dh_ok=1
[ "$_dh_ok" = 1 ] || { echo "ERROR 하한 값 이상(${FT_DISK_HARD_MIN_MIB:-}) — FT_DISK_HARD_MIN_MIB 는 1~9999999 MiB 정수(기본 1024)"; exit 3; }
[ "$_dh_ok" != 1 ] || DISK_HARD_MIB="$((10#$DISK_HARD_MIB))"
DISK_MIN="${FT_DISK_MIN_GIB:-30}"
SWAP_HARD="${FT_SWAP_HARD_MIB:-12288}"
AGENT_MAX="${FT_AGENT_MAX:-65}"
SWAP_LEVEL_MIN="${FT_SWAP_LEVEL_MIN:-2}"
ft_swap_memfree_max; SWAP_MEMFREE_MAX="$FT_SWAP_MEMFREE_MAX_VAL"; [ -z "${FT_SWAP_MEMFREE_WARN:-}" ] || echo "WARN resource ${FT_SWAP_MEMFREE_WARN}" >&2   # r672: 판정·문턱은 ft-resource-swap-lib.sh 한 곳(감시자와 같은 함수·같은 env)
case "$SWAP_LEVEL_MIN" in ''|*[!0-9]*) _slm_bad=1;; *) [ "$((10#$SWAP_LEVEL_MIN))" -ge 1 ] && _slm_bad=0 || _slm_bad=1;; esac
[ "$_slm_bad" = 0 ] || { [ -z "${FT_SWAP_LEVEL_MIN:-}" ] || echo "WARN resource FT_SWAP_LEVEL_MIN=${FT_SWAP_LEVEL_MIN} 무효(양의 정수 아님) — 기본 2 사용" >&2; SWAP_LEVEL_MIN=2; }
if [ "$SUCC" = 1 ]; then
  MEM_MIN="${FT_MEM_FREE_MIN_SUCC:-10}"; RATE_MAX="${FT_SWAP_RATE_MAX_SUCC:-1024}"; LEVEL_MAX="${FT_PRESSURE_MAX_SUCC:-3}"
else
  MEM_MIN="${FT_MEM_FREE_MIN_PCT:-15}"; RATE_MAX="${FT_SWAP_RATE_MAX:-512}"; LEVEL_MAX="${FT_PRESSURE_MAX:-2}"
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 리포 루트 = git common-dir — 워크트리 bin 에서 불러도 메인 리포 루트로 통일(동결·tsv 한 곳). git 미가용 대비 FT_RES_ROOT 우선 · 그다음 ft_repo_root(옛 설치 꼴 · cwd) · 못 풀면 ERROR
RES_ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$RES_ROOT" ] || { . "$HERE/ft-harness-root.sh" && RES_ROOT="$(ft_repo_root "$HERE")"; } || exit 3
FREEZE="$RES_ROOT/.fable-team/state/RESOURCE_FREEZE"
PTSV="$RES_ROOT/.fable-team/state/pressure.tsv"

is_int() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

# ── WARN 누적기(r921) — 넘은 축·못 잰 축을 모아 «1줄» 로 낸다. 디스크 측정 실패만 REJECT(= 새 파일을 못 쓸 수 있다).
WARNS=""
warn_add() { WARNS="${WARNS:+$WARNS; }$1"; }
mf() {   # <축> <사유>
  case "$1" in
    disk) echo "REJECT resource disk-measure $2 limit=reject"; exit 3;;
  esac
  warn_add "$1 측정실패($2)"
}
# 측정 명령 1개 실행 — 출력 = M_OUT · rc 반환(부르는 쪽이 mf 로 갈래를 정한다).
mrun() { M_OUT="$("$@" 2>/dev/null)"; }

# 디스크 여유 — GiB(문턱 판정)·MiB(하드 하한 판정). -P 로 한 줄 고정 포맷 보장.
DISK_KIB=na; DISK_GIB=na; DISK_MIB=na
if ! command -v df >/dev/null 2>&1; then mf disk "command-missing=df"
elif mrun df -Pk /System/Volumes/Data; then
  _k="$(printf '%s\n' "$M_OUT" | awk 'NR==2{print $4}')"
  if is_int "$_k"; then DISK_KIB="$_k"; DISK_GIB=$((_k/1048576)); DISK_MIB=$((_k/1024)); else mf disk "df=$_k"; fi
else mf disk "df rc≠0"; fi

# 스왑 사용 MiB — "used = 1234.50M" / "used = 1.50G" 파싱, 단위 환산.
SWAP_MIB=na
if ! command -v sysctl >/dev/null 2>&1; then mf swap "command-missing=sysctl"
elif mrun sysctl -n vm.swapusage; then
  SWAPLINE="$M_OUT"
  SWAP_PAIR="$(printf '%s' "$SWAPLINE" | sed -n 's/.*used = \([0-9][0-9.]*\)\([A-Za-z]\).*/\1 \2/p')"
  if [ -z "$SWAP_PAIR" ]; then mf swap "swapusage=$SWAPLINE"
  else
    SWAP_VAL="${SWAP_PAIR% *}"; SWAP_UNIT="${SWAP_PAIR#* }"
    if _sw="$(awk -v v="$SWAP_VAL" -v u="$SWAP_UNIT" 'BEGIN{
      if(v==""){exit 1}
      m=v+0
      if(u=="G"||u=="g") m=v*1024
      else if(u=="K"||u=="k") m=v/1024
      if(m<0) m=0
      printf "%d", m
    }')" && is_int "$_sw"; then SWAP_MIB="$_sw"; else mf swap "convert=$SWAP_PAIR"; fi
  fi
else mf swap "sysctl rc≠0"; fi

# 메모리 여유 % — "System-wide memory free percentage: 90%" 끝줄.
MEMFREE=na
if ! command -v memory_pressure >/dev/null 2>&1; then mf memfree "command-missing=memory_pressure"
elif mrun memory_pressure; then
  _m="$(printf '%s\n' "$M_OUT" | awk -F': ' '/free percentage/{v=$2; gsub(/[^0-9]/,"",v); print v; exit}')"
  if is_int "$_m"; then MEMFREE="$_m"; else mf memfree "memory_pressure=$_m"; fi
else mf memfree "memory_pressure rc≠0"; fi

# 커널 압력 단계 — macOS 가 «지금» 판정한 값(후행 없음).
LEVEL=na
if ! command -v sysctl >/dev/null 2>&1; then mf level "command-missing=sysctl"
elif mrun sysctl -n kern.memorystatus_vm_pressure_level; then
  if is_int "$M_OUT"; then LEVEL="$M_OUT"; else mf level "sysctl=$M_OUT"; fi
else mf level "sysctl rc≠0"; fi

# 스왑 증가 속도 MiB/분 — pressure.tsv 마지막 6줄의 첫·끝 표본 기울기 (R213 DA⑥ r2).
#   표본 없음·마지막 표본 180초 넘게 낡음 = 감시자 정지 → 문지기가 ft-resource-sample.sh 를 그 자리에서 1회 돌려 직접 잰다(실패 = WARN rate).
#   줄 검증(1줄이어도 5칸 전부 숫자 · 시각 비내림) 깨짐 · 시각 역행 · 미래 시각(age<0) · 샘플 뒤에도 180초 넘게 낡음 = WARN rate.
#   rate=na = 검증을 통과한 «1줄뿐»(방금 잰 1줄 또는 감시자 첫 줄 — 180초 안) 일 때만 · 속도 칸만 건너뛴다.
_ptl() { if [ -f "$PTSV" ]; then wc -l < "$PTSV" | tr -d ' '; else echo 0; fi; }
RATE=na; _rfail=""
if ! command -v awk >/dev/null 2>&1; then _rfail="command-missing=awk"
elif ! command -v sort >/dev/null 2>&1; then _rfail="command-missing=sort"
else
  _pt_now="$(date +%s)"; _plines="$(_ptl)"; _plast=""
  [ "$_plines" -lt 1 ] || _plast="$(tail -n 1 "$PTSV" | awk -F'\t' '$1~/^[0-9]+$/{print $1}')"
  if [ "$_plines" -lt 1 ] || { is_int "$_plast" && [ $((_pt_now - _plast)) -gt 180 ]; }; then
    if [ ! -f "$HERE/ft-resource-sample.sh" ]; then _rfail="ft-resource-sample.sh 없음: $HERE"
    elif _perr="$(FT_RES_ROOT="$RES_ROOT" bash "$HERE/ft-resource-sample.sh" 2>&1 >/dev/null)"; then
      echo "WARN resource pressure.tsv 없음/낡음 — 문지기가 표본 1회 직접 측정(com.byz.ft-resource-watch 확인)" >&2
      _pt_now="$(date +%s)"; _plines="$(_ptl)"
    else _rfail="pressure sample 실패: $(printf '%s' "$_perr" | head -c 120) — com.byz.ft-resource-watch 확인"; fi
  fi
  if [ -z "$_rfail" ]; then
    _pr="$(tail -n 6 "$PTSV" 2>/dev/null | awk -F'\t' '
      NF!=5 || $1!~/^[0-9]+$/ || $2!~/^[0-9]+$/ || $3!~/^[0-9]+$/ || $4!~/^[0-9]+$/ || $5!~/^[0-9]+$/ { bad=1; exit }
      NR>1 && $1+0<p { bad=1; exit }
      { p=$1+0; if(NR==1){t0=p; s0=$2+0} t1=p; s1=$2+0; n=NR }
      END{ if(bad || n<1) print "BAD"; else if(n==1) printf "na %d", t1; else if(t1-t0<=0) print "BAD"; else printf "%d %d", (s1-s0)*60/(t1-t0), t1 }')"
    case "$_pr" in
      [0-9-]*" "[0-9]*|"na "[0-9]*) RATE="${_pr% *}"; _age=$(( _pt_now - ${_pr#* } ))
        [ "$_age" -ge 0 ] || { RATE=na; _rfail="pressure.tsv clock-skew(미래 시각 ${_age}s)"; }
        [ "$_rfail" = "" ] && [ "$_age" -gt 180 ] && { RATE=na; _rfail="pressure.tsv stale(${_age}s) — com.byz.ft-resource-watch 확인"; };;
      *) _rfail="pressure.tsv corrupt — 5칸·숫자·시각 순서 위반(마지막 6줄) com.byz.ft-resource-watch 확인";;
    esac
  fi
fi
if [ -n "$_rfail" ]; then mf rate "$_rfail"; else
  [ "$RATE" != na ] || echo "WARN resource rate=na pressure.tsv 표본 ${_plines}줄 — 속도 칸만 건너뛰고 판정" >&2
fi

# 에이전트 프로세스 수 — claude(-x) + codex 벤더 바이너리(-x) 의 PID 합집합. 이 세션 자신도 셈. (codex -f 는 npm·node·셸 헬퍼까지 셈 — R169) -a = 조상 포함 · macOS pgrep 기본은 호출 조상 제외.
#   pgrep 은 센서별로 rc·출력을 따로 본다: rc0=출력 전부 숫자 PID · rc1=정상 no-match(빈 출력) · rc≥2·비정상 출력=측정 실패(WARN agents · r921).
PIDS=""; _aerr=""
agent_scan() {
  local name="$1" out rc; shift
  out="$(pgrep "$@" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) [ -z "$out" ] || [ -z "$(printf '%s\n' "$out" | grep -v '^[0-9][0-9]*$')" ] || _aerr="pgrep-$name output=$(printf '%s' "$out" | head -c 60 | tr '\n' ' ')";;
    1) [ -z "$out" ] || _aerr="pgrep-$name output=$(printf '%s' "$out" | head -c 60 | tr '\n' ' ')";;
    *) _aerr="pgrep-$name rc=$rc";;
  esac
  PIDS="$PIDS
$out"
}
AGENTS=na
if ! command -v pgrep >/dev/null 2>&1; then mf agents "command-missing=pgrep"
else
  agent_scan claude -a -x claude
  agent_scan codex -a -x codex
  if [ -n "$_aerr" ]; then mf agents "$_aerr"
  else
    _ag="$(printf '%s\n' "$PIDS" | grep '^[0-9][0-9]*$' | sort -u | grep -c .)"
    if is_int "$_ag"; then AGENTS="$_ag"; else mf agents "count=$_ag"; fi
  fi
fi

FREEZE_FLAG=0; [ -f "$FREEZE" ] && FREEZE_FLAG=1

if [ "$CMD" = status ]; then
  echo "disk=$DISK_GIB swap=$SWAP_MIB memfree=$MEMFREE level=$LEVEL rate=$RATE agents=$AGENTS freeze=$FREEZE_FLAG"
  exit 0
fi

# check — ★r921★ 넘으면 WARN 1줄 + exit 0(진행) · 디스크 하드 하한·디스크 측정 실패만 REJECT
[ "$FREEZE_FLAG" = 1 ] && warn_add "freeze=$(sed -n '1p' "$FREEZE" 2>/dev/null) limit=0"
# W2(r2): 디스크 비교의 정수 비교 오류(rc≥2 · 측정값·문턱 이상)는 «안 넘음» 이 아니다 — 디스크 측정 실패 REJECT rc3(WARN + rc0 으로 새는 길 0)
if [ "$DISK_MIB" != na ]; then
  [ "$DISK_MIB" -lt "$DISK_HARD_MIB" ] 2>/dev/null; _dc=$?
  case "$_dc" in 0) echo "REJECT resource disk=${DISK_MIB}MiB limit=${DISK_HARD_MIB}MiB"; exit 3;; 1) ;; *) mf disk "디스크 측정 실패(비교 오류 disk=${DISK_MIB}MiB limit=${DISK_HARD_MIB}MiB)";; esac
fi
if [ "$DISK_GIB" != na ]; then
  [ "$DISK_GIB" -lt "$DISK_MIN" ] 2>/dev/null; _dc=$?
  case "$_dc" in 0) warn_add "disk=${DISK_GIB}GiB limit=${DISK_MIN}GiB";; 1) ;; *) mf disk "디스크 측정 실패(비교 오류 disk=${DISK_GIB}GiB limit=${DISK_MIN}GiB)";; esac
fi
if [ "$LEVEL" != na ] && [ "$LEVEL" -gt "$LEVEL_MAX" ]; then warn_add "level=$LEVEL limit=$LEVEL_MAX"; fi
# R357: swap 절대량은 커널이 경고(level>=SWAP_LEVEL_MIN)라 말할 때만 넘음 · 승계(순증 0)는 swap 축 면제 — level·memfree·rate 는 그대로
if [ "$SUCC" != 1 ] && [ "$SWAP_MIB" != na ] && [ "$LEVEL" != na ] && [ "$MEMFREE" != na ] && ft_swap_axis_hit "$SWAP_MIB" "$LEVEL" "$MEMFREE" "$SWAP_HARD" "$SWAP_LEVEL_MIN" "$SWAP_MEMFREE_MAX"; then
  warn_add "swap=${SWAP_MIB}MiB level=${LEVEL} memfree=${MEMFREE}% limit=${SWAP_HARD}MiB@level>=${SWAP_LEVEL_MIN}&memfree<${SWAP_MEMFREE_MAX}"
fi
if [ "$MEMFREE" != na ] && [ "$MEMFREE" -lt "$MEM_MIN" ]; then warn_add "memfree=${MEMFREE}% limit=${MEM_MIN}%"; fi
if [ "$RATE" != na ] && [ "$RATE" -gt "$RATE_MAX" ]; then warn_add "rate=${RATE}MiB/min limit=${RATE_MAX}MiB/min"; fi
if [ "$SUCC" != 1 ] && [ "$AGENTS" != na ] && [ "$AGENTS" -gt "$AGENT_MAX" ]; then warn_add "agents=$AGENTS limit=$AGENT_MAX"; fi

[ -z "$WARNS" ] || { echo "WARN resource $WARNS"; exit 0; }
echo "OK disk=${DISK_GIB}GiB swap=${SWAP_MIB}MiB memfree=${MEMFREE}% level=$LEVEL rate=$RATE agents=$AGENTS"
exit 0
