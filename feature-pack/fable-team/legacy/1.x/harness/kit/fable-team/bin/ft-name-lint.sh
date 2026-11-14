#!/usr/bin/env bash
# ft-name-lint.sh — tmux 세션명이 P6 문법에 맞는지 검사한다 (C2). 읽기 전용.
#
# 사용: ft-name-lint.sh <세션명>
#   PASS <세션명>            exit 0
#   REJECT <세션명>: <사유>   exit 1 (사유 stdout)   · 인자 오류 exit 2
#
# 문법 (SPEC-session-naming-20261005 §2-A):
#   <프로젝트>-<팀>-<역할>[-<꼬리>]#<N>
#   프로젝트·팀 = [a-z0-9]+ · 역할 = 예약어 12 · 구분자는 '-' 만 · 대문자·'_'·공백 0 · 길이 ≤ 60
#   꼬리 = nano 는 카드 slug(필수, [a-z0-9-]+) · qa 는 에이전트 또는 «범위 1토큰 + 에이전트» · 그 밖의 역할 좌석은 에이전트(claude|codex|opencode|cmd|pi) 필수
#   r1641 석 칸: 역할 좌석 꼬리 = <석K>-<에이전트>(K = 0 또는 앞자리 0 없는 정수 · qa 도 숫자 토큰이면 석) · 석 칸 없는 옛 꼴 = PASS + 둘째 줄 WARN
#   #N = 계보 번호(0 이상 정수, 필수)
# 이행 기간의 구 이름(ft-·FB_·KakaoBot …)은 허용 목록 없이 그대로 REJECT 한다 — 신규 이름 검사용이다.
set -uo pipefail

ROLES="master arch da tester checker analyst pm nano repro tool desk qa"
AGENTS="claude codex opencode cmd pi"
MAXLEN=60

# ★역할 집합 노출(r975 r6 · 오빠 결정 5 = 4번)★ — «한 값은 한 곳». ft-nano-spawn.sh 의 «이 팀 좌석» 경계 판정이
#   자기 목록을 따로 적지 않고 이 값을 그대로 읽는다(`ft-name-lint.sh --roles`). 판정 로직은 그대로.
[ "${1:-}" = --roles ] && { printf '%s\n' "$ROLES"; exit 0; }

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: ft-name-lint.sh <세션명>" >&2; exit 2; }
NAME="$1"

rej() { echo "REJECT $NAME: $1"; exit 1; }
has() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }

[ "${#NAME}" -le "$MAXLEN" ] || rej "길이 ${#NAME} > $MAXLEN"
case "$NAME" in *"#"*) ;; *) rej "계보 번호 '#N' 없음";; esac
BASE="${NAME%#*}"; GEN="${NAME##*#}"
case "$GEN" in ''|*[!0-9]*) rej "'#' 뒤는 0 이상 정수여야 한다 ('$GEN')";; esac
case "$BASE" in *"#"*) rej "'#' 가 둘 이상";; esac
case "$BASE" in *[!a-z0-9-]*) rej "허용 문자는 소문자·숫자·'-' 뿐이다 (대문자·'_'·공백 금지)";; esac
case "$BASE" in -*|*-|*--*) rej "빈 토큰 ('-' 연속·양끝)";; esac

IFS='-' read -r PROJECT TEAM ROLE TAIL <<EOF
$BASE
EOF
# TAIL 은 read 가 나머지 전부를 받는다 (slug 안의 '-' 보존)
[ -n "${PROJECT:-}" ] && [ -n "${TEAM:-}" ] && [ -n "${ROLE:-}" ] || rej "토큰 부족 — <프로젝트>-<팀>-<역할>[-꼬리] 최소 3토큰"
has "$ROLES" "$ROLE" || rej "역할 '$ROLE' 은 예약어가 아니다 ($ROLES)"

if [ "$ROLE" = "nano" ]; then
  [ -n "${TAIL:-}" ] || rej "nano 는 카드 slug 꼬리 필수"
else
  [ -n "${TAIL:-}" ] || rej "역할 좌석은 에이전트 꼬리 필수 ($AGENTS)"
  SEAT=""; RANGE=""; H="${TAIL%%-*}"   # r1641 역할 바로 뒤 칸 = 석 K(숫자만) · qa 는 숫자 아닌 토큰이면 범위(r1650)
  if [ "$H" != "$TAIL" ]; then
    case "$H" in
      *[!0-9]*) has "$AGENTS" "$H" && rej "순서가 틀렸다 — <역할>-<석K>-<에이전트> ('$TAIL')"
                [ "$ROLE" = "qa" ] || rej "석 칸은 숫자여야 한다 ('$H') — 꼬리는 에이전트여야 한다: <역할>[-<석K>]-<에이전트>"; RANGE=1;;
      *) SEAT="$H"; TAIL="${TAIL#*-}";;
    esac
  fi
  case "$SEAT" in 0?*) rej "석 번호는 앞자리 0 없이 ('$SEAT')";; esac
  if [ -n "$RANGE" ]; then case "${TAIL%-*}" in *-*) rej "qa 범위는 1토큰만 ('${TAIL%-*}') — <qa>-<범위>-<에이전트>";; esac; TAIL="${TAIL##*-}"; fi
  case "$TAIL" in *-*) rej "석 칸 뒤는 에이전트 1토큰만 ('$TAIL') — <역할>-<석K>-<에이전트>";; esac
  has "$AGENTS" "$TAIL" || rej "역할 좌석 꼬리는 에이전트여야 한다 ($AGENTS) — '$TAIL'"
fi

echo "PASS $NAME"
[ "$ROLE" = "nano" ] || [ -n "$SEAT$RANGE" ] || echo "WARN 옛 꼴 — 다음 승계에서 $ROLE-0-$TAIL"   # r1641 첫 줄 계약 불변 · 개명 0(승계마다 이행)
