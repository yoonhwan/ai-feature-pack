#!/usr/bin/env bash
# ft-unpushed-summary.sh — 워크트리마다 «push 안 된 로컬 커밋 N» 을 하루 1통 master 에 (r963)
#   왜: 장수 가지에 push 안 된 커밋이 수천 개 디스크 한 곳에만 쌓였는데 아무도 세지 않는다(r963 실측: 5073).
#   ★원격에 묻지 않는다★ — 각 워크트리 가지의 «로컬 추적 ref»(refs/remotes/origin/<가지>)만 본다. ls-remote·fetch·@{upstream} 0.
#     로컬 추적 ref 있음 = `rev-list --count refs/remotes/origin/<가지>..HEAD` · 없음 = `<base>..HEAD` 를 «원격 가지 없음 · main 에 없는 커밋» 으로.
#     HEAD 분리 워크트리 = 셈 0 · «HEAD 분리 M곳» 에만 센다. 문턱(기본 50) 미만은 뺀다.
#   ★표식은 «한 바퀴를 다 본 날» 만★ — <state>/<YYYY-MM-DD>.done. 한 워크트리라도 시간 초과·실패면 표식 0 + ERROR 1줄(다음 틱 재시도 · «문제없음» 발신 0).
#   본문 고정 꼴: «미push N곳 · HEAD 분리 M곳 · 상위 3곳 = 이름(커밋 수) … · 전체 = unpushed/<날짜>.txt»
#     이름 = 워크트리 «바닥 이름»(60자 자름) — 루트 경로 길이와 무관 · 본문 ≤ FT_UNPUSHED_BODY_MAX(700).
#   잠금: <state>/lock(mkdir) — ★trap 을 잠금 «직후» 에 건다★(로그 쓰기보다 먼저 — 로그 경로가 디렉터리여도 잔류 0). 2시간 넘은 잠금 = 죽은 실행.
#   env: FT_UNPUSHED_MIN(50) · FT_UNPUSHED_TOP(3) · FT_UNPUSHED_BODY_MAX(700) · FT_UNPUSHED_DEADLINE(70) · FT_UNPUSHED_CALL_MAX(7)
#        FT_UNPUSHED_STATE_DIR(<루트>/.fable-team/state/unpushed) · FT_UNPUSHED_BASE(origin/main) · FT_UNPUSHED_SEATS · FT_TICK_MBOX
#        FT_UNPUSHED_LOG(요약 1줄 append · 실패해도 표식은 산다) · FT_UNPUSHED_NOW(YYYY-MM-DD · 시험용) · FT_UNPUSHED_DRY=1(출력만)
#   exit 0 = 정상(보냈거나 오늘 이미 했거나 보낼 것 0) · 2 = usage · 4 = 루트·목록·저장·명부·미완주 · 5 = mbox 발신 실패
set -uo pipefail
REPO=""; DRY="${FT_UNPUSHED_DRY:-0}"
MIN="${FT_UNPUSHED_MIN:-50}"; TOP="${FT_UNPUSHED_TOP:-3}"
MAXC="${FT_UNPUSHED_BODY_MAX:-700}"; DEADLINE="${FT_UNPUSHED_DEADLINE:-70}"; CALL_MAX="${FT_UNPUSHED_CALL_MAX:-7}"
usage() { echo "usage: $0 [--repo DIR] [--dry-run]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;; --dry-run) DRY=1; shift;; *) usage;; esac; done
case "$MIN" in ''|*[!0-9]*) echo "WARN FT_UNPUSHED_MIN=$MIN 는 양의 정수가 아니다 → 50" >&2; MIN=50;; esac
err() { echo "$*" >&2; }
[ -n "$REPO" ] || REPO="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
ROOT="${FT_ROOT:-$(git -C "${REPO:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || { err "ERROR 루트를 못 찾음(REPO=${REPO:-<빈>}) — 표식 0 · 발신 0"; exit 4; }
BASE="${FT_UNPUSHED_BASE:-origin/main}"
STATE="${FT_UNPUSHED_STATE_DIR:-$ROOT/.fable-team/state/unpushed}"
TODAY="${FT_UNPUSHED_NOW:-$(date +%F)}"
MARK="$STATE/$TODAY.done"; FULL="$STATE/$TODAY.txt"; LOCK="$STATE/lock"
LOGF="${FT_UNPUSHED_LOG:-}"
TB="$(command -v timeout || command -v gtimeout)"
[ -n "$TB" ] || { err "ERROR timeout/gtimeout 없음 — 시간 상한을 못 걸어 실행 거절"; exit 4; }
note() { [ -n "$LOGF" ] || return 0; printf '%s\n' "$*" >> "$LOGF" 2>/dev/null || err "WARN 로그 쓰기 실패(잠금·표식과 분리): $LOGF"; }
if [ "$DRY" != 1 ]; then
  [ ! -e "$MARK" ] || { note "SKIP 오늘($TODAY) 이미 했다: $MARK"; exit 0; }
  mkdir -p "$STATE" 2>/dev/null || { err "ERROR 상태 폴더 못 만듦: $STATE — 표식 0 · 발신 0"; exit 4; }
  if [ -d "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    [ "$age" -gt 7200 ] && rm -rf "$LOCK"
  fi
  mkdir "$LOCK" 2>/dev/null || { note "SKIP 다른 실행 중: $LOCK"; exit 0; }
  trap 'rm -rf "$LOCK"' EXIT   # ★잠금 직후★ — 아래 어떤 실패(로그 쓰기 포함)에도 잔류 0
fi
START="$(date +%s)"
left_s() { echo $(( DEADLINE - ( $(date +%s) - START ) )); }
gq() {  # gq <git 인자…> — 남은 예산으로 상한을 줄인 git 한 번(원격 접촉 인자 0)
  local left; left="$(left_s)"; [ "$left" -gt "$CALL_MAX" ] && left="$CALL_MAX"; [ "$left" -lt 1 ] && left=1
  "$TB" "$left" git -c gc.auto=0 "$@"
}
bad=0; badwhy=""
markbad() { bad=$((bad+1)); [ -n "$badwhy" ] || badwhy="$*"; }
fail_round() {  # ★r963 계약 ② — 덜 본 날은 표식 0 + ERROR 1줄★(빈 목록·«문턱 넘는 곳 없음» 으로 «문제없음» 을 만들지 않는다)
  err "ERROR r963 미완주 — ${bad}곳 확인 못 함(예: ${badwhy:-모름}) — 표식 0 · 발신 0(다음 틱 재시도)"
  exit 4
}
name_of() { local b; b="$(basename "$1")"; printf '%s' "${b:0:60}"; }  # ★바닥 이름 60자★ — 루트 경로가 728자여도 본문은 그대로
wlist="$(gq -C "$REPO" worktree list --porcelain 2>/dev/null)"; wrc=$?
[ "$wrc" = 0 ] && [ -n "$wlist" ] || { markbad "worktree list rc=$wrc"; fail_round; }
lines=(); detached=0; nosub=0
while IFS=$'\t' read -r p br; do
  [ -n "${p:-}" ] || continue
  if [ "$(left_s)" -lt 1 ]; then markbad "마감 초과(남은 예산 0)"; break; fi
  case "$br" in
    HEAD) detached=$((detached + 1)); continue;;            # HEAD 분리 = 셈 0·«HEAD 분리 M곳» 에만 센다
    '') markbad "$(name_of "$p") 가지 이름 빈 값"; continue;;
  esac
  if [ -d "$p" ]; then HEADREF=HEAD; G="-C $p"; else HEADREF="refs/heads/$br"; G="-C $REPO"; fi   # 폴더가 사라진 등록은 공용 repo 의 가지 ref 로 센다
  if gq -C "$REPO" rev-parse --verify -q "refs/remotes/origin/$br" >/dev/null 2>&1; then
    kind="로컬 추적 ref"
    # shellcheck disable=SC2086
    n="$(gq $G rev-list --count "refs/remotes/origin/$br..$HEADREF" 2>/dev/null)"
  else
    kind="원격 가지 없음 · main 에 없는 커밋"
    # shellcheck disable=SC2086
    n="$(gq $G rev-list --count "${BASE}..$HEADREF" 2>/dev/null)"
  fi
  case "$n" in ''|*[!0-9]*) [ -d "$p" ] && { markbad "$(name_of "$p") rev-list 실패"; continue; }; nosub=$((nosub + 1)); continue;; esac
  [ "$DRY" = 1 ] && err "LIST $(name_of "$p") · $br · $kind=$n"
  [ "$n" -ge "$MIN" ] && lines+=("$n"$'\t'"$(name_of "$p")")
