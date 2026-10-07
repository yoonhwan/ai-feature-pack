#!/usr/bin/env bash
# ft-regress-pack.sh add|select|run|retire — C21 닫힌 Issue 회귀 팩 (tests/regression/issue_pack.jsonl).
#   행 = {issue, closed_sha, repro_cmd, expected, files[], mode(press|alt|unit), team, added_at, retired_at}
#   add    --issue N --closed-sha SHA --repro-cmd CMD --expected STR --files a,b --mode M --team T
#   select <기준sha> <후보sha>   후보가 바꾼 파일(git diff --name-only)과 files[] 가 겹치는 활성 행 출력
#   run    <기준sha> <후보sha>   select 결과 중 unit/alt 만 실행(rc 0 AND 출력에 expected 포함 = PASS) · press 는 목록만(오디오 실행은 tester 소관)
#   retire <issue>               retired_at 기록(삭제 아님)
#   env: FT_REGRESS_REPO(기본 cwd 의 git 루트) · FT_REGRESS_PACK(기본 <repo>/tests/regression/issue_pack.jsonl) · FT_REGRESS_PRESS_MAX(기본 20)
#   exit 0 = 정상 · 1 = 거부/FAIL · 2 = usage·환경 오류
set -uo pipefail
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }
REPO="${FT_REGRESS_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] || { echo "git 저장소 아님 (FT_REGRESS_REPO 지정)" >&2; exit 2; }
PACK="${FT_REGRESS_PACK:-$REPO/tests/regression/issue_pack.jsonl}"
PRESS_MAX="${FT_REGRESS_PRESS_MAX:-20}"
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cap_check() {
  [ -f "$PACK" ] || return 0
  local n; n="$(jq -s '[.[] | select(.mode=="press" and .retired_at==null)] | length' "$PACK")"
  if [ "$n" -gt "$PRESS_MAX" ]; then
    echo "WARN press 활성 행 $n > 상한 $PRESS_MAX — 오래된 행부터 retire 필요(삭제 아님)"
  fi
}

cmd_add() {
  local issue="" sha="" repro="" expected="" files="" mode="" team=""
  while [ $# -gt 0 ]; do case "$1" in
    --issue) issue="${2:-}"; shift 2;; --closed-sha) sha="${2:-}"; shift 2;;
    --repro-cmd) repro="${2:-}"; shift 2;; --expected) expected="${2:-}"; shift 2;;
    --files) files="${2:-}"; shift 2;; --mode) mode="${2:-}"; shift 2;;
    --team) team="${2:-}"; shift 2;; *) echo "unknown $1" >&2; usage;;
  esac; done
  case "$issue" in ''|*[!0-9]*) echo "REJECT issue 는 정수여야 한다: '$issue'"; exit 1;; esac
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,40}$' || { echo "REJECT closed_sha 는 7~40자리 소문자 hex: '$sha'"; exit 1; }
  [ -n "$repro" ] || { echo "REJECT repro_cmd 비어 있음"; exit 1; }
  [ -n "$expected" ] || { echo "REJECT expected 비어 있음"; exit 1; }
  [ -n "$files" ] || { echo "REJECT files 비어 있음 (콤마 구분 1개 이상)"; exit 1; }
  case "$mode" in press|alt|unit) ;; *) echo "REJECT mode 는 press|alt|unit: '$mode'"; exit 1;; esac
  [ -n "$team" ] || { echo "REJECT team 비어 있음"; exit 1; }
  if [ -f "$PACK" ] && [ -n "$(jq -c --argjson i "$issue" 'select(.issue==$i)' "$PACK")" ]; then
    echo "REJECT 중복 issue #$issue (retire 된 행 포함 — 이미 팩에 있다)"; exit 1
  fi
  mkdir -p "$(dirname "$PACK")"
  jq -nc --argjson issue "$issue" --arg sha "$sha" --arg repro "$repro" --arg exp "$expected" \
     --arg files "$files" --arg mode "$mode" --arg team "$team" --arg at "$(now)" \
    '{issue:$issue,closed_sha:$sha,repro_cmd:$repro,expected:$exp,files:($files|split(",")|map(select(length>0))),mode:$mode,team:$team,added_at:$at,retired_at:null}' >> "$PACK"
  echo "ADDED #$issue mode=$mode team=$team"
  cap_check
}

