#!/usr/bin/env bash
# ft-unpushed-summary.sh — 워크트리마다 «push 안 된 로컬 커밋 N» 을 하루 1통 master 에 (r963 r1·r2·r3)
#   왜: 장수 가지에 push 안 된 커밋이 수천 개 디스크 한 곳에만 쌓였는데 아무도 세지 않는다(r963 실측: 5073).
#   ★원격에 묻지 않는다★ — 각 워크트리 가지의 «로컬 추적 ref»(refs/remotes/origin/<가지>)만 본다. ls-remote·fetch·@{upstream} 0.
#     로컬 추적 ref 있음 = `rev-list --count refs/remotes/origin/<가지>..HEAD` · 없음 = `<base>..HEAD` 를 «원격 가지 없음 · main 에 없는 커밋» 으로.
#   ★r3 구조 — git 프로세스를 띄우는 줄은 실행기 gq() «1곳뿐»★ (r1·r2 는 호출 자리마다 rc 를 손으로 봤고, 그때마다 새 자리가 샜다: 루트 탐색 정상 출력 + rc128).
#     사용법 gq <허용 rc 집합> <사유> <git 인자…> — rc 가 허용 집합 밖이거나 124(시간 초과)·128(실행 실패)이면 FAILS 에 «사유 rc=N» 을 남기고 빈 값.
#     본문에 «실행기 밖 git » 0 (주석 줄·따옴표 안 문자열 제외 — 시험 ⓐ4 안전망 grep 이 판정).
#   ★표식·발신은 끝 한 곳 finish_round() 에서 «실패 기록 0» 일 때만★ — 실패 ≥1 = 표식 0 + ERROR 1줄(사유 전부) + 발신 본문 «확인 불가 N곳».
#     «덜 본 날» 을 «문턱 넘는 곳 없음»·«문제없음» 으로 접지 않는다. 중간 exit 는 «정상 건너뜀» 2갈래(오늘 이미 함·다른 실행 중)뿐.
#     HEAD 분리 워크트리 = 셈 0 · «HEAD 분리 M곳» 에만 센다. 문턱(기본 50) 미만은 뺀다.
#   표식은 «한 바퀴를 다 본 날» 만 — <state>/<YYYY-MM-DD>.done. 본문 고정 꼴:
#     «미push N곳 · HEAD 분리 M곳 · 상위 3곳 = 이름(커밋 수) … · 전체 = unpushed/<날짜>.txt»
#     이름 = 워크트리 «바닥 이름»(60자 자름) — 루트 경로 길이와 무관 · 본문 ≤ FT_UNPUSHED_BODY_MAX(700).
#   잠금: <state>/lock(mkdir) — ★trap 을 잠금 «직후» 에 건다★(로그 쓰기보다 먼저 — 로그 경로가 디렉터리여도 잔류 0). 2시간 넘은 잠금 = 죽은 실행.
#   ★r1021 호출 묶음★ 워크트리마다 git 을 부르지 않는다 — worktree list 1 + for-each-ref 2 = 3회, 추적 ref 있는 가지만 rev-list 1회.
#     «미push 수» 는 그대로: 추적 ref 있음 = origin/<br>..<br> · 없음 = <base>..<br>(묶음의 ahead 값) · HEAD 분리 = 0 · 폴더별 -C 호출 0.
#   ★r1021 확인 불가 쪽지 = 날짜당 1통★ <state>/<날짜>.failmail 이 있으면 쪽지 0 — ERROR 로그 줄은 회차마다 그대로 남긴다.
#   env: FT_UNPUSHED_MIN(50) · FT_UNPUSHED_TOP(3) · FT_UNPUSHED_BODY_MAX(700) · FT_UNPUSHED_DEADLINE(70) · FT_UNPUSHED_CALL_MAX(7)
#        FT_UNPUSHED_STATE_DIR(<루트>/.fable-team/state/unpushed) · FT_UNPUSHED_BASE(origin/main) · FT_UNPUSHED_SEATS · FT_TICK_MBOX
#        FT_UNPUSHED_LOG(요약 1줄 append · 실패해도 표식은 산다) · FT_UNPUSHED_NOW(YYYY-MM-DD · 시험용) · FT_UNPUSHED_DRY=1(출력만)
#   exit 0 = 정상(보냈거나 오늘 이미 했거나 다른 실행 중) · 2 = usage · 4 = 실패 기록 ≥1(표식 0)
set -uo pipefail
REPO=""; DRY="${FT_UNPUSHED_DRY:-0}"
MIN="${FT_UNPUSHED_MIN:-50}"; TOP="${FT_UNPUSHED_TOP:-3}"
MAXC="${FT_UNPUSHED_BODY_MAX:-700}"; DEADLINE="${FT_UNPUSHED_DEADLINE:-70}"; CALL_MAX="${FT_UNPUSHED_CALL_MAX:-7}"
usage() { echo "usage: $0 [--repo DIR] [--dry-run]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;; --dry-run) DRY=1; shift;; *) usage;; esac; done
case "$MIN" in ''|*[!0-9]*) echo "WARN FT_UNPUSHED_MIN=$MIN 는 양의 정수가 아니다 → 50" >&2; MIN=50;; esac
START="$(date +%s)"; FAILS=(); GQ_RC=0; GQ_OUT=""
err() { echo "$*" >&2; }
left_s() { echo $(( DEADLINE - ( $(date +%s) - START ) )); }
# ★r4 고침 2 — 상한은 r938 의 nf_bound(자손 전부 TERM → 1초 → KILL · 총 ≤ 상한 + 4초)★ 정의 복사 0 — nano-close.sh 의 함수 본문을 그대로 가져온다.
#   재설계서는 «lib 로 옮기고 둘이 source» 를 적었지만, 실측에서 다른 카드 시험 28파일이 ft-nano-close.sh 만 복사해 돌려 35+ 단언이 깨졌다(r4 측정 = lib 없음 ERROR).
#   그래서 «정의는 한 곳(ft-nano-close.sh)» 을 그대로 두고 이 도구가 그 본문을 읽어 쓴다 — 복사 0 · 두 도구가 같은 정의 · 기존 시험 0 변경.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
_NB="$(sed -n '/^nf_bound() {/,/^}$/p' "$HERE/ft-nano-close.sh" 2>/dev/null)"
[ -n "$_NB" ] && eval "$_NB"
declare -F nf_bound >/dev/null || { err "ERROR nf_bound 를 ft-nano-close.sh 에서 못 가져왔다($HERE) — 시간 상한 없이 돌 수 없어 실행 거절"; exit 4; }
command -v python3 >/dev/null 2>&1 || { err "ERROR python3 없음 — 시간 상한을 못 걸어 실행 거절"; exit 4; }
# gq <허용 rc 집합(쉼표)> <사유> <git 인자…> → GQ_OUT·GQ_RC
gq() {  # ★git호출을 띄우는 유일한 자리★
  local allow="$1" why="$2" left out rc hard; shift 2   # ★stdout 이 아니라 GQ_OUT★ — `$(gq)` 는 하위 셸이라 FAILS 기록이 사라진다
  left="$(left_s)"; [ "$left" -gt "$CALL_MAX" ] && left="$CALL_MAX"; [ "$left" -lt 1 ] && left=1
  out="$(nf_bound "$left" git -c gc.auto=0 "$@" 2>/dev/null)"; rc=$?
  GQ_RC="$rc"; GQ_OUT=""
  case "$rc" in 124|128) hard=1;; *) hard=0;; esac
  if [ "$hard" = 0 ]; then case ",$allow," in *",$rc,"*) GQ_OUT="$out"; return 0;; esac; fi
  FAILS+=("$why rc=$rc"); return 1
}
name_of() { local b; b="$(basename "$1")"; printf '%s' "${b:0:60}"; }  # ★바닥 이름 60자★ — 루트 경로가 728자여도 본문은 그대로
# ★r4 고침 1 — 맨 처음 하는 일 = 실행기로 루트 탐색★ 실패(종료값 ≠ 0 · 시간 초과 · 빈 출력)면 «오늘 표식» 유무를 보지 않고 바로 finish_round.
#   r3 반례: 표식 있는 날 재실행이 루트 탐색 **전** 에 exit 0 하면서 루트 탐색 rc128 을 삼켰다.
if [ -z "$REPO" ]; then
  gq 0 "루트 탐색" rev-parse --show-toplevel && REPO="$GQ_OUT"
  [ -n "$REPO" ] || [ "$GQ_RC" != 0 ] || FAILS+=("루트 탐색 빈 출력")   # rc≠0 은 gq 가 이미 기록 — 한 번만 센다
