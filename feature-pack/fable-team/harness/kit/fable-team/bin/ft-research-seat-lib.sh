#!/usr/bin/env bash
# ft-research-seat-lib.sh — 리서치 나노 좌석 셈·잠금 한 곳.
#   ★r921(오빠 2026-10-25 «멈춰 있으면 머할건데») — «리서치 나노 1석」 상한을 삭제했다★: 리서치는 일반 나노와 같은 규칙으로 열린다(상한 = 팀 나노 상한뿐).
#   셈 = 살아 있는 tmux 세션 이름 `*-research#N`. 조회 실패는 0석으로 «속이지» 않고 WARN 1줄 + 진행(못 세면 멈출 근거도 없다 · r921).
#   rc1 갈래(arch 119 재대조): tmux 는 «서버 없음»(정상 0석)도, «소켓·권한 오류»도 rc1 이다 → stderr 에 «no server running» 이 있을 때만 0석, 그 밖 rc1 = 셈 실패(rc655 H4⑦ 과 같은 처방).
#   잠금 = 조회~개설 구간(두 spawn 이 동시에 열어도 같은 자리를 두 번 쓰지 않게) · mkdir 원자 · pid 죽었으면 회수 · 10초 대기 뒤 포기.
#   쓰는 법:
#     . ft-research-seat-lib.sh
#     ft_research_live_count                    # rc0 = 수 출력 · rc2 = 셈 실패
#     ft_research_cap_check <lockdir>           # rc0 = 통과(잠금 유지 · 개설 뒤 ft_research_unlock <lockdir>) · rc1 = 잠금 대기 초과(거절)
FT_RESEARCH_SEAT_LIMIT=0   # r921: 0 = 상한 없음(일반 나노 규칙). 아래 cap_check 는 이 값을 읽지 않는다 — 남겨 두는 이유는 옛 호출자·문서 호환.
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

ft_research_cap_check() { # <lockdir> — 잠금만 잡는다(r921: 좌석 수 상한 삭제 · 셈 실패는 WARN 후 진행)
  local d="$1" n
  [ -z "${FT_RESEARCH_SEAT_MAX:-}" ] || echo "WARN research FT_RESEARCH_SEAT_MAX=${FT_RESEARCH_SEAT_MAX} 무시 — 리서치 좌석 상한 없음(r921: 일반 나노와 같은 규칙)" >&2
  ft_research_lock_take "$d" || { echo "REJECT 리서치 spawn 잠금 대기 초과 — 다른 리서치 개설 중: $d"; return 1; }
  n="$(ft_research_live_count)" || echo "WARN research 리서치 좌석 수 조회 실패(tmux list-sessions) — 세지 못한 채 진행(r921)" >&2
  return 0
}
