# shellcheck shell=bash
# ft-secret-lib.sh — 비밀 조회 래퍼 secret() (R135a · loom 사고 2026-10-13 처방 3). 계획·진단 스크립트에서 source 해서 쓴다.
# ★반드시  X="$(secret <시크릿 이름> [계정])" || exit 1  로만 부른다★ — 맨 호출·파이프는 값이 화면으로 나온다(secret-output-guard 훅이 거절한다).
# 확인은 ${#X}·[ -n "$X" ] 만, 쓴 뒤 unset X. stdout = 값 · stderr = 실패 이유(120자, 값 아님) · 빈 값·실패·시간 초과 = rc 1.
# 외부 호출 7초 룰(전역 하드 룰 12): gcloud 1회 7초 + 재시도 1회, 시도 1회 반환 ≤ 8초(TERM → 1초 유예 → KILL, gcloud 와 자식 포함), 총 마감 16초(70초 천장 안). FT_SECRET_TIMEOUT_S 는 줄이기만 된다(7 초과는 7).
# 환경: FT_SECRET_PROJECT(기본 byz-agents-484214) · FT_SECRET_ACCOUNT(기본 없음 · 둘째 인자가 우선)

_secret_tree() {  # $1 와 그 자손 pid 를 한 줄씩 (자손 먼저 모으고 부모는 뒤)
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do _secret_tree "$c"; done
  echo "$1"
}

_secret_stop() {  # TERM → 1초 유예 → KILL (대상은 gcloud 와 그 자식) → 그 뒤에만 wait
  local pids p
  pids="$(_secret_tree "$1")"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$1" 2>/dev/null || break
    sleep 0.1
  done
  for p in $pids; do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  { wait "$1"; } 2>/dev/null
}

_secret_attempt() {  # $1=시크릿 $2=계정 $3=값 파일 $4=오류 파일 → rc 0 성공 · 124 시간 초과 · 그 외 gcloud 실패 (반환 ≤ limit+1초)
  local pid timer limit="${FT_SECRET_TIMEOUT_S:-7}" rc
  [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -ge 1 ] && [ "$limit" -le 7 ] || limit=7
  gcloud secrets versions access latest --secret="$1" --project="${FT_SECRET_PROJECT:-byz-agents-484214}" ${2:+--account="$2"} >"$3" 2>"$4" &
  pid=$!
  sleep "$limit" &  # 벽시계 타이머 — 조회 반복의 sleep 0.1 이 부하로 늘어져도 7초는 7초다
  timer=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ! kill -0 "$timer" 2>/dev/null; then
      { wait "$timer"; } 2>/dev/null
      _secret_stop "$pid"
      echo "시간 초과 ${limit}초" >"$4"; return 124
    fi
    sleep 0.1
  done
  kill "$timer" 2>/dev/null; { wait "$timer"; } 2>/dev/null
  { wait "$pid"; } 2>/dev/null; rc=$?
  return "$rc"
}

secret() {
  local out err val acct="${2:-${FT_SECRET_ACCOUNT:-}}" rc=1
  out="$(mktemp)" || return 1
  err="$(mktemp)" || { rm -f "$out"; return 1; }
  for _ in 1 2; do
    : >"$out"
    _secret_attempt "$1" "$acct" "$out" "$err"; rc=$?
    [ "$rc" != 0 ] || break
  done
  if [ "$rc" != 0 ]; then
    echo "STOP 시크릿 조회 실패: $1 ($(head -c 120 "$err" | tr '\n' ' '))" >&2; rm -f "$out" "$err"; return 1
  fi
  val="$(cat "$out")"; rm -f "$out" "$err"
  [ -n "$val" ] || { echo "STOP 시크릿 비어 있음: $1" >&2; return 1; }
  printf '%s' "$val"
}
