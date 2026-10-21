#!/usr/bin/env bash
# ft-merge-lib.sh — 병합·랜딩 도구 공용 함수 (R230 · source 전용 · 7초 룰 판정 666)
#   fm_t7 <명령…>            : 시도당 timeout 7 초 + 재시도 1 (총 14 초 상한) — timeout 도구 없으면 rc 127 (조용한 통과 0)
#   fm_fetch <repo> <remote> <ref> : fm_t7 로 한 ref 만 받는다
fm_timeout_bin() { command -v timeout || command -v gtimeout; }
fm_t7() {
  local tb rc=0 i; tb="$(fm_timeout_bin)" || { echo "timeout/gtimeout 없음 — 7초 상한을 걸 수 없어 외부 호출 거절" >&2; return 127; }
  for i in 1 2; do "$tb" 7 "$@" && return 0; rc=$?; done
  return "$rc"
}
fm_fetch() { fm_t7 git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3"; }
#   fm_push_calc <객체수|?> : push «시도당 상한»(정수 초 · 소수 버림) = min(F + 7 × ceil(N/U0), 70) — 규칙 12 «쪼갤 수 없는 크기 아는 배치»(판정 1375). N 모름(?) = F + 7.
#     F = FT_PUSH_FIXED_S(기본 4.5 · ssh 접속 2.9 + pre-push 훅 1.1 실측 + 여유 · 7 초과는 7 로 클램프) · U0 = FT_PUSH_UNIT_OBJECTS(기본 100 객체/7 s 잠정 · 양의 정수 아니면 기본) · 잘못된 env 는 WARN(stderr)
#   fm_push_bound <repo> <M> <Q> : stdout "<객체수|?> <시도당 상한>" — 객체수 = rev-list --objects M..Q · 조회 실패는 WARN 1줄 + 호환값(F+7) (조용한 통과 0)
fm_push_calc() {
  local n="$1" f="${FT_PUSH_FIXED_S:-4.5}" u="${FT_PUSH_UNIT_OBJECTS:-100}"
  printf '%s' "$f" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && awk -v f="$f" 'BEGIN{exit !(f>0)}' || { echo "WARN FT_PUSH_FIXED_S=$f 는 0 보다 큰 숫자가 아님 → 기본 4.5" >&2; f=4.5; }
  awk -v f="$f" 'BEGIN{exit !(f>7)}' && { echo "WARN FT_PUSH_FIXED_S=$f 는 7 초과 → 7 로 클램프" >&2; f=7; }
  printf '%s' "$u" | grep -Eq '^[0-9]+$' && [ "$u" -gt 0 ] || { echo "WARN FT_PUSH_UNIT_OBJECTS=$u 는 양의 정수가 아님 → 기본 100" >&2; u=100; }
  if [ "$n" = '?' ]; then awk -v f="$f" 'BEGIN{printf "%d\n", f+7}'
  else awk -v f="$f" -v n="$n" -v u="$u" 'BEGIN{k=int((n+u-1)/u); if(k<1)k=1; t=f+7*k; if(t>70)t=70; printf "%d\n", t}'; fi
}
fm_push_bound() {
  local out n
  if out="$(git -C "$1" rev-list --objects "$2..$3" 2>&1)"; then n="$(printf '%s\n' "$out" | grep -c . || true)"
  else echo "WARN 객체 수 조회 실패(rev-list) → 크기 모름 · 상한 F+7 호환값: $(printf '%s' "$out" | tail -n1)" >&2; n='?'; fi
  echo "$n $(fm_push_calc "$n")"
}
#   fm_land_ctx <repo> <remote> <ft_root|빈> : r648 — 승인 루트(BYZ)와 대상 리포를 가른다. stdout 1줄 "<원장루트>|<CROSS 0|1>|<owner/name|빈>|<base-head 경로>|<대상 리포 루트>" (칸 구분 = | — 빈 칸이 있어도 밀리지 않게 탭 금지)
#     원장·승인 루트 = FT_ROOT → 부른 리포(cwd 공용 루트) → 대상 리포 루트 · CROSS = 부른 리포 ≠ 대상 리포(«리포 기준» 모드 — 원장은 부른 쪽 한 곳)
#     owner/name = 대상 리포 remote.<remote>.url(https://github.com/o/n[.git] · git@github.com:o/n.git) — 깃허브 아님(로컬 경로)은 빈 값(그때는 -R 없이 지금 그대로)
#     base-head = <원장루트>/.fable-team/state/base-head · CROSS 면 -<owner>-<name> 꼬리(다른 리포 sha 를 기준 헤드로 섞지 않는다)
#     rc 1 = 대상 리포 루트 확인 실패 또는 CROSS 인데 owner/name 을 못 풂(다른 리포 PR 을 조용히 조회하는 길 0)
fm_land_ctx() {
  local repo="$1" rem="$2" ft="${3:-}" xrepo="" rroot="" rt="" url="" slug="" bh cross=0
  rroot="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && rroot="$(dirname "$rroot")" || return 1
  [ -n "$rroot" ] || return 1
  xrepo="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && xrepo="$(dirname "$xrepo")" || xrepo=""
  url="$(git -C "$repo" config --get "remote.$rem.url" 2>/dev/null)" || url="$(git -C "$repo" remote get-url "$rem" 2>/dev/null)" || url=""
  case "$url" in *github.com*)
    slug="${url#*github.com}"; slug="${slug#[:/]}"; slug="${slug%.git}"; slug="${slug%/}"
    printf '%s' "$slug" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1;;
  esac
  [ -z "$xrepo" ] || [ "$xrepo" = "$rroot" ] || cross=1
  [ "$cross" = 0 ] || [ -n "$slug" ] || return 1
  rt="${ft:-${xrepo:-$rroot}}"; bh="$rt/.fable-team/state/base-head"
  [ "$cross" = 0 ] || bh="$bh-${slug//\//-}"
  printf '%s|%s|%s|%s|%s\n' "$rt" "$cross" "$slug" "$bh" "$rroot"
}
#   fm_flag_off_new <repo> <옛> <새> : R239 랜딩 직후 «새로 생긴 기본 꺼짐 플래그» 줄 출력 — 출력만(rc 항상 0 · 실패는 WARN 1줄 · 로컬 git 만 읽는다)
FM_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fm_flag_off_new() {
  local tb out rc; tb="$(fm_timeout_bin)" || { echo "WARN flag-off 검사 실패 timeout 도구 없음"; return 0; }
  out="$("$tb" 7 python3 "$FM_HERE/ft_flag_off.py" --repo "$1" --new-between "$2" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then [ -z "$out" ] || printf '%s\n' "$out"; else echo "WARN flag-off 검사 실패 rc=$rc $(printf '%s' "$out" | tail -n1)"; fi
  return 0
}
