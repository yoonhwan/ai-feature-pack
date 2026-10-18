#!/usr/bin/env bash
# ft-verdict.sh — 판정 번호 원장 (루트 단일 물리 파일 · 단일 호스트 발급) (판정 421 설계 §2-1 · N1).
#
# 왜 있나: planner 의 «판정 N» 번호가 대화·BOARD 문장 안에만 있어 승계 때 구 좌석과 후계가 같은 번호를 두 번 냈다(408·410).
#   번호의 유일한 권위 = <FT_ROOT>/.fable-team/state/verdicts.jsonl 한 파일. 이 도구만이 쓴다.
#
# 사용:
#   ft-verdict.sh seed <n> --by <좌석>                      첫 줄 기준값(legacy 마지막 번호). 이미 있으면 rc 1
#   ft-verdict.sh new --title "<한 줄>" --teams a,b [--seq 62xxx,…] [--oppa-todo "<한 줄>"]   → 새 번호를 stdout
#   ft-verdict.sh done <n> [--note "<한 줄>"]               같은 번호의 상태만 갱신(새 번호 0)
#   ft-verdict.sh todo <n> --oppa-todo "<한 줄>" | --clear
#   ft-verdict.sh list [--today] [--json]                   n 으로 fold (state open/done · oppa_todo 최신)
#
# 발급 권위: seed·new 는 hostname == 명부 seats-planner.json 의 _verdict_host ∧ realpath(FT_ROOT) == realpath(_verdict_root) 일 때만.
#   (hostname 은 env FT_VERDICT_HOSTNAME 으로 주입 가능 — 시험용)
# 번호 = lock 안에서 max(seed, new 의 n)+1 → append → fsync. seed 가 없으면 new 거부.
# 잠금 = mkdir verdicts.lock + 보유 pid 기록 · 죽은 pid 는 회수 (함수는 ft-verdict-lock.sh — 같은 디렉터리, source).
# 실패는 전부 raise(rc≠0) — 손상 줄(JSON 아닌 줄)은 줄 번호와 함께 rc 1, 건너뛰지 않는다.
set -uo pipefail

die() { echo "REJECT $*" >&2; exit "${2:-1}"; }

ROOT_DEFAULT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
FT_ROOT="${FT_ROOT:-$ROOT_DEFAULT}"
[ -n "$FT_ROOT" ] || die "FT_ROOT 를 알 수 없다 — env FT_ROOT 지정" 2
SEATS="${FT_SEATS:-$FT_ROOT/.fable-team/seats-planner.json}"
STATE="$FT_ROOT/.fable-team/state"
LEDGER="$STATE/verdicts.jsonl"
LOCK="$STATE/verdicts.lock"

CMD="${1:-}"; [ $# -gt 0 ] && shift
usage() { die "usage: $0 seed <n> --by <좌석> | new --title <t> --teams a,b [--seq 1,2] [--oppa-todo <t>] | done <n> [--note <t>] | todo <n> --oppa-todo <t>|--clear | list [--today] [--json]" 2; }

is_int() { case "$1" in ''|*[!0-9]*) return 1;; *) [ "$1" -gt 0 ];; esac; }

authority_check() {
  [ -f "$SEATS" ] || die "명부 없음: $SEATS"
  local host root my_host my_root
  host="$(jq -r '._verdict_host // empty' "$SEATS" 2>/dev/null)" || die "명부 JSON 읽기 실패: $SEATS"
  root="$(jq -r '._verdict_root // empty' "$SEATS" 2>/dev/null)"
  [ -n "$host" ] && [ -n "$root" ] || die "명부에 _verdict_host/_verdict_root 없음 — 발급 권위 미설정 ($SEATS)"
  my_host="${FT_VERDICT_HOSTNAME:-$(hostname)}"
  my_root="$(cd -- "$FT_ROOT" 2>/dev/null && pwd -P)" || die "FT_ROOT 열 수 없음: $FT_ROOT"
  root="$(cd -- "$root" 2>/dev/null && pwd -P)" || die "_verdict_root 열 수 없음"
  [ "$my_host" = "$host" ] || die "발급은 $host planner 에게 — 이 머신($my_host)은 발급 권위 아님"
  [ "$my_root" = "$root" ] || die "발급은 $root 에서만 — 이 루트($my_root)는 발급 권위 아님(워크트리·사본 발급 0)"
}

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=ft-verdict-lock.sh
source "$HERE/ft-verdict-lock.sh" || die "잠금 모듈 로드 실패: $HERE/ft-verdict-lock.sh"

