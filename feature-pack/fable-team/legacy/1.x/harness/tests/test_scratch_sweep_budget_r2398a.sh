#!/usr/bin/env bash
# test_scratch_sweep_budget_r2398a.sh — r2398a K2·K3: ft-scratch-repo.sh --sweep(지우기 길)이 «실제로 돈다».
#   K2 = 지우기 길은 크기(du)를 부르지 않는다(크기 «?» · 표시 전용 · 결정 입력 0) · 점유 조회 = 회차 시작에 전체 1회(`lsof -a -d cwd -Fpcn` · 7초) → 사본마다 cwd_holder 비교 ·
#        전체 조회 실패(rc≠0·0줄) = 사본별 1회 길로 후퇴(r1029 그대로 — «실패를 점유 0 으로 읽지 않는다»)
#   K3 = 예산 = FT_SCRATCH_JUDGE_BUDGET 미설정이면 min(5초 + 7초×ceil(후보/100), 70초)(설정값은 그대로 상한) · 끝 줄에 judged·swept·round(done|cursor) 셋을 따로 · WARN «예산 N초(후보 M개)» 1줄
# 사례 = ④ 사본 300 · du 2초(가짜) → du 호출 0 · 예산 26초 · judged ≥ 60 · swept ≥ 1 · round=cursor → 다음 틱 이어서 judged 누적 300 · round=done
#        ⑤ 전체 lsof 실패 → 사본별 후퇴(삭제 결과 같음) / 전체 lsof 가 사본 1개를 cwd 로 보고 → 그 사본 held · 나머지 진행
#        ⑥ 예산 20초 명시 = 20초 그대로 / 후보 2762개 = 70초(상한) · WARN «예산 70초(후보 2762개)» · ⑦ (정정2 DA H2) 후보 0 끝 줄의 judged·round 는 실제 값
# 변이(원본과 같은 사례 1회 대조) = 짝 파일 test_scratch_sweep_budget_mut_r2398a.sh(M3·M4·M5) · 대역 = tests/lib/sweep_budget_r2398a_bed.sh
# 임시 git 저장소·가짜 tmux·가짜 lsof·가짜 du·가짜 date(가상 시계)·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR·실 상태 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/sweep_budget_r2398a_bed.sh"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"   # FT_SUT = 변이 판(원본 대조) 실행용
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; done_line; }
bed_begin "$SUT"

# ── ④ 사본 300 · du 2초(가짜) → du 0 · 예산 26초 · judged ≥ 60 · swept ≥ 1 · round=cursor → 이어서 round=done ──
if want ④; then
  reset
  R1="$(mkreg 00)"                      # swept ≥ 1 증거(진짜 워크트리 하나)
  many_tmp 299   # 나머지 299 = $TMPDIR tmp.*(같은 예산 눈금 · N = 300 · 실제로 지워져서 다음 틱 후보가 줄어든다)
  t0=$SECONDS; GATE_TICKS=3 BUDGET= sc --sweep; tm1=$SECONDS   # 삭제 1건 = 0.3초(가상 · «사본 1개 git 0.3초» 자리) · du 1회 = 2초(가짜)
  t1="$(field judged)"; sw="$(field swept)"; rd="$(roundof)"; du="$(duC)"
  { [ "$RC" = 0 ] && [ "$du" = 0 ] && puts "$OUT" "예산 26초(후보 300개)" && [ -n "$t1" ] && [ "$t1" -ge 60 ] \
    && [ -n "$sw" ] && [ "$sw" -ge 1 ] && [ "$rd" = cursor ] && [ ! -d "$R1" ]; } \
    && ok "④1 예산 26초(후보 300) · du 호출 0 · judged=$t1 ≥ 60 · swept=$sw ≥ 1 · round=cursor · $(( tm1 - t0 ))초" \
    || bad "④1 rc=$RC du=$du judged=${t1:-?} swept=${sw:-?} round=${rd:-?} R1=$([ -d "$R1" ] && echo 남음 || echo 지움) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  total="${t1:-0}"; ticks=1; rd="$(roundof)"; tm2=$SECONDS
  while [ "$rd" != done ] && [ "$ticks" -lt 20 ]; do
    GATE_TICKS=0 BUDGET= sc --sweep; ticks=$((ticks+1)); rd="$(roundof)"
    n="$(field judged)"; total=$(( total + ${n:-0} ))
  done
  LEFT="$(find "$TMPD" -maxdepth 1 -type d -name 'tmp.*' | wc -l | tr -d ' ')"
  { [ "$rd" = done ] && [ "$total" -ge 300 ] && [ "$LEFT" = 0 ]; } \
    && ok "④2 다음 틱 이어서 judged 합 $total ≥ 300 · ${ticks}틱 만에 round=done · tmp.* 0개(바퀴가 실제로 돈다) · $(( SECONDS - tm2 ))초" \
    || bad "④2 round=${rd:-?} judged합=$total 틱=$ticks 남은tmp=$LEFT out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ⑤ 전체 lsof 실패 → 사본별 후퇴(삭제 결과 같음) / 전체 lsof 가 사본 1개를 cwd 로 → 그 사본만 held ──
