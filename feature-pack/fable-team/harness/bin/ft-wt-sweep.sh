#!/usr/bin/env bash
# ft-wt-sweep.sh [--dry-run]  — 닫힌 나노의 워크트리 정리 계획(.fable-team/state/wt-clean/<seat>.sh)을 «세션이 사라진 뒤» 실행한다.
#   하네스 0.5 행 2 r2 (DA-harness-0.5-row2-r1 조건 1): close 는 계획을 «생성만» 하고, 실행은 이 sweep(또는 close --kill 성공 뒤)에서만.
#   계획 스크립트 자신이 가드(계보 세션 0 · cwd 보유 프로세스 0 · branch nano/* · HEAD=branch 도달성 · 실작업물 0 · ignored 보관)와 원장 표식을 담당한다.
#   결과: cleaned|none → 계획을 <seat>.sh.done 으로 · skipped:좌석/cwd → WAIT(다음 sweep) · 그 외 skipped → [HIL] 1줄(호출자가 mbox 로 올린다).
#   실행 위치: master 워크트리(원장은 계획에 절대경로로 박혀 있다). FT_WT_AUTOCLEAN=0 이면 아무것도 실행하지 않는다.
set -uo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || { echo "FT_WT_AUTOCLEAN=0 — sweep 실행 안 함"; exit 0; }
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
DIR="${FT_WT_CLEAN_DIR:-$ROOT/.fable-team/state/wt-clean}"
n=0; c=0; w=0; h=0
for plan in "$DIR"/*.sh; do
  [ -f "$plan" ] || continue
  n=$((n+1)); seat="$(basename "$plan" .sh)"
  if [ "$DRY" = 1 ]; then echo "DRY $seat — $plan"; continue; fi
  res="$(/bin/bash "$plan" 2>&1 | tee "$plan.log" | tail -1)"
  case "$res" in
    cleaned*|none) c=$((c+1)); mv "$plan" "$plan.done"; echo "OK   $seat wt=$res";;
    skipped:좌석*|skipped:cwd*) w=$((w+1)); echo "WAIT $seat ${res#skipped:}";;
    skipped:*) h=$((h+1)); echo "[HIL] ${res#skipped:} · 스크립트 $plan";;
    *) h=$((h+1)); echo "[HIL] 실행 실패(${res:-출력 없음}) · 스크립트 $plan (로그 $plan.log)";;
  esac
done
echo "sweep 계획 $n · cleaned/none $c · wait $w · hil $h"