# 모든 줄이 JSON 객체인지 — 아니면 줄 번호와 함께 rc 1
validate_ledger() {
  [ -f "$LEDGER" ] || return 0
  local bad
  bad="$(jq -Rrn 'foreach inputs as $l (0; .+1; . as $i | ($l | try (fromjson | type) catch "BAD") | select(. != "object") | $i)' "$LEDGER" 2>&1 | head -1)"
  [ -z "$bad" ] || die "원장 손상 — ${LEDGER} 줄 $bad 가 JSON 객체가 아니다(건너뛰지 않는다)"
}

append_event() {  # <json 한 줄> — append + fsync
  python3 - "$LEDGER" "$1" <<'PY' || die "원장 쓰기 실패: $LEDGER"
import os, sys
path, line = sys.argv[1], sys.argv[2]
fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
try:
    os.write(fd, (line + "\n").encode("utf-8"))
    os.fsync(fd)
finally:
    os.close(fd)
PY
}

now() { date +%Y-%m-%dT%H:%M:%S; }
has_seed() { [ -f "$LEDGER" ] && jq -e 'select(.ev=="seed")' "$LEDGER" >/dev/null 2>&1; }
has_new() { [ -f "$LEDGER" ] && jq -e --argjson n "$1" 'select(.ev=="new" and .n==$n)' "$LEDGER" >/dev/null 2>&1; }

csv_json() { jq -cn --arg s "$1" '$s | split(",") | map(gsub("^ +| +$";"")) | map(select(length>0))'; }

cmd_seed() {
  local n="${1:-}" by=""; [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in --by) by="${2:-}"; shift 2;; *) die "알 수 없는 옵션: $1" 2;; esac
  done
  is_int "$n" || usage
  [ -n "$by" ] || die "--by <좌석> 필요" 2
  authority_check; acquire_lock; validate_ledger
  has_seed && die "seed 가 이미 있다 — 기준값은 한 번만"
  [ -f "$LEDGER" ] && [ -s "$LEDGER" ] && die "원장에 이미 사건이 있다 — seed 는 첫 줄이어야 한다"
  append_event "$(jq -cn --argjson n "$n" --arg ts "$(now)" --arg by "$by" '{ev:"seed",n:$n,ts:$ts,by:$by}')"
  echo "SEEDED n=$n by=$by"
}

cmd_new() {
  local title="" teams="" seqs="" todo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift 2;;
      --teams) teams="${2:-}"; shift 2;;
      --seq) seqs="${2:-}"; shift 2;;
      --oppa-todo) todo="${2:-}"; shift 2;;
      *) die "알 수 없는 옵션: $1" 2;;
    esac
  done
  [ -n "$title" ] && [ -n "$teams" ] || usage
  local teams_j seq_j
  teams_j="$(csv_json "$teams")"; seq_j="$(csv_json "$seqs")"
  [ "$teams_j" != "[]" ] || die "--teams 가 비었다" 2
  printf '%s' "$seq_j" | jq -e 'all(.[]; test("^[0-9]+$"))' >/dev/null || die "--seq 는 숫자 목록(62xxx,…)" 2
  seq_j="$(printf '%s' "$seq_j" | jq -c 'map(tonumber)')"
  authority_check; acquire_lock; validate_ledger
  has_seed || die "seed 없음 — 발급 불가(planner 검증 마지막 번호로 ft-verdict.sh seed 먼저)"
  local last n
  last="$(jq -rs '[.[] | select(.ev=="seed" or .ev=="new") | .n] | max' "$LEDGER")" || die "원장 읽기 실패"
  n=$((last+1))
  append_event "$(jq -cn --argjson n "$n" --arg ts "$(now)" --arg title "$title" --argjson teams "$teams_j" --argjson seq "$seq_j" --arg todo "$todo" \
    '{ev:"new",n:$n,ts:$ts,title:$title,teams:$teams,seq_out:$seq,oppa_todo:$todo}')"
  echo "$n"
}

