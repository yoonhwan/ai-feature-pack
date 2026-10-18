#!/usr/bin/env bash
# ft-resource-preventive.sh — R332 · 감시자(ft-resource-watch.sh tick)가 진입 직후 부르는 «선제 회수» 보조 호출. 새 파괴 권한 0 — 닫기는 ft-resource-reclaim.sh --preventive(승인 두 행) 경유뿐.
#   due 판단 = 예방 전용 stamp(.preventive-last · 완료 시각) 가 FT_RECLAIM_PREVENT_SEC(기본 600 · 0 이면 호출 0) 보다 오래됨.
#   직렬 = 「기한 확인 → 실행권(preventive.lock.d · mkdir 1회 · 경합이면 즉시 포기) → ★실행권을 얻은 뒤 stamp 를 다시 읽어 due 재확인★ → 실행 → 완료 기록 → 실행권 해제」.
#   완료 기록 = 회수 도구가 `PREVENTIVE reclaimed=` 요약줄과 rc0 으로 끝났을 때만(후보 0 도 완료). 경합(`PREVENTIVE skipped=lock`)·실패는 stamp 0 → 다음 틱 재시도.
#   회수 실패·경합은 감시자의 측정·동결을 바꾸지 않는다 — 이 도구는 usage 오류 외엔 rc0 · 닫은 수>0·실패는 resource-watch.log 에 1줄.
#   env: FT_RES_ROOT(감시자가 넘김) · FT_RECLAIM_PREVENT_SEC · FT_RECLAIM_SH(시험 대역)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SEC="${FT_RECLAIM_PREVENT_SEC:-600}"
case "$SEC" in ''|*[!0-9]*) echo "ERROR FT_RECLAIM_PREVENT_SEC 숫자 아님: $SEC" >&2; exit 2;; esac
[ "$SEC" -gt 0 ] || exit 0
[ -n "${FT_RES_ROOT:-}" ] || { echo "ERROR FT_RES_ROOT 필요(감시자가 넘긴다)" >&2; exit 2; }
STATE="$FT_RES_ROOT/.fable-team/state"; STAMP="$STATE/.preventive-last"; XLOCK="$STATE/preventive.lock.d"; WLOG="$STATE/resource-watch.log"
RECLAIM="${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}"

due() { local last; last="$(cat "$STAMP" 2>/dev/null)"; case "$last" in ''|*[!0-9]*) last=0;; esac; [ $(( $(date +%s) - last )) -ge "$SEC" ]; }
logline() { printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$WLOG"; }

GUARD="$XLOCK.rc"   # 낡은 실행권 «회수+획득» 을 직렬화하는 원자 잠금(mkdir) — 한 번에 한 호출만 낡은 잠금을 지우고 새로 잡는다(DA⑥ H2)
older_than_1min() { [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }
acquire() {   # rc0 = 실행권 획득 · rc1 = 포기(살아 있는 보유자 · 다른 호출이 회수 중)
  local hp r=1
  mkdir "$XLOCK" 2>/dev/null && return 0
  mkdir "$GUARD" 2>/dev/null || { ! older_than_1min "$GUARD" || rmdir "$GUARD" 2>/dev/null; return 1; }   # 회수 중인 다른 호출이 있음(그 호출이 죽어 1분 넘게 남은 가드는 치운다)
  hp="$(cat "$XLOCK/pid" 2>/dev/null)"
  if { [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; } || { [ -z "$hp" ] && older_than_1min "$XLOCK"; }; then   # 죽은 보유자 · 또는 pid 기록 전에 죽어 1분 넘은 빈 잠금
    [ "$(cat "$XLOCK/pid" 2>/dev/null)" = "$hp" ] && rm -rf "$XLOCK"   # 관찰한 그 보유자의 잠금일 때만 삭제
    mkdir "$XLOCK" 2>/dev/null && r=0
  fi
  rmdir "$GUARD" 2>/dev/null
  return $r
}
due || exit 0
mkdir -p "$STATE" 2>/dev/null || exit 0
acquire || exit 0
echo $$ > "$XLOCK/pid"; trap '[ "$(cat "$XLOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$XLOCK"' EXIT   # 자기 잠금만 해제
due || exit 0   # 실행권을 얻은 «뒤» 최신 stamp 로 재확인 — 앞선 실행이 방금 끝났으면 재실행 0

out="$(bash "$RECLAIM" --preventive 2>&1)"; rc=$?
line="$(printf '%s\n' "$out" | grep '^PREVENTIVE ' | tail -1)"
case "$line" in
  "PREVENTIVE reclaimed="*)
    if [ "$rc" = 0 ]; then
      date +%s > "$STAMP.tmp.$$" && mv "$STAMP.tmp.$$" "$STAMP"
      case "$line" in "PREVENTIVE reclaimed=0 "*) ;; *) logline "$line";; esac
    else logline "ERROR preventive rc=$rc $line"; fi;;
  "PREVENTIVE skipped=lock") ;;
  *) logline "ERROR preventive rc=$rc $(printf '%s' "$out" | head -c 160 | tr '\n' ' ')";;
esac
exit 0
