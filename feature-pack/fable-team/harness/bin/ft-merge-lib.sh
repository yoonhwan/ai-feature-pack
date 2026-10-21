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
#   fm_land_ctx <repo> <remote> <ft_root|빈> : r648 — 승인 루트(부른 리포)와 대상 리포를 가른다. stdout 1줄 "<원장루트>|<CROSS 0|1>|<owner/name|빈>|<base-head 경로>|<대상 리포 루트>" (칸 구분 = | — 빈 칸이 있어도 밀리지 않게 탭 금지)
#     원장 루트 = FT_ROOT → 부른 리포(cwd 공용 루트) → 대상 리포 · CROSS = 부른 리포 ≠ 대상 리포(«리포 기준» 모드 — 원장은 부른 쪽 한 곳)
#     owner/name 은 CROSS 일 때만 잡는다(아니면 빈 값 = 이전 판 그대로 -R·FT_ISSUE_REPO 0) · 실제 전송 URL «전부»(`remote get-url --all` + `remote get-url --push --all` — push 는 등록된 모든 URL 로 간다)가 같은 github owner/name 일 때만(목적지가 둘 이상이거나 갈리면 REJECT)
#     base-head = <원장루트>/.fable-team/state/base-head · CROSS 면 -<owner>-<name> 꼬리(다른 리포 sha 를 기준 헤드로 섞지 않는다)
#     rc 1 = 대상 리포 루트 확인 실패 또는 CROSS 인데 owner/name 을 못 풂(다른 리포 PR 을 조용히 조회하는 길 0)
fm_land_ctx() {
  local repo="$1" rem="$2" ft="${3:-}" xrepo="" rroot="" rt="" slug="" bh cross=0
  rroot="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && rroot="$(dirname "$rroot")" || return 1
  [ -n "$rroot" ] || return 1
  xrepo="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && xrepo="$(dirname "$xrepo")" || xrepo=""
  rt="${ft:-${xrepo:-$rroot}}"
  [ -z "$xrepo" ] || [ "$xrepo" = "$rroot" ] || cross=1
  bh="$rt/.fable-team/state/base-head"
  if [ "$cross" = 1 ]; then   # 전송 목적지 «전부» 가 같은 값이어야 한다 — push 는 등록된 모든 URL 로 간다(land:82)
    local u s
    for u in $(git -C "$repo" remote get-url --all "$rem" 2>/dev/null) $(git -C "$repo" remote get-url --push --all "$rem" 2>/dev/null); do
      s="$(fm_gh_slug "$u")" || return 1
      [ -n "$s" ] || return 1
      [ -z "$slug" ] || [ "$slug" = "$s" ] || return 1
      slug="$s"
    done
    [ -n "$slug" ] || return 1
    bh="$bh-${slug//\//-}"
  fi
  printf '%s|%s|%s|%s|%s\n' "$rt" "$cross" "$slug" "$bh" "$rroot"
}
#   fm_gh_slug <url> : https://github.com/o/n[.git] · ssh://git@github.com/o/n[.git] · git@github.com:o/n[.git] 만 — 호스트가 «정확히» github.com 이고 owner/name 꼴이면 1줄, 아니면 빈 줄(rc0) · 꼴이 깨졌으면 rc1
fm_gh_slug() {
  local s
  case "$1" in
    https://github.com/*|ssh://git@github.com/*|git@github.com:*) ;;
    *) return 0;;
  esac
  s="${1#*github.com}"; s="${s#:}"; s="${s#/}"; s="${s%.git}"; s="${s%/}"
  printf '%s' "$s" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  printf '%s\n' "$s"
}
#   fm_flag_off_new <repo> <옛> <새> : R239 랜딩 직후 «새로 생긴 기본 꺼짐 플래그» 줄 출력 — 출력만(rc 항상 0 · 실패는 WARN 1줄 · 로컬 git 만 읽는다)
FM_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fm_flag_off_new() {
  local tb out rc; tb="$(fm_timeout_bin)" || { echo "WARN flag-off 검사 실패 timeout 도구 없음"; return 0; }
  out="$("$tb" 7 python3 "$FM_HERE/ft_flag_off.py" --repo "$1" --new-between "$2" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then [ -z "$out" ] || printf '%s\n' "$out"; else echo "WARN flag-off 검사 실패 rc=$rc $(printf '%s' "$out" | tail -n1)"; fi
  return 0
}
