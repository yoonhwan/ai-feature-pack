#!/usr/bin/env bash
# ft-heavy-slot-lib.sh — 무거운 git 일(착지·사본·나노 워크트리)의 «전역 자리 2개» (r1286 · source 전용).
#   자리 = <데이터 루트>/.fable-team/state/heavy-slots/slot-1.lock · slot-2.lock (일반 파일 · 없으면 만듦).
#   잠금 = 이 셸이 연 파일 fd 에 BSD flock(LOCK_EX|LOCK_NB) — perl 이 dup 해 걸고 바로 끝난다. 잠금은 «열린 파일» 에 남으므로
#   쥔 셸이 끝나거나(또는 상속한 git 자식까지 끝나면) 커널이 푼다. 회수 코드 0 · pid 판정 0 · 만료 0(살아 있는 작업을 뺏지 않는다).
#   hs_acquire <도구> <대기 상한초>  rc0 = 쥠(HS_FD·HS_SLOT) · rc3 = 판정 불가(대기 초과·이미 쥠·perl/루트 없음) — 부르는 쪽이 «아무것도 안 함» 갈래로 받는다.
#   hs_release                      owner 비움 → fd 닫기 → HS_FD 지움 · 안 쥔 셸에서 부르면 아무것도 안 함(남의 잠금은 못 풂).
#   hs_held / hs_waiting            표본(f‌t-resource-sample)이 쓰는 «쥔 자리 수»·«대기 수» — 표시 전용.
#   env: FT_HEAVY_SLOTS=0 = 자리 검사 0(옛 동작) · FT_HEAVY_DIR = 자리 폴더 직접 지정(시험) · FT_HEAVY_POLL_SEC(기본 1)
#   하드 룰 19(우리 도구 파일 = 일반 파일) · 20(실패 = «판정 불가» 1줄) · 12(대기는 부르는 도구 예산 안)
set -uo pipefail
hs_dir() { # 자리 폴더 — 없으면 만든다. rc0 = HS_DIR 채움
  local d="${FT_HEAVY_DIR:-}"
  if [ -z "$d" ]; then
    local r="${FT_RES_ROOT:-${FT_ROOT:-}}"   # 도구마다 데이터 루트 이름이 다르다(scratch·sample = FT_RES_ROOT · merge-land = FT_ROOT)
    if [ -z "$r" ]; then
      local h="${BASH_SOURCE[0]:-$0}"; h="$(cd -- "$(dirname -- "$h")" && pwd)"
      [ ! -f "$h/ft-harness-root.sh" ] || { . "$h/ft-harness-root.sh"; r="$(ft_repo_root "$h")"; }
    fi
    [ -n "$r" ] || return 3
    d="$r/.fable-team/state/heavy-slots"
  fi
  mkdir -p "$d" 2>/dev/null || return 3
  HS_DIR="$d"; HS_OFF="${FT_HEAVY_SLOTS:-1}"
}
hs_count_held() { # 표시 전용 — 자리마다 새로 열어 LOCK_NB 시도(잡히면 바로 풂 = 빈 자리) → 0..2
  local n=0 i f fd
  hs_dir >/dev/null 2>&1 || { printf '%s' '-'; return 1; }
  [ "$HS_OFF" = 0 ] && { printf '%s' '-'; return 0; }
  for i in 1 2; do
    f="$HS_DIR/slot-$i.lock"
    { exec {fd}>>"$f"; } 2>/dev/null || continue
    perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$fd" 2>/dev/null || n=$((n+1))   # 거절 = 누가 쥠
    eval "exec ${fd}>&-" 2>/dev/null
  done
  printf '%s' "$n"
}
hs_waiting() { # 표시 전용 — wait.d/<pid> 중 살아 있는 수(죽은 pid 파일은 지운다)
  local c=0 f p
  hs_dir >/dev/null 2>&1 || { printf '0'; return 0; }
  [ -d "$HS_DIR/wait.d" ] || { printf '0'; return 0; }
  for f in "$HS_DIR"/wait.d/*; do
    [ -e "$f" ] || continue
    p="${f##*/}"
    case "$p" in ''|*[!0-9]*) rm -f "$f" 2>/dev/null; continue;; esac
    kill -0 "$p" 2>/dev/null || { rm -f "$f" 2>/dev/null; continue; }
    c=$((c+1))
  done
  printf '%s' "$c"
}
hs_ahead() { # 표시 전용 «슬롯 도구·pid·경과 초» — owner 파일(없으면 «빈 자리»)
  local i ow f now t
  hs_dir >/dev/null 2>&1 || { printf '-'; return 0; }
  now="$(date +%s)"
  for i in 1 2; do
    ow=""; f="$HS_DIR/slot-$i.owner"
    [ ! -s "$f" ] || ow="$(cat "$f" 2>/dev/null)"
    set -- $ow
    if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
      t="${3:-$now}"; case "$t" in ''|*[!0-9]*) t="$now";; esac
      printf 'slot-%s %s·%s·%s초' "$i" "$1" "$2" "$((now-t))"
    else printf 'slot-%s 빈 자리' "$i"; fi
    [ "$i" = 2 ] || printf ' · '
  done
}
hs_try() { # <자리 파일> → rc0 잡음(fd 유지) · rc1 남이 쥠 · rc3 판정 불가
  local f="$1" rc
  { exec {HS_FD}>>"$f"; } 2>/dev/null || { unset HS_FD; return 3; }
  perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$HS_FD" 2>/dev/null
  rc=$?
  [ "$rc" = 0 ] && return 0
  eval "exec ${HS_FD}>&-" 2>/dev/null; unset HS_FD
  [ "$rc" = 1 ] && return 1
  return 3
}
hs_acquire() { # <도구> <대기 상한초>
  local tool="${1:-?}" lim="${2:-0}" start now waited=0 said=0 i
  [ "${FT_HEAVY_SLOTS:-1}" = 0 ] && return 0
  [ -z "${HS_FD:-}" ] || { HS_MSG="판정 불가 — 이미 자리를 쥠(release 누락)"; echo "$HS_MSG" >&2; return 3; }
  hs_dir || { HS_MSG="판정 불가 — 데이터 루트 해석 실패"; echo "$HS_MSG" >&2; return 3; }
  command -v perl >/dev/null 2>&1 || { HS_MSG="판정 불가 — perl 없음(flock 불가)"; echo "$HS_MSG" >&2; return 3; }
  case "$lim" in ''|*[!0-9]*) lim=0;; esac
  mkdir -p "$HS_DIR/wait.d" 2>/dev/null && : > "$HS_DIR/wait.d/$$" 2>/dev/null
  start="$(date +%s)"
  while :; do
    for i in 1 2; do
      if hs_try "$HS_DIR/slot-$i.lock"; then
        HS_SLOT="slot-$i"
        printf '%s %s %s\n' "$tool" "$$" "$(date +%s)" > "$HS_DIR/$HS_SLOT.owner" 2>/dev/null
        rm -f "$HS_DIR/wait.d/$$" 2>/dev/null
        return 0
      fi
    done
    now="$(date +%s)"; waited=$((now-start))
    [ "$said" = 1 ] || { said=1; HS_MSG="순번 대기 $(hs_waiting)(앞: $(hs_ahead))"; echo "$HS_MSG" >&2; }
    if [ "$lim" -le 0 ] || [ "$waited" -ge "$lim" ]; then
      rm -f "$HS_DIR/wait.d/$$" 2>/dev/null
      HS_MSG="판정 불가 — 무거운 git 자리 대기 ${waited}초 초과(앞: $(hs_ahead))"; echo "$HS_MSG" >&2
      return 3
    fi
    sleep "${FT_HEAVY_POLL_SEC:-1}"
  done
}
hs_release() {
  [ -n "${HS_FD:-}" ] || return 0
  [ -z "${HS_SLOT:-}" ] || : > "$HS_DIR/$HS_SLOT.owner" 2>/dev/null
  eval "exec ${HS_FD}>&-" 2>/dev/null
  unset HS_FD HS_SLOT
  return 0
}