if want ⑤; then
  reset
  A="$(mkreg 00)"; B="$(mkreg 01)"
  : > "$T/map.fail"                                   # 회차 전체 지도 실패(rc1)
  STEP_TICKS=0 sc --sweep
  PC="$(grep -c -- 'x' /dev/null 2>/dev/null)"; PC=0   # (자리표시 · 아래에서 사본별 호출을 센다)
  PC="$(printf '%s\n' "$OUT" | grep -c '판정 불가')"   # 사본별 후퇴 흔적은 아래 두 줄(삭제 결과)로 본다
  { [ "$RC" = 0 ] && [ ! -d "$A" ] && [ ! -d "$B" ] && puts "$OUT" "swept=2 owner-dead=2"; } \
    && ok "⑤1 전체 지도 실패 → 사본별 조회 길로 후퇴 · 삭제 결과 같음(swept=2)" \
    || bad "⑤1 rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  reset
  A="$(mkreg 00)"; B="$(mkreg 01)"
  printf 'p777\ncpytest\nfcwd\nn%s/sub\n' "$A" > "$T/lsof.all"   # 전체 지도가 A 를 cwd 로 쓰는 프로세스를 본다
  STEP_TICKS=0 sc --sweep
  { [ "$RC" = 0 ] && [ -d "$A" ] && [ ! -d "$B" ] && field held | grep -qx 1; } \
    && ok "⑤2 전체 지도가 A 를 cwd 로 봄 — A held(보류) · B 는 삭제(나머지 진행)" \
    || bad "⑤2 rc=$RC A=$([ -d "$A" ] && echo 남음 || echo 지움) B=$([ -d "$B" ] && echo 남음 || echo 지움) held=$(field held) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ⑥ 예산 20초 명시 = 20초 그대로 / 후보 2762개 = 70초(상한) ─────────────────────────────────
if want ⑥; then
  reset
  mtmp a >/dev/null; mtmp b >/dev/null; mtmp c >/dev/null
  BUDGET=20 STEP_TICKS=0 sc --sweep
  { [ "$RC" = 0 ] && puts "$OUT" "예산 20초(후보 3개)"; } \
    && ok "⑥1 FT_SCRATCH_JUDGE_BUDGET=20 명시 — 예산 20초 그대로(후보 3개)" \
    || bad "⑥1 rc=$RC out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  reset
  many_tmp 2762
  STEP_TICKS=10 BUDGET= sc --sweep
  { [ "$RC" = 0 ] && puts "$OUT" "예산 70초(후보 2762개)"; } \
    && ok "⑥2 후보 2762개 — 예산 = 상한 70초 · WARN «예산 70초(후보 2762개)»" \
    || bad "⑥2 rc=$RC out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

# ── ⑦ 정정2(DA H2): N=0 끝 줄은 «상수» 가 아니라 실제 판정·끊긴 자리 ───────────────────────────
if want ⑦; then
  reset
  A="$(mtmp a)"; B="$(mtmp b)"
  printf 'p777\ncpytest\nfcwd\nn%s/sub\nn%s/sub\n' "$A" "$B" > "$T/lsof.all"   # 둘 다 점유 = 판정은 끝났지만 후보 0
  STEP_TICKS=0 sc --sweep
  J="$(field judged)"
  { [ "$RC" = 0 ] && [ "$(field held)" = 2 ] && [ -n "$J" ] && [ "$J" -ge 2 ] && [ "$(roundof)" = done ]; } \
    && ok "⑦1 후보 0(둘 다 붙잡음) — judged=$J ≥ 2 · held=2 · round=done(상수 0 아님)" \
    || bad "⑦1 rc=$RC held=$(field held) judged=${J:-?} round=${J:+$(roundof)} out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
  reset
  mtmp a >/dev/null; mtmp b >/dev/null; mtmp c >/dev/null
  STEP_TICKS=10 BUDGET=1 sc --sweep   # date 1회 = 1초 · 예산 1초 → 첫 판정 전에 예산이 바닥난다
  J2="$(field judged)"
  { [ "$RC" = 0 ] && [ "${J2:-0}" = 0 ] && [ "$(roundof)" = cursor ] && [ -s "$CURSOR" ]; } \
    && ok "⑦2 첫 판정 전 예산 소진 — judged=0 · round=cursor(끝 줄·cursor 파일 둘 다 cursor)" \
    || bad "⑦2 rc=$RC judged=${J2:-?} round=$(roundof) cursor=$([ -s "$CURSOR" ] && echo 있음 || echo 없음) out=$(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

done_line
