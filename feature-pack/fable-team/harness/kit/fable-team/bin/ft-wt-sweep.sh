#!/usr/bin/env bash
# ft-wt-sweep.sh [--dry-run]  — 닫힌 나노의 워크트리 정리 계획(.fable-team/state/wt-clean/<seat>.sh)을 «세션이 사라진 뒤» 실행한다.
#   하네스 0.5 행 2 r2~r4 (DA r1 조건 1 · DA r2 조건 2 · DA r3 MAJOR N1): close 는 계획을 «생성만» 하고, 실행은 이 sweep(또는 close --kill 성공 뒤)에서만.
#   ★호출처(r3 배선)★: ft-tick.sh 의 pass() 가 매 루프(60s) `sweep_wt()` 로 이 스크립트를 부른다(FT_TICK_WT_SWEEP=0 으로 끔). 수동 호출도 같은 진입점.
#   계획 스크립트 자신이 가드(계보 세션 자기 포함 0 · cwd 보유 프로세스 0 · branch nano/* · HEAD=branch 도달성 · 실작업물 0 · ignored 보관 · 도구 실패=skipped)와 원장 표식을 담당한다.
#   결과: cleaned|none → <seat>.sh.done · skipped:좌석/cwd → WAIT(제자리 · 다음 sweep) · 그 외 skipped → ★<seat>.sh.hil 로 이동 + [HIL] 1줄 «1회»★(호출자가 mbox 로 올린다 ·
#   사람이 .hil 을 .sh 로 되돌리면 재시도). 계획 1건당 FT_WT_PLAN_TIMEOUT(기본 120s) — 초과는 skipped:timeout 으로 .hil(MINOR b).
#   ★r-wt-sweep-route-timeout★ ①초과는 rc 124 정직(perl 이 자기 TERM 을 무시) ②baton 머리줄이 로그에 있는 «삭제 단계» 초과는 WAIT + <계획>.tmo 연속 카운트(FT_WT_SWEEP_TMO_MAX=3 회면 HIL)
#   ③pass 1회에 계획 FT_WT_SWEEP_MAX(기본 1)건만(좌석·cwd WAIT 는 안 센다) ④[HIL] 줄은 «seat=<좌석>» 을 담는다(호출자가 팀 master 로 라우팅).
#   실행 위치 무관(원장·워크트리는 계획에 절대경로로 박혀 있다). FT_WT_AUTOCLEAN=0 이면 아무것도 실행하지 않는다.
set -uo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || { echo "FT_WT_AUTOCLEAN=0 — sweep 실행 안 함"; exit 0; }
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
DIR="${FT_WT_CLEAN_DIR:-${ROOT:-$WT}/.fable-team/state/wt-clean}"
TMO="${FT_WT_PLAN_TIMEOUT:-120}"
MAX="${FT_WT_SWEEP_MAX:-1}"          # pass 1회에 실행하는 계획 수(좌석 WAIT 는 세지 않는다) — 틱 pass 를 계획 N×상한 동안 붙잡지 않는다
TMO_MAX="${FT_WT_SWEEP_TMO_MAX:-3}"  # 삭제 단계 초과가 «연속» 이 횟수가 되면 사람 판정(HIL)
BATON_HDR='워크트리 정리 — Archive'   # baton wt-clean 머리줄 — 이게 로그에 있으면 계획이 가드를 지나 «삭제 단계» 까지 갔다
# 계획 1건을 타임아웃 아래 실행 — perl alarm(macOS 기본엔 timeout(1) 이 없다). 새 프로세스 그룹으로 띄워 초과 시 «그룹 전체»(bash·tar·baton 자식) TERM. rc 는 계획의 것 · 초과 = 124.
#   perl 자신이 그 그룹의 리더라 TERM 을 무시해야 exit 124 까지 간다(안 그러면 자기도 죽어 rc 143 = «실행 실패» 오분류).
run_plan() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "$TMO" /bin/bash "$1"; }
HB="$(dirname "$0")/ft-hil.sh"  # R83: 사람 ! 실행 안내 = 짧은 링크(`! bash /tmp/h<N>`) — 옆의 ft-hil.sh 가 없거나 실패면 지금 문구 그대로 + WARN
hilmsg() { local m=""; command -v "$HB" >/dev/null 2>&1 && m="$("$HB" --add "$1" 2>/dev/null | tail -1)"; [ -n "$m" ] && echo "$m" || { echo "WARN ft-hil 실패 — 경로 안내로 후퇴" >&2; echo "스크립트 $1"; }; }
n=0; c=0; w=0; h=0; d=0; ran=0
for plan in "$DIR"/*.sh; do
  [ -f "$plan" ] || continue
  seat="$(basename "$plan" .sh)"
  if [ "$DRY" = 1 ]; then n=$((n+1)); echo "DRY $seat — $plan"; continue; fi
  if [ "$ran" -ge "$MAX" ]; then d=$((d+1)); continue; fi
  n=$((n+1))
  run_plan "$plan" > "$plan.log" 2>&1; rc=$?; res="$(tail -1 "$plan.log")"   # 파일로 받는다 — 파이프 캡처는 고아 자식이 잡고 있으면 타임아웃 뒤에도 안 돌아온다
  [ "$rc" -ne 124 ] || res="skipped:timeout ${TMO}s"
  case "$res" in skipped:좌석*|skipped:cwd*) ;; *) ran=$((ran+1));; esac
  tmo="$plan.tmo"
  if [ "$rc" -eq 124 ] && grep -qF -- "$BATON_HDR" "$plan.log"; then
    # 삭제 단계 초과 = 사람 판정이 아니라 재시도(계획은 재실행 안전 — 반쯤 지워졌으면 baton 이 이어서 지운다). 연속 TMO_MAX 회면 HIL.
    t=$(( $(cat "$tmo" 2>/dev/null || echo 0) + 1 ))
    if [ "$t" -ge "$TMO_MAX" ]; then h=$((h+1)); rm -f "$tmo"; mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat 삭제 단계 시간 초과 ${t}회 연속(${TMO}s) · $(hilmsg "$plan.hil") (로그 $plan.log)"
    else w=$((w+1)); echo "$t" > "$tmo"; echo "WAIT $seat 삭제 단계 시간 초과 ${t}/${TMO_MAX} — 다음 sweep 재시도"; fi
    continue
  fi
  rm -f "$tmo"   # 초과 외의 결과는 «연속» 을 끊는다
  case "$res" in
    cleaned*|none) c=$((c+1)); mv "$plan" "$plan.done"; echo "OK   $seat wt=$res";;
    skipped:좌석*|skipped:cwd*) w=$((w+1)); echo "WAIT $seat ${res#skipped:}";;
    skipped:*) h=$((h+1)); mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat ${res#skipped:} · $(hilmsg "$plan.hil")";;
    *) h=$((h+1)); mv "$plan" "$plan.hil"; echo "[HIL] seat=$seat 실행 실패(rc=$rc: ${res:-출력 없음}) · $(hilmsg "$plan.hil") (로그 $plan.log)";;
  esac
done
echo "sweep 계획 $n · cleaned/none $c · wait $w · hil $h$([ "$d" -gt 0 ] && echo " · 이월 $d")"
