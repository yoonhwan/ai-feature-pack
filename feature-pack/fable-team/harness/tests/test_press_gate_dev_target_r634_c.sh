#!/usr/bin/env bash
# test_press_gate_dev_target_r634_c.sh — r634 press 게이트 «dev 대상» 갈래 시험의 3/3 — ⓞ8 ⓛ 시간 상한 · ⓜ 변이 · 정적 (r1134: 한 파일 132초 → 3파일 · 하드 룰 22 «시험 1개 단독 70초»).
#   공용 준비(스텁·mkroot·gate·expect) = lib/press_gate_dev_target_r634.sh · 칸 내용은 쪼개기 전 test_press_gate_dev_target_r634.sh 그대로.
#   짝: test_press_gate_dev_target_r634_a.sh(ⓐ~ⓚ) · _b.sh(ⓝ · ⓞ1~ⓞ7) · _c.sh(ⓞ8 ⓛ ⓜ 정적) — 셋을 다 돌려야 r634 전부다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/press_gate_dev_target_r634.sh"

# ══ ⓞ8 (r685 DA⑥ r1 H2 본문 판별 마감 — 시간 칸이라 ⓛ 와 같은 파일)
mkroot o8; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FT_PRESS_DEV_BUDGET=4 FAKE_PY=slow; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 20 ] && printf '%s' "$OUT" | grep -q 'dev web health 200 이지만 본문 판별' && ! printf '%s' "$OUT" | grep -q 'dev gateway health 200 —' \
  && ok "$n. ⓞ8 느린 본문 판별(30초·TERM 무시) + 마감 4초 → ${el}초 만에 web·gateway 막힘(판별도 마감 안 · exit $got)" \
  || { bad "$n. ⓞ8 느린 본문 판별 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓛ H4 시간 상한(TERM 무시 자식 · 전체 마감)
mkroot l1; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FAKE_SLOW_SVC="$SVC_WK"; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 15 ] && printf '%s' "$OUT" | grep -q 'dev worker 이미지 sha 못 읽음' \
  && ok "$n. ⓛ1 TERM 무시 스텁(gcloud 30초) → ${el}초 만에 막힘(timeout -k 강제종료 · exit $got)" \
  || { bad "$n. ⓛ1 TERM 무시 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# ⓛ1b _bounded 단위 — timeout/gtimeout 이 «없는» PATH 에서 TERM 무시 자식을 KILL 로 끊는가(실제 경과 단언)
sed -n '/^_bounded(){/,/^}/p' "$GATE" > "$T/bounded.sh"
printf '#!/bin/sh\ntrap "" TERM\nsleep 30\n' > "$T/termsh"; chmod +x "$T/termsh"   # TERM 을 무시하는 자식
n=$((n+1)); u="$(PATH=/usr/bin:/bin bash -c 'source "$1"; s=$SECONDS; _bounded 3 "$2"; echo "rc=$? el=$((SECONDS-s))"' _ "$T/bounded.sh" "$T/termsh" 2>&1)"
urc="$(printf '%s' "$u" | sed -n 's/.*rc=\([0-9]*\).*/\1/p')"; uel="$(printf '%s' "$u" | sed -n 's/.*el=\([0-9]*\).*/\1/p')"
[ -n "$urc" ] && [ "$urc" != 0 ] && [ "${uel:-99}" -le 8 ] \
  && ok "$n. ⓛ1b _bounded(timeout 없는 PATH) = TERM 무시 자식을 ${uel}초에 KILL(rc=$urc)" \
  || bad "$n. ⓛ1b _bounded 대체 경로 (${u:-출력 없음})"

mkroot l2; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FT_PRESS_DEV_BUDGET=5 FAKE_SLOW_HEALTH=1; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 25 ] && printf '%s' "$OUT" | grep -q 'dev 검사 시간 마감' \
  && ok "$n. ⓛ2 전체 마감(FT_PRESS_DEV_BUDGET=5) 넘기면 막힘 — ${el}초(exit $got)" \
  || { bad "$n. ⓛ2 전체 마감 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓜ 변이 대조(H5④): dev 칸 최종 판정(FAIL=1)을 «:» 로 지운 사본에서 ⓑ 가 통과해 버리는가
mkroot m; dev_env
mkdir -p "$T/mut"; for f in "$(dirname "$GATE")"/*; do b="$(basename "$f")"; [ "$b" = ft-press-gate.sh ] && continue; ln -sf "$f" "$T/mut/$b"; done
MUT="$T/mut/ft-press-gate.sh"
sed 's/^  \[ "\$bad" = "0" \] || FAIL=1$/  : # MUTANT/' "$GATE" > "$MUT"; chmod +x "$MUT"
n=$((n+1))
if ! grep -q 'MUTANT' "$MUT"; then bad "$n. ⓜ 변이 사본 생성 실패(패턴 불일치)"
else
  SUT="$MUT"; gate "${DEV[@]}" FAKE_CURL_GW=503; got=$?; SUT="$GATE"
  { echo "# 변이 대조 — dev 칸 최종 판정 줄을 지운 사본에서 ⓑ 가 통과하면 시험이 그 변이를 못 죽인 것"; echo "\$ sed 's/FAIL=1/:/'"; grep -n 'MUTANT' "$MUT"; echo "exit=$got (기대 0 = 변이 생존 = 이 시험이 죽인다)" ; printf '%s\n' "$OUT" | grep -E 'gateway|PRESS-GATE' ; } > "$T/mut.txt"
  [ -n "${R634_MUT_OUT:-}" ] && cp "$T/mut.txt" "$R634_MUT_OUT"   # 증거 수집용(리포 밖 경로만 — 시험 중 리포 쓰기 0 유지)
  [ "$got" -eq 0 ] && ok "$n. ⓜ 변이(최종 FAIL 판정 삭제) 사본에서 ⓑ 가 exit 0 = 부정 칸이 그 변이를 죽인다" \
    || { bad "$n. ⓜ 변이 생존 실패 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
fi

# ══ 정적: 하위 호환 칸 수 · 리포 쓰기 0
n=$((n+1))
grep -q 'printf .%s\\t%s\\t%s\\t%s\\t%s\\t%s' "$GATE" && grep -q '"ts","target"' "$GATE" \
  && ok "$n. 허가 줄 = 끝 칸 1개 덧붙임(옛 5칸 호환)" || bad "$n. 허가 줄 칸"
n=$((n+1)); [ "$(git -C "$HERE/../.." status --porcelain)" = "$REAL_BEFORE" ] && ok "$n. 실제 리포 파일 쓰기 0(시험 전후 git status 동일)" || bad "$n. 실제 리포가 바뀌었다"
r634_finish
