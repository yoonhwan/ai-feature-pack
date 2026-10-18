#!/usr/bin/env bash
# ft-autonomy-start.sh — 자율 «켜기» 보조 (r-autonomy-night-preflight · #1406 · 판정 1355·1359) — ft-autonomy.sh on 이 부른다
#   preflight   켜기 «전» 인증 사전 점검 — gcloud 사용자 계정 · ADC 각 7초 + 재시도 1회(판정 666 · ft-proxy-decide.sh 의 bounded 꼴)
#               PASS <항목> / FAIL <항목> — 지금 사람 손: <명령> / 끝줄 «사람 손 필요 N건». ★점검 실패는 켜기를 막지 않는다(오빠가 보고 판단)★
#               토큰 값은 버린다(성공 여부만). gcloud 없음 = FAIL (조용한 생략 0 · #0 RULE). 항상 rc 0.
#   ledger <A<N>>  켜기 «뒤» 시작 장부 1장 — $PLANNER/AUTONOMY-START-A<N>.md: ⓐ진행 중 카드(design/*/indices/진행) ⓑ할 일 =
#               열린 Issue(priority:p0|p1|p2 · gh 7초+재시도 1) → 우선순위 없는 대기 카드(design/*/indices/대기) · 카드는 머리 1줄만
#               gh 실패·초과·없음 = 그 절에 «Issue 목록 못 읽음: <원인>» 1줄(조용한 생략 0 · 켜기는 안 막음). 장부 쓰기 실패 = stderr ERROR + rc 1.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(cd "$HERE/../.." && pwd)}"
PLANNER="${FT_PLANNER_DIR:-$ROOT/design/planner}"
CALL_TIMEOUT_S=7; CALL_RETRIES=1
[[ "${FT_CALL_TIMEOUT_S:-}" =~ ^[1-7]$ ]] && CALL_TIMEOUT_S="$FT_CALL_TIMEOUT_S"   # 시험용 — 줄이기만 된다(7 초과는 무시)

_bd_tree() {  # $1 와 그 자손 pid 를 한 줄씩 (자손 먼저 모으고 부모는 뒤)
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do _bd_tree "$c"; done
  echo "$1"
}

_bd_stop() {  # TERM → 1초 유예 → KILL (대상과 그 자손) → 그 뒤에만 wait — 반환 뒤 자식 0 · 늦은 쓰기 0 (R135a _secret_stop 꼴)
  local pids p
  pids="$(_bd_tree "$1")"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$1" 2>/dev/null || break
    sleep 0.1
  done
  for p in $pids; do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  { wait "$1"; } 2>/dev/null
}

# <명령…> → rc 0 이면 성공 · 마감은 «벽시계» 타이머(sleep 틱 세기 아님 — 부하로 늘어지지 않는다) · 출력은 $BOUND_OUT(기본 폐기)
# 시간 초과(타이머 만료 뒤 rc0 포함 — 늦은 성공 채택 0) = 계보 TERM→1초→KILL 후 재시도 CALL_RETRIES회 · 시도당 반환 ≤ 한도+1초
bounded() {
  local try=0 pid timer rc hit
  while [ "$try" -le "$CALL_RETRIES" ]; do
    try=$((try+1)); hit=0
    "$@" >"${BOUND_OUT:-/dev/null}" 2>/dev/null & pid=$!
    sleep "$CALL_TIMEOUT_S" & timer=$!
    while kill -0 "$pid" 2>/dev/null; do
      if ! kill -0 "$timer" 2>/dev/null; then hit=1; _bd_stop "$pid"; break; fi
      sleep 0.1
    done
    if [ "$hit" = 0 ]; then
      if kill -0 "$timer" 2>/dev/null; then kill "$timer" 2>/dev/null; else hit=1; fi   # 대상 종료와 타이머 만료가 같은 틱이면 시간 초과
      { wait "$timer"; } 2>/dev/null
    else
      { wait "$timer"; } 2>/dev/null
    fi
    [ "$hit" = 1 ] && { { wait "$pid"; } 2>/dev/null; continue; }
    { wait "$pid"; } 2>/dev/null; rc=$?
    [ "$rc" = 0 ] && return 0
  done
  return 1
}