# 겹치는 활성 행을 «compact JSON + overlap» 으로 stdout. 실패는 exit 2.
select_rows() {
  local base="${1:-}" cand="${2:-}"
  [ -n "$base" ] && [ -n "$cand" ] || usage
  local changed; changed="$(git -C "$REPO" diff --name-only "$base" "$cand" 2>&1)" \
    || { echo "git diff $base $cand 실패: $changed" >&2; exit 2; }
  [ -f "$PACK" ] || return 0
  jq -c --arg changed "$changed" '($changed|split("\n")|map(select(length>0))) as $c
    | select(.retired_at==null)
    | (.files|map(select(. as $f | $c|index($f)))) as $ov
    | select($ov|length>0) | .overlap=$ov' "$PACK"
}

cmd_select() {
  local rows; rows="$(select_rows "$@")" || exit $?
  if [ -z "$rows" ]; then echo "NONE 겹치는 활성 행 없음"; else
    jq -r '"#\(.issue)\t\(.mode)\t\(.closed_sha)\t\(.team)\toverlap=\(.overlap|join(","))"' <<<"$rows"
  fi
  cap_check
}

cmd_run() {
  local rows; rows="$(select_rows "$@")" || exit $?
  [ -n "$rows" ] || { echo "NONE 겹치는 활성 행 없음 — 실행할 것 없음"; cap_check; return 0; }
  local pass=0 fail=0 listed=0 row issue mode repro expected out rc
  while IFS= read -r row <&3; do
    issue="$(jq -r .issue <<<"$row")"; mode="$(jq -r .mode <<<"$row")"
    if [ "$mode" = "press" ]; then
      echo "LIST press #$issue (실행 안 함 — tester 묶음 소관) overlap=$(jq -r '.overlap|join(",")' <<<"$row")"; listed=$((listed+1)); continue
    fi
    repro="$(jq -r .repro_cmd <<<"$row")"; expected="$(jq -r .expected <<<"$row")"
    out="$(cd "$REPO" && bash -c "$repro" 2>&1 </dev/null)"; rc=$?
    if [ $rc -eq 0 ] && printf '%s' "$out" | grep -qF -- "$expected"; then
      echo "PASS $mode #$issue"; pass=$((pass+1))
    else
      echo "FAIL $mode #$issue rc=$rc expected='$expected' out=$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"; fail=$((fail+1))
    fi
  done 3<<<"$rows"
  echo "RESULT pass=$pass fail=$fail press_listed=$listed"
  cap_check
  [ "$fail" -eq 0 ]
}

cmd_retire() {
  local issue="${1:-}"
  case "$issue" in ''|*[!0-9]*) usage;; esac
  [ -f "$PACK" ] || { echo "REJECT 팩 파일 없음"; exit 1; }
  local cur; cur="$(jq -c --argjson i "$issue" 'select(.issue==$i)' "$PACK")"
  [ -n "$cur" ] || { echo "REJECT #$issue 행 없음"; exit 1; }
  [ "$(jq -r .retired_at <<<"$cur")" = "null" ] || { echo "REJECT #$issue 이미 retire 됨"; exit 1; }
  local tmp; tmp="$(mktemp)"
  jq -c --argjson i "$issue" --arg at "$(now)" 'if .issue==$i then .retired_at=$at else . end' "$PACK" > "$tmp" \
    && mv "$tmp" "$PACK" && echo "RETIRED #$issue"
}

sub="${1:-}"; shift || true
case "$sub" in add) cmd_add "$@";; select) cmd_select "$@";; run) cmd_run "$@";; retire) cmd_retire "$@";; *) usage;; esac
