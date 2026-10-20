#!/usr/bin/env bash
# test_wt_clean_plan_single_runner_lock.sh — 카드 r608: 닫기(ft-nano-close `_wt_clean_run`)와 주기 정리(ft-wt-sweep)가
#   «같은 정리 계획»을 동시에 돌려 같은 `<계획>.log` 를 잘라 써 결과 줄이 깨지고(«ed(ignored …») 성공이 «실행 실패» [HIL] 로 오알림되던 것.
#   고침 = 계획 1개당 실행자 1명(<계획>.run.lock 디렉터리 + pid) · 낡은 잠금(pid 죽음)은 걷어내고 실행.
# 픽스처 = mktemp scratch 안의 «스텁 계획 .sh» + 스텁 상태 폴더 — 실제 워크트리·실 나노 좌석·실 mbox·실 baton·실 상태 폴더 0.
# 두 실행자 모두 «실 스크립트의 함수»를 그대로 뽑아 쓴다: 닫기 = ft-nano-close.sh 의 `_wt_clean_run`(PLAN 변수) · sweep = 실 ft-wt-sweep.sh 실행.
# base 대조 = FT_KIT_BIN=<옛 판 폴더> 로 돌린다(같은 시험 · 같은 픽스처).
# 축: ⓐ 같은 계획 동시 실행 → 고친 판 = 한쪽만 실행 · 다른 쪽 «다른 실행자가 돌리는 중» · `.sh.done` 1 · [HIL] 0
#        (base 판 = 로그 깨짐 · [HIL] 1)  ⓑ 잡은 실행자가 죽어 잠금만 남음 → 다음 sweep 이 걷어내고 실행(사유 1줄)
#        ⓒ 진짜 실패 계획(skipped:원장 락 실패) → 지금처럼 [HIL] 1(회귀 0)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${FT_KIT_BIN:-$HERE/../../harness/kit/fable-team/bin}"
SWEEP="$KIT/ft-wt-sweep.sh"
CLOSE="$KIT/ft-nano-close.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hil"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SWEEP" && bash -n "$CLOSE" && ok "bash -n sweep·close" || bad "bash -n"
# 함수 3개(plan_lock·plan_unlock·_wt_clean_run)를 «중괄호 균형»으로 뽑는다(한 줄짜리 함수도 정확히 · 중복 0)
CLOSE_FN="$(awk '
  /^(plan_lock|plan_unlock|_wt_clean_run)\(\) \{/ { inb=1; depth=0 }
  inb { print; o=gsub(/\{/,"{"); c=gsub(/\}/,"}"); depth+=o-c; if (depth<=0) inb=0 }
' "$CLOSE")"
case "$CLOSE_FN" in *plan_lock*) ok "닫기 판에 plan_lock 추출";; *) bad "닫기 판에 plan_lock 없음(base 판 = 정상)";; esac

# 닫기 경로 실행자 = «그 함수만» 뽑아 실행(실 ft-nano-close 전체 호출 0 · 실 명부·원장 0)
close_run() { ( PLAN="$1" bash -c "set -uo pipefail"$'\n'"$CLOSE_FN"$'\n''_wt_clean_run' 2>&1 ); }
# 주기 정리 실행자 = 실 ft-wt-sweep.sh(격리 디렉터리만 · 상한 1초 · cwd scratch)
sweep_run() { ( cd "$T" && env FT_WT_CLEAN_DIR="$1" FT_WT_PLAN_TIMEOUT="${2:-5}" HIL_DIR="$T/hil" HIL_CLIP=0 bash "$SWEEP" 2>&1 ); }

# ⓐ-픽스처: 같은 계획을 두 실행자가 «동시에». 계획 = 처음 부르면 앞토막을 쓰고 잠깐 멈췄다가 뒷토막(«cleaned(…)»)을 쓰고,
#   두 번째 호출이면 «none». base 판이면 둘째가 로그를 잘라 써 첫 줄이 깨지고 판정기가 «실행 실패» 로 [HIL] 을 올린다.
prep_race() { # <디렉터리> <좌석>
  local d="$1" s="$2"; rm -rf "$d"; mkdir -p "$d"
  cat > "$d/$s.sh" <<EOF
if [ ! -e "$d/marked" ]; then
  touch "$d/marked"; printf 'cleaned(보관 288'
  sleep 2
  printf '파일 보관) · 이름 바꿈 → %s\n' "$s"
else
  echo none
fi
EOF
}

