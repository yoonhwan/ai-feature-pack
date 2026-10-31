#!/usr/bin/env bash
# test_press_gate_step1_cache_r1260_c.sh — r1260 press 게이트 ① 판정 캐시(3/4): 실제 게이트 전체 · ② 이후는 캐시와 무관 · 단계별 초 줄 · bin·kit 같은 판
#   R8 캐시 적중 실행의 ① 밖 출력(②~⑧ 줄 전부)이 캐시 0 실행과 같다 · 적중 실행에 health 200 으로 바꾸면 «✓ worker health 200» 이 새로 나온다(② 이후는 매번 돈다)
#   단계 줄: «단계 초: ⓪ a · ① b(실행|캐시) · ② · ③ · ④ · ⑤ · ⑥⑦⑧» 꼴
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
norm(){ printf '%s\n' "$1" | grep -v -e '캐시 재사용' -e '단계 초' -e 'BTS.md 골격' | grep -vE '미랜딩|세트 밖|세트 포함|착지됨|다른 줄기|선언'; }
RE='단계 초: ⓪ [0-9.]+ · ① [0-9.]+\((실행|캐시)\) · ② [0-9.]+ · ③ [0-9.]+ · ④ [0-9.]+ · ⑤ [0-9.]+ · ⑥⑦⑧ [0-9.]+'
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
mkcase r8; runbin "$GATE"; oa="$OUT"
runbin "$GATE"; ob="$OUT"; hit && ok "R8 둘째 실행 ① 캐시 재사용" || bad "R8 둘째 실행 적중 아님"
GENV="FT_PRESS_GATE_CACHE_SEC=0"; runbin "$GATE"; oc="$OUT"; GENV=""
[ -n "$(norm "$ob")" ] && [ "$(norm "$ob")" = "$(norm "$oc")" ] && ok "R8 적중 실행의 ② 이후 출력 = 캐시 0 실행" || { bad "R8 ② 이후 출력 다름"; diff <(norm "$ob") <(norm "$oc") | head -8; }
CURL_CODE=200; runbin "$GATE"; CURL_CODE=000
{ hit && has "✓ worker health 200" && ! has "worker health=000"; } && ok "R8 적중 + health 200 → ③ 이 새로 돈다" || bad "R8 ③ 이 캐시에 묶임"
printf '%s\n' "$oa" | grep -qE "$RE" && printf '%s\n' "$oa" | grep -q '① [0-9.]*(실행)' && ok "단계 줄(실행)" || bad "단계 줄(실행) 꼴"
printf '%s\n' "$ob" | grep -qE "$RE" && printf '%s\n' "$ob" | grep -q '① [0-9.]*(캐시)' && ok "단계 줄(캐시)" || bad "단계 줄(캐시) 꼴"
cmp -s "$GATE" "$KIT/ft-press-gate.sh" && ok "bin·kit cmp0" || bad "bin·kit 내용 다름"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
