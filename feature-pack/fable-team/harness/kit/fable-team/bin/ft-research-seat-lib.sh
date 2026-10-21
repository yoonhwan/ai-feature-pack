#!/usr/bin/env bash
# ft-research-seat-lib.sh — r672: «리서치 나노 1석» 판정 한 곳(DA⑥ r1 H1 · 동결 면제의 대가).
#   셈 = 살아 있는 tmux 세션 이름 `*-research#N`. 조회 실패는 0석이 아니라 «셈 실패»(통과 금지 · BYZ #0 NO SILENT FALLBACK).
#   rc1 갈래(arch 119 재대조): tmux 는 «서버 없음»(정상 0석)도, «소켓·권한 오류»도 rc1 이다 → stderr 에 «no server running» 이 있을 때만 0석, 그 밖 rc1 = 셈 실패(rc655 H4⑦ 과 같은 처방).
#   상한 = 코드 상수 1 — env(FT_RESEARCH_SEAT_MAX)로 올릴 수 없다(주입하면 WARN 1줄 + 1). 닫히면 다시 열린다.
#   잠금 = 조회~개설 구간(두 spawn 이 동시에 0석을 읽고 둘 다 여는 길 0) · mkdir 원자 · pid 죽었으면 회수 · 10초 대기 뒤 포기.
#   쓰는 법:
#     . ft-research-seat-lib.sh
#     ft_research_live_count                    # rc0 = 수 출력 · rc2 = 셈 실패
#     ft_research_cap_check <lockdir>           # rc0 = 통과(잠금 유지 · 개설 뒤 ft_research_unlock <lockdir>) · rc3 = 거절(사유 stdout · 잠금 해제) · rc4 = 셈 실패
FT_RESEARCH_SEAT_LIMIT=1
FT_RESEARCH_LOCK_WAIT=100   # 0.1초 × 100 = 10초
FT_RESEARCH_LOCK_STALE=10   # 빈 pid 잠금을 «만드는 중» 으로 봐 주는 시간(초) — 넘으면 회수

ft_research_live_count() {
  local out rc n ef err
  ef="$(mktemp "${TMPDIR:-/tmp}/ft-research-count.XXXXXX" 2>/dev/null)" || return 2
  out="$(tmux list-sessions -F '#{session_name}' 2>"$ef")"; rc=$?
  err="$(cat "$ef" 2>/dev/null)"; rm -f "$ef"
  case "$rc" in
    0) ;;
    1) case "$err" in *"no server running"*) out="" ;; *) return 2;; esac;;   # 서버 없음 = 0석 · 소켓·권한 오류 등 그 밖 rc1 = 셈 실패
    *) return 2;;
  esac
  n="$(printf '%s\n' "$out" | grep -c -- '-research#[0-9]')"
  case "$n" in ''|*[!0-9]*) return 2;; esac
  printf '%s' "$n"
}

ft_research_lock_take() { # <lockdir> — 잠금 획득 rc0 · 대기 초과 rc1 · «빈 pid = 만드는 중» 은 지우지 않고 기다린다(폴더가 10초 넘게 묵었을 때만 회수 · arch 119 관찰)
  local d="$1" i=0 p age
  while :; do
    if mkdir "$d" 2>/dev/null; then printf '%s\n' "$$" > "$d/pid" 2>/dev/null; return 0; fi
    p="$(cat "$d/pid" 2>/dev/null)"
    if [ -z "$p" ]; then   # mkdir 직후·pid 쓰기 직전일 수 있다 — 나이 보고 회수
      age=$(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || echo "$(date +%s)") ))
      [ "$age" -gt "$FT_RESEARCH_LOCK_STALE" ] && rm -rf "$d" 2>/dev/null
    else
      case "$p" in *[!0-9]*) rm -rf "$d" 2>/dev/null;; *) kill -0 "$p" 2>/dev/null || rm -rf "$d" 2>/dev/null;; esac
    fi
    i=$((i+1)); [ "$i" -le "$FT_RESEARCH_LOCK_WAIT" ] || return 1; sleep 0.1
  done
}

ft_research_unlock() { [ -z "${1:-}" ] || rm -rf "$1" 2>/dev/null; return 0; }

ft_research_cap_check() { # <lockdir> — 잠그고 «그 안에서» 다시 세서 상한 판정(잠금은 통과일 때만 유지)
  local d="$1" n
  case "${FT_RESEARCH_SEAT_MAX:-$FT_RESEARCH_SEAT_LIMIT}" in
    "$FT_RESEARCH_SEAT_LIMIT"|"") ;;
    *) echo "WARN research FT_RESEARCH_SEAT_MAX=${FT_RESEARCH_SEAT_MAX} 무시 — 상한은 ${FT_RESEARCH_SEAT_LIMIT} 고정(동결 면제는 1석만 · r672)" >&2;;
  esac
  ft_research_lock_take "$d" || { echo "REJECT 리서치 spawn 잠금 대기 초과 — 다른 리서치 개설 중(1석 상한 · r672 H1): $d"; return 3; }
  n="$(ft_research_live_count)" || { echo "REJECT 리서치 좌석 수 조회 실패(tmux list-sessions) — 셈 못 하면 열지 않는다(r672 H1)"; ft_research_unlock "$d"; return 4; }
  [ "$n" -lt "$FT_RESEARCH_SEAT_LIMIT" ] || { echo "REJECT 리서치 나노 상한 — 살아 있는 리서치 좌석 ${n}석(한도 ${FT_RESEARCH_SEAT_LIMIT} 고정 · r672: 동결 면제는 1석만)"; ft_research_unlock "$d"; return 3; }
  return 0
}
