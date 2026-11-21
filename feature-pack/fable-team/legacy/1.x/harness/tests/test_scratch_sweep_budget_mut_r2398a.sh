#!/usr/bin/env bash
# test_scratch_sweep_budget_mut_r2398a.sh — r2398a 변이 3종(K2·K3) 원본 대조: 변이 판이 «기대한 칸» 만 빨강이 되는가.
#   M6 G6 생존 검사에서 reap 을 뺀다 → ⑧1(재등장 = 삭제 0) 빨강 · M3 지우기 길이 다시 크기(du)를 잰다 → ④(du 호출 0) 빨강 · M4 회차 전체 지도 실패를 «점유 0» 으로 읽는다 → ⑤1(사본별 후퇴) 빨강 · M5 예산 식에서 70초 상한을 뺀다 → ⑥2(예산 70초) 빨강
# 대역 = 사례 파일과 같은 tests/lib/sweep_budget_r2398a_bed.sh(임시 리포·가짜 tmux/lsof/du/date 만) — 실 상태 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"
. "$HERE/lib/sweep_budget_r2398a_bed.sh"
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; done_line; }
bed_begin "$SUT"

# ── M3 변이 «지우기 길에서 다시 크기를 잼(du)» → ④ 의 «du 호출 0» 이 빨강 ──────────────────────
if want M3; then
  mut M3 's/\[ "\$JMARK" = 0 \] || { ODEF=\$((ODEF+1)); return 1; }/[ "$JMARK" = 0 ] || { ODEF=$((ODEF+1)); return 1; }; cap COPY_KB kb "$1" 7   # r2398a-mut: 지우기 길이 다시 크기를 잰다/' && {
    reset
    for i in 1 2 3; do mtmp "d$i" >/dev/null; done
    STEP_TICKS=10 CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --sweep        # 예산을 빨리 바닥내 «예산 바닥» 갈래를 지나간다
    MC="$(duC)"
    [ "$MC" -gt 0 ] && ok "M3 지우기 길에서 크기를 다시 잼 → du ${MC}회 > 0 = ④ 빨강(변이 잡힘)" || bad "M3 을 못 잡음 — du 를 다시 넣어도 du ${MC}회"
  }
fi

# ── M4 변이 «전체 lsof 실패를 점유 0 으로 읽음» → ⑤ 가 빨강 ─────────────────────────────────────
if want M4; then
  mut M4 's#elif ! lsof_ok; then LSOF_OK=0; echo "ERROR lsof 실패 — 삭제 0 (cwd 판정 불가)" >&2; return 0; fi#else LSOF_MAP_OK=1; CWDROWS=""; fi   \# r2398a-mut: 실패를 «점유 0» 으로 읽음#' && {
    reset
    A="$(mkreg 00)"; B="$(mkreg 01)"
    : > "$T/map.fail"
    STEP_TICKS=0 CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --sweep
    PC="$(grep -c '조회 실패' <<<"$OUT")"
    { [ "$PC" = 0 ] && [ ! -d "$A" ] && [ ! -d "$B" ]; } \
      && ok "M4 지도 실패를 «점유 0» 으로 읽음 → 사본별 후퇴 0회 · 그대로 삭제 = ⑤1 빨강(변이 잡힘)" \
      || bad "M4 를 못 잡음 — 조회 실패 줄 $PC · A=$([ -d "$A" ] && echo 남음 || echo 지움) rc=$RC"
  }
fi

# ── M5 변이 «예산 식에서 70초 상한 뺌» → ⑥2 가 빨강 ───────────────────────────────────────────
if want M5; then
  mut M5 's/\[ "\$BUDGET_SEC" -le 70 \] || BUDGET_SEC=70/:/' && {
    reset
    many_tmp 2762
    STEP_TICKS=10 BUDGET= CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --sweep
    ! puts "$OUT" "예산 70초(후보 2762개)" && grep -q '예산 201초' <<<"$OUT" \
      && ok "M5 상한을 뺌 → 예산 201초(후보 2762) = ⑥2 빨강(변이 잡힘)" \
      || bad "M5 를 못 잡음 — 상한을 빼도 out=$(printf '%s' "$OUT" | grep -m1 '예산')"
  }
fi

# ── M6 변이 «G6 생존 검사에서 reap 을 뺀다(고침 1 제거)» → ⑧1 이 빨강 ─────────────────────────
if want M6; then
  mut M6 's/if \[ "\$mode" = sweep \] || \[ "\$mode" = reap \]; then/if [ "$mode" = sweep ]; then/' && {
    reset
    A="$(mkreap 00)"; printf 'gone-seat\n' > "$T/seat.reappear"
    STEP_TICKS=0 CASE_SUT="$MUTB/$(basename -- "$SUT")" sc --reap-owner gone-seat
    { [ ! -d "$A" ] && puts "$OUT" "REAP gone-seat done=1"; } \
      && ok "M6 G6 에서 reap 을 뺌 → lsof 단계 재등장에도 지워짐(done=1) = ⑧1 빨강(변이 잡힘)" \
      || bad "M6 를 못 잡음 — reap 을 빼도 A=$([ -d "$A" ] && echo 남음 || echo 지움) rc=$RC out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  }
fi

done_line