check_one() {  # <항목 이름> <사람 손 명령> <gcloud 인자…> → PASS/FAIL 1줄 · FAIL 이면 rc 1
  local name="$1" hand="$2"; shift 2
  if bounded gcloud "$@"; then echo "PASS $name"; return 0; fi
  echo "FAIL $name — 지금 사람 손: $hand"; return 1
}

cmd_preflight() {
  local bad=0
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "FAIL gcloud 없음 — 지금 사람 손: gcloud 설치 후 gcloud auth login"
    echo "사람 손 필요 1건"; return 0
  fi
  check_one "gcloud 사용자 계정" "gcloud auth login" auth print-access-token || bad=$((bad+1))
  check_one "gcloud ADC" "gcloud auth application-default login" auth application-default print-access-token || bad=$((bad+1))
  echo "사람 손 필요 ${bad}건"
}

cards() {  # <진행|대기> → «- [팀] 카드 머리 1줄» (팀 = design/ 아래 폴더 이름)
  local f team
  shopt -s nullglob
  for f in "$ROOT"/design/*/indices/"$1"/*.md "$ROOT"/design/teams/*/indices/"$1"/*.md; do   # R382: design/teams/<팀>/ 꼴도 센다
    team="$(basename "$(dirname "$(dirname "$(dirname "$f")")")")"
    printf -- '- [%s] %s\n' "$team" "$(head -n 1 "$f" | sed 's/^# *//')"
  done
}

issues() {  # → p0→p1→p2 순 «- #N [팀] 제목» (팀 = team:* 라벨, 없으면 -) · 못 읽으면 rc 1 + 원인을 stdout 에
  local tmp; tmp="$(mktemp)" || { echo "임시 파일 실패"; return 1; }
  command -v gh >/dev/null 2>&1 || { rm -f "$tmp"; echo "gh 없음"; return 1; }
  command -v python3 >/dev/null 2>&1 || { rm -f "$tmp"; echo "python3 없음"; return 1; }
  if ! BOUND_OUT="$tmp" bounded gh issue list --state open --json number,title,labels --limit 200; then
    rm -f "$tmp"; echo "gh 호출 실패 또는 ${CALL_TIMEOUT_S}초 초과(재시도 ${CALL_RETRIES}회 뒤)"; return 1
  fi
  python3 -I - "$tmp" <<'PY' || { rm -f "$tmp"; echo "JSON 해석 실패"; return 1; }
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
for pr in ("p0", "p1", "p2"):
    for r in sorted(rows, key=lambda r: r["number"]):
        names = [l["name"] for l in r["labels"]]
        if "priority:" + pr in names:
            team = next((n[5:] for n in names if n.startswith("team:")), "-")
            print("- #%d [%s] %s · %s" % (r["number"], team, r["title"], pr))
PY
  rm -f "$tmp"
}

cmd_ledger() {  # <A<N>>
  local ev="${1:-}" out="$PLANNER/AUTONOMY-START-${1:-}.md" body iss lines
  [ -n "$ev" ] || { echo "ERROR ledger 에는 사건 번호(A<N>) 필요" >&2; return 1; }
  iss="$(issues)"; lines=$?
  body="$(printf '# 자율 시작 장부 %s — %s\n\n## ⓐ 진행 중 (design/*/indices/진행)\n%s\n\n## ⓑ 할 일 — 순서: 진행 중 → p0 → p1 → p2 → 우선순위 없는 대기 카드\n### 열린 Issue (p0 → p1 → p2)\n' \
    "$ev" "$(date '+%Y-%m-%d %H:%M')" "$(cards 진행)")"
  if [ "$lines" = 0 ]; then body="$body$iss"; else body="$body- Issue 목록 못 읽음: $iss"; fi
  body="$body
### 대기 카드 (우선순위 없음 · design/*/indices/대기)
$(cards 대기)"
  mkdir -p "$PLANNER" && printf '%s\n' "$body" > "$out" || { echo "ERROR 시작 장부 쓰기 실패: $out" >&2; return 1; }
  echo "시작 장부 $out"
}

case "${1:-}" in
  preflight) cmd_preflight ;;
  ledger) cmd_ledger "${2:-}" ;;
  *) echo "usage: ft-autonomy-start.sh preflight|ledger <A<N>>" >&2; exit 2 ;;
esac