cmd_done() {
  local n="${1:-}" note=""; [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in --note) note="${2:-}"; shift 2;; *) die "알 수 없는 옵션: $1" 2;; esac
  done
  is_int "$n" || usage
  acquire_lock; validate_ledger
  has_new "$n" || die "판정 $n 없음 — done 은 새 번호를 만들지 않는다"
  append_event "$(jq -cn --argjson n "$n" --arg ts "$(now)" --arg note "$note" '{ev:"done",n:$n,ts:$ts,note:$note}')"
  echo "DONE n=$n"
}

cmd_todo() {
  local n="${1:-}" todo="" clear=0 have=0; [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --oppa-todo) todo="${2:-}"; have=1; shift 2;;
      --clear) clear=1; shift;;
      *) die "알 수 없는 옵션: $1" 2;;
    esac
  done
  is_int "$n" || usage
  { [ "$clear" = 1 ] && [ "$have" = 0 ]; } || { [ "$have" = 1 ] && [ "$clear" = 0 ] && [ -n "$todo" ]; } || die "todo 는 --oppa-todo \"<한 줄>\" 또는 --clear 중 정확히 하나" 2
  acquire_lock; validate_ledger
  has_new "$n" || die "판정 $n 없음 — todo 는 새 번호를 만들지 않는다"
  append_event "$(jq -cn --argjson n "$n" --arg ts "$(now)" --arg todo "$todo" '{ev:"todo",n:$n,ts:$ts,oppa_todo:$todo}')"
  echo "TODO n=$n"
}

cmd_list() {
  local today=0 json=0
  while [ $# -gt 0 ]; do
    case "$1" in --today) today=1; shift;; --json) json=1; shift;; *) die "알 수 없는 옵션: $1" 2;; esac
  done
  acquire_lock; validate_ledger
  local folded
  if [ -f "$LEDGER" ]; then
    folded="$(jq -s --arg today "$(date +%F)" --argjson only_today "$today" '
      [ .[] | select(.ev=="new" or .ev=="done" or .ev=="todo") ]
      | group_by(.n)
      | map( (map(select(.ev=="new")) | first) as $new
             | select($new != null)
             | { n: $new.n, ts: $new.ts, title: $new.title, teams: $new.teams, seq_out: $new.seq_out,
                 state: (if any(.[]; .ev=="done") then "done" else "open" end),
                 oppa_todo: ( ([ .[] | select(.ev=="new" or .ev=="todo") ] | last).oppa_todo ),
                 note: ( ([ .[] | select(.ev=="done") ] | last | .note) // "" ) } )
      | map(select($only_today==0 or (.ts | startswith($today))))
      | sort_by(.n)' "$LEDGER")" || die "원장 fold 실패"
  else
    folded="[]"
  fi
  if [ "$json" = 1 ]; then printf '%s\n' "$folded"
  else printf '%s' "$folded" | jq -r '.[] | "\(.n) | \(.state) | \(.title) | \(.teams | join(",")) | \(.oppa_todo)"'
  fi
}

case "$CMD" in
  seed) cmd_seed "$@";;
  new)  cmd_new "$@";;
  done) cmd_done "$@";;
  todo) cmd_todo "$@";;
  list) cmd_list "$@";;
  *) usage;;
esac
