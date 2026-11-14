#!/bin/sh
# r1900 pre-push 나노 가드 — 나노 좌석(env FT2_HOLDER·FT_SEAT_NAME 에 -nano-)의 main·ops/main-base push 를 거부한다.
# stdin(ref 줄)만 읽는다 · 저장·재생은 부르는 훅 몫 · 착지 = master · --no-verify 는 건너뜀(실수 방지 장치 · 권한 통제 아님).
seat=""
for s in "${FT2_HOLDER:-}" "${FT_SEAT_NAME:-}"; do
  case "$s" in *-nano-*) seat="$s"; break ;; esac
done
[ -n "$seat" ] || { cat >/dev/null; exit 0; }
card_only() {   # r1999: ops/main-base 면제 = 커밋 1개(부모 = remote_sha) · 파일 1개 */indices/*.md · 지운 줄 0 → 0 · 아니면 1 · git 실패 = 2
  case "$1 $2" in *0000000000000000000000000000000000000000*) return 1 ;; esac
  p=$(git rev-parse "$1^@" </dev/null 2>/dev/null) || return 2
  [ "$p" = "$2" ] || return 1   # r1999-mut:parent
  n=$(git -c core.quotePath=false diff --no-renames --numstat "$2" "$1" </dev/null 2>/dev/null) || return 2
  IFS="$(printf '\t')" read -r a d f x <<EOF
$n
EOF
  case "$a" in ''|*[!0-9]*) return 1 ;; esac
  [ "$d" = 0 ] || return 1   # r1999-mut:del
  [ -z "$x" ] && [ "$(printf '%s\n' "$n" | wc -l)" -eq 1 ] && case "$f" in */indices/*.md) return 0 ;; esac; return 1
}
rc=0
while read -r local_ref local_sha remote_ref remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/ops/main-base)
      if [ "$remote_ref" = refs/heads/ops/main-base ]; then card_only "$local_sha" "$remote_sha"; k=$?; else k=1; fi
      [ "$k" = 0 ] && continue
      [ "$k" = 2 ] && echo "판정 불가 나노 가드 git rev-parse·diff 실패($remote_ref) rc=1" >&2
      echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — 착지 = master" >&2
      rc=1 ;;
  esac
done
exit $rc