fi
ROOT="${FT_ROOT:-}"
if [ -z "$ROOT" ]; then
  gq 0 "루트 탐색" -C "${REPO:-.}" rev-parse --path-format=absolute --git-common-dir
  ROOT="${GQ_OUT%/.git}"   # ★파이프 대신 셸 치환★ — `| sed` 는 실행기 종료값을 덮는다
  [ -n "$ROOT" ] || [ "$GQ_RC" != 0 ] || FAILS+=("루트 탐색 빈 출력")
fi
ROOT_BASE="${FT_ROOT:-${ROOT:-$REPO}}"
BASE="${FT_UNPUSHED_BASE:-origin/main}"
STATE="${FT_UNPUSHED_STATE_DIR:-$ROOT_BASE/.fable-team/state/unpushed}"
TODAY="${FT_UNPUSHED_NOW:-$(date +%F)}"
MARK="$STATE/$TODAY.done"; FULL="$STATE/$TODAY.txt"; LOCK="$STATE/lock"
LOGF="${FT_UNPUSHED_LOG:-}"
note() { [ -n "$LOGF" ] || return 0; printf '%s\n' "$*" >> "$LOGF" 2>/dev/null || err "WARN 로그 쓰기 실패(잠금·표식과 분리): $LOGF"; }
lines=(); total=0   # r4: 루트 탐색 실패가 finish_round 로 바로 갈 수 있게 미리 초기화
finish_round() {  # ★모든 갈래가 끝나는 «한 곳»★ — 표식·발신은 실패 기록 0 일 때만(계약 ②)
  local why joined=""
  [ "$DRY" = 1 ] || [ "${#FAILS[@]}" != 0 ] || {
    { printf '%s\n' "[r963 push 안 된 로컬 커밋 $TODAY · 문턱 $MIN · 로컬 ref 만(원격 접촉 0)]"
      [ "$total" = 0 ] || printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1nr | awk -F'\t' '{printf "%s\t%s\n", $2, $1}'
      echo "되돌림 = 그 가지 주인이 push(가지 병합·main 이동은 소유자 + 오빠 승인)"; } > "$FULL" 2>/dev/null \
      || FAILS+=("전체 목록 저장 실패 $FULL")
  }
  if [ "$DRY" != 1 ]; then
    SEATS="${FT_UNPUSHED_SEATS:-$ROOT_BASE/.fable-team/seats-harness.json}"; [ -f "$SEATS" ] || SEATS="$ROOT_BASE/.fable-team/seats.json"
    MASTER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("_master") or "")' "$SEATS" 2>/dev/null)"
    [ -n "$MASTER" ] || FAILS+=("명부에서 _master 를 못 읽음 $SEATS")
    MBOX="${FT_TICK_MBOX:-$ROOT_BASE/.fable-team/comm/mbox.sh}"
    [ -f "$MBOX" ] || { FAILS+=("mbox 없음 $MBOX"); MBOX=""; }
    if [ "${#FAILS[@]}" = 0 ]; then
      bash "$MBOX" send "$MASTER" ft-unpushed-summary "$body" >/dev/null 2>&1 || FAILS+=("mbox 발신 실패(to=$MASTER)")
    fi
    if [ "${#FAILS[@]}" = 0 ]; then
      : > "$MARK" 2>/dev/null || FAILS+=("표식 못 씀 $MARK")
      [ "${#FAILS[@]}" = 0 ] && { echo "$body"; note "SENT to=$MASTER · 표식 $MARK · 전체 $FULL(${total}곳 · HEAD 분리 ${detached}곳)"; exit 0; }
    fi
  fi
  if [ "${#FAILS[@]}" = 0 ]; then echo "$body"; exit 0; fi
  for why in "${FAILS[@]}"; do joined="${joined:+$joined; }$why"; done
  err "ERROR r963 미완주 — 확인 불가 ${#FAILS[@]}곳: $joined — 표식 0 · 다음 틱 재시도"
  # ★r1021 — «확인 불가» 쪽지는 날짜당 1통★ ERROR 로그 줄은 회차마다 그대로 남긴다(계약 ④).
  if [ "$DRY" != 1 ] && [ -n "${MBOX:-}" ] && [ -n "${MASTER:-}" ] && [ ! -e "$STATE/$TODAY.failmail" ]; then
    if bash "$MBOX" send "$MASTER" ft-unpushed-summary \
      "확인 불가 ${#FAILS[@]}곳(사유 첫 1: ${FAILS[0]}) — 표식 0 · 다음 틱 재시도" >/dev/null 2>&1; then
      : > "$STATE/$TODAY.failmail" 2>/dev/null
    fi
  fi
  exit 4
}
[ "${#FAILS[@]}" = 0 ] || finish_round   # ★r4 순서 고정 — 루트 탐색 실패 = «오늘 표식» 검사 없이 바로 끝(표식 0 · ERROR 1줄 · 확인 불가 발신)★
if [ "$DRY" != 1 ]; then
  [ ! -e "$MARK" ] || { note "SKIP 오늘($TODAY) 이미 했다: $MARK"; exit 0; }
  if ! mkdir -p "$STATE" 2>/dev/null; then
    FAILS+=("상태 폴더 못 만듦 $STATE")
  elif [ -d "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    [ "$age" -gt 7200 ] && rm -rf "$LOCK"
  fi
  if [ "${#FAILS[@]}" = 0 ]; then
    mkdir "$LOCK" 2>/dev/null || { note "SKIP 다른 실행 중: $LOCK"; exit 0; }
    trap 'rm -rf "$LOCK"' EXIT   # ★잠금 직후★ — 아래 어떤 실패(로그 쓰기 포함)에도 잔류 0
  fi
fi
gq 0 "worktree 목록" -C "${REPO:-.}" worktree list --porcelain; wlist="$GQ_OUT"
# ★r1021 — 워크트리마다 git 을 부르지 않는다★ 가지 ref·추적 ref·«main 에 없는 커밋 수» 는 공용 리포 한 곳에서 묶음 2회로 읽는다.
#   호출 = 3 + (추적 ref 있는 가지 수) · 폴더별 -C 호출 0. 묶음이 실패하면 «덜 봄» 이므로 FAILS 에 남기고 셈하지 않는다(계약 ①·③).
gq 0 "가지 묶음 조회 실패" -C "${REPO:-.}" for-each-ref refs/heads --format="%(refname:lstrip=2)%09%(ahead-behind:$BASE)"; htab="$GQ_OUT"
gq 0 "추적 ref 묶음 조회 실패" -C "${REPO:-.}" for-each-ref refs/remotes/origin --format='%(refname:lstrip=3)'; ttab="$GQ_OUT"
[ "${#FAILS[@]}" = 0 ] || finish_round   # 묶음을 못 읽으면 «덜 봄» — 워크트리를 짚지 않고 바로 끝(가짜 «표에 없음» 을 안 만든다)
lines=(); detached=0; nosub=0
plan="$(printf '%s\n%s\n' \
  "$(printf '%s\n' "$htab" | awk -F'\t' -v OFS='\t' 'NF{print "H",$1,$2}')" \
  "$(printf '%s\n' "$ttab" | awk -v OFS='\t' 'NF{print "T",$1}')" \
  "$(printf '%s\n' "$wlist" | awk -v OFS='\t' '/^worktree /{p=substr($0,10)} /^branch refs\/heads\//{print "W",p,substr($0,19)} /^detached/{print "W",p,"HEAD"}')" \
  | awk -F'\t' -v OFS='\t' '
      $1=="H"{ ah[$2]=$3; has[$2]=1; next }
      $1=="T"{ trk[$2]=1; next }
      $1=="W"{ if($3=="HEAD"){print $2,$3,"detached"; next}
        if($3==""){print $2,$3,"empty"; next}
        if(!($3 in has)){print $2,$3,"noref"; next}
        split(ah[$3],ab," "); print $2,$3,(($3 in trk)?"track":"base"),ab[1] }')"
while IFS=$'\t' read -r p br kind n; do
  [ -n "${p:-}" ] || continue
  if [ "$(left_s)" -lt 1 ]; then FAILS+=("마감 초과(남은 예산 0)"); break; fi
  case "$kind" in
    detached) detached=$((detached + 1)); continue;;            # HEAD 분리 = 셈 0·«HEAD 분리 M곳» 에만 센다
    empty) FAILS+=("$(name_of "$p") 가지 이름 빈 값"); continue;;
    noref) if [ -d "$p" ]; then FAILS+=("$(name_of "$p") 가지 ref 표에 없음"); else nosub=$((nosub + 1)); fi; continue;;
  esac                                                    # 폴더·가지 ref 둘 다 없음 = 사라진 등록(실패 아님)
  if [ "$kind" = track ]; then   # 추적 ref 있음 = 로컬 추적 ref 와 견준다(공용 리포에서 1회)
    kind="로컬 추적 ref"
    gq 0 "$(name_of "$p") rev-list 실패" -C "${REPO:-.}" rev-list --count "refs/remotes/origin/$br..refs/heads/$br" || continue
    n="$GQ_OUT"
  else kind="원격 가지 없음 · main 에 없는 커밋"; fi        # 추적 ref 없음 = 묶음의 ahead 값(=$BASE..$br)
  case "$n" in ''|*[!0-9]*) FAILS+=("$(name_of "$p") rev-list 출력이 숫자가 아님"); continue;; esac
  [ "$DRY" = 1 ] && err "LIST $(name_of "$p") · $br · $kind=$n"
  [ "$n" -ge "$MIN" ] && lines+=("$n"$'\t'"$(name_of "$p")")