echo "== ⓐ 같은 계획을 닫기 경로와 sweep 이 동시에 → 한쪽만 실행 · 다른 쪽 «다른 실행자가 돌리는 중» · .done 1 · [HIL] 0"
D="$T/a"; prep_race "$D" 'ra#0'
( close_run "$D/ra#0.sh" > "$T/a.close" 2>&1 ) & cp1=$!
sleep 0.4
sweep_out="$(sweep_run "$D")"
wait $cp1; close_out="$(cat "$T/a.close")"
both="$close_out"$'\n'"$sweep_out"
hasnt "$both" '[HIL]' "ⓐ [HIL] 0(오알림 없음)"
hasnt "$both" '실행 실패' "ⓐ «실행 실패» 0"
has "$both" '다른 실행자가 돌리는 중' "ⓐ 다른 쪽 «다른 실행자가 돌리는 중» 1줄"
[ "$(ls "$D"/*.sh.done 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "ⓐ 결과 .sh.done 1" || bad "ⓐ .sh.done = $(ls "$D" 2>/dev/null | tr '\n' ' ')"
log1="$(tail -1 "$D/ra#0.sh.log" 2>/dev/null | tr -d '\000' || true)"
case "$log1" in cleaned*|none) ok "ⓐ 로그 마지막 줄 온전(«${log1:0:40}»)";; *) bad "ⓐ 로그 마지막 줄 깨짐: «${log1}»";; esac
grep -q 'ed(ignored' "$D/ra#0.sh.log" 2>/dev/null && bad "ⓐ 로그에 «ed(ignored…» 잔재" || ok "ⓐ «ed(ignored…» 잔재 0"
[ ! -e "$D/ra#0.sh.run.lock" ] && ok "ⓐ 끝난 뒤 잠금 없음" || bad "ⓐ 잠금 남음"

echo "== ⓑ 잠금을 쥔 실행자가 죽고 pid 만 남음 → 다음 sweep 이 낡은 잠금으로 보고 걷어낸 뒤 실행(사유 1줄)"
D="$T/b"; rm -rf "$D"; mkdir -p "$D/bb#0.sh.run.lock"
printf 'echo cleaned\n' > "$D/bb#0.sh"
printf '999999\n' > "$D/bb#0.sh.run.lock/pid"
out="$(sweep_run "$D")"
has "$out" '낡은 잠금 걷음' "ⓑ 낡은 잠금 사유 1줄"
[ -f "$D/bb#0.sh.log" ] && [ "$(tail -1 "$D/bb#0.sh.log")" = cleaned ] && ok "ⓑ 걷어낸 뒤 실제 실행(로그 cleaned)" || bad "ⓑ 실행 로그: «$(tail -1 "$D/bb#0.sh.log" 2>/dev/null)»"
[ -f "$D/bb#0.sh.done" ] && ok "ⓑ .sh.done" || bad "ⓑ .sh.done 없음: $(ls "$D" | tr '\n' ' ')"
hasnt "$out" '[HIL]' "ⓑ [HIL] 0"
[ ! -e "$D/bb#0.sh.run.lock" ] && ok "ⓑ 낡은 잠금 지움" || bad "ⓑ 낡은 잠금 남음"

echo "== ⓒ 진짜 실패 계획(skipped:원장 락 실패) → 지금처럼 [HIL] 1(회귀 0)"
D="$T/c"; rm -rf "$D"; mkdir -p "$D"
printf 'echo "skipped:원장 락 실패"\n' > "$D/cc#0.sh"
out="$(sweep_run "$D")"
has "$out" '[HIL] seat=cc#0 원장 락 실패' "ⓒ [HIL] 1"
[ -f "$D/cc#0.sh.hil" ] && ok "ⓒ 계획 .sh.hil 이동" || bad "ⓒ .sh.hil 없음: $(ls "$D" | tr '\n' ' ')"
[ ! -e "$D/cc#0.sh.run.lock" ] && ok "ⓒ 잠금 없음(실패 판정 뒤 정리)" || bad "ⓒ 잠금 남음"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