done <<< "$(printf '%s\n' "$wlist" | awk '/^worktree /{p=substr($0,10)} /^branch refs\/heads\//{print p"\t"substr($0,19)} /^detached/{print p"\tHEAD"}')"
[ "$nosub" = 0 ] || err "WARN 이미 사라진 등록 $nosub곳(폴더·가지 ref 없음 · 셈 밖 — git worktree prune 대상)"
[ "$(left_s)" -lt 0 ] && markbad "마감 초과(반복 끝)"
[ "$bad" = 0 ] || fail_round
total="${#lines[@]}"
sorted=""; [ "$total" = 0 ] || sorted="$(printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1nr | cut -f2-)"
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
echo "$body"
[ "$DRY" = 1 ] && exit 0
{ printf '%s\n' "[r963 push 안 된 로컬 커밋 $TODAY · 문턱 $MIN · 로컬 ref 만(원격 접촉 0)]"
  [ "$total" = 0 ] || printf '%s\n' "${lines[@]}" | sort -t$'\t' -k1,1nr | awk -F'\t' '{printf "%s\t%s\n", $2, $1}'
  echo "되돌림 = 그 가지 주인이 push(가지 병합·main 이동은 소유자 + 오빠 승인)"; } > "$FULL" 2>/dev/null \
  || { err "ERROR 전체 목록 저장 실패: $FULL — 표식 0 · 발신 0(다음 틱 재시도)"; exit 4; }
SEATS="${FT_UNPUSHED_SEATS:-$ROOT/.fable-team/seats-harness.json}"; [ -f "$SEATS" ] || SEATS="$ROOT/.fable-team/seats.json"
MASTER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("_master") or "")' "$SEATS" 2>/dev/null)"
[ -n "$MASTER" ] || { err "ERROR 명부에서 _master 를 못 읽음: $SEATS — 표식 0 · 발신 0"; exit 4; }
MBOX="${FT_TICK_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
[ -f "$MBOX" ] || { err "ERROR mbox 없음: $MBOX — 표식 0 · 발신 0"; exit 4; }
bash "$MBOX" send "$MASTER" ft-unpushed-summary "$body" >/dev/null 2>&1 \
  || { err "ERROR mbox 발신 실패(to=$MASTER) — 표식 0(다음 틱 재시도)"; exit 5; }
: > "$MARK" 2>/dev/null || { err "ERROR 표식 못 씀: $MARK — 다음 틱 재발신 위험"; exit 4; }
note "SENT to=$MASTER · 표식 $MARK · 전체 $FULL(${total}곳 · HEAD 분리 ${detached}곳)"
exit 0