done <<< "$plan"
[ "$nosub" = 0 ] || err "WARN 이미 사라진 등록 ${nosub}곳(폴더·가지 ref 없음 · 셈 밖 — git worktree prune 대상)"
[ "$(left_s)" -lt 0 ] && FAILS+=("마감 초과(반복 끝)")
total="${#lines[@]}"
fixed="미push ${total}곳 · HEAD 분리 ${detached}곳"; taily="전체 = unpushed/$TODAY.txt"
blen() { printf '%s' "$1" | wc -c | tr -d ' '; }
if [ "$total" = 0 ]; then
  body="$fixed · 문턱 ${MIN} 넘는 곳 없음 · $taily"
else
  top_list=""; shown=0
  while IFS=$'\t' read -r cn nm; do
    [ -n "${nm:-}" ] || continue
    trial="$fixed · 상위 ${TOP}곳 = $([ -n "$top_list" ] && printf '%s · ' "$top_list")${nm}(${cn}) · $taily"
    [ "$(blen "$trial")" -le "$MAXC" ] || break   # ★고정 꼴 + 길이 상한★(넘으면 이름을 덜 넣는다)
    top_list="$([ -n "$top_list" ] && printf '%s · ' "$top_list")${nm}(${cn})"
    shown=$((shown + 1)); [ "$shown" -ge "$TOP" ] && break
  done <<< "$(printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1nr)"
  body="$fixed · 상위 ${TOP}곳 = ${top_list} · $taily"
fi
finish_round
