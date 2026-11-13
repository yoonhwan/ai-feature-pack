#!/bin/sh
# r1900 pre-push 나노 가드 — 나노 좌석(env FT2_HOLDER·FT_SEAT_NAME 에 -nano-)의 main·ops/main-base push 를 거부한다.
# stdin(ref 줄)만 읽는다 · 저장·재생은 부르는 훅 몫 · 착지 = master · --no-verify 는 건너뜀(실수 방지 장치 · 권한 통제 아님).
seat=""
for s in "${FT2_HOLDER:-}" "${FT_SEAT_NAME:-}"; do
  case "$s" in *-nano-*) seat="$s"; break ;; esac
done
[ -n "$seat" ] || { cat >/dev/null; exit 0; }
rc=0
while read -r local_ref local_sha remote_ref remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/ops/main-base)
      echo "PUSH_DENIED 나노 좌석 $seat 의 $remote_ref push — 착지 = master" >&2
      rc=1 ;;
  esac
done
exit $rc
