#!/usr/bin/env bash
# test_stall_scan_lint_cache_r1392.sh — r1392 stall-scan 이 대기 카드 lint 를 «바뀐 카드만» 돌리고(카드 blob oid + lint 판 sha 캐시),
#   한 실행의 lint 는 판정 기한 D 의 절반에서 멈추며, 기한을 넘겨도 그때까지 잰 장은 저장된다.
#   본문 = tests/scripts/test_stall_scan_lint_cache_r1392.py (L1~L7)
#   + 기준판(팩 origin/main) 대조: L1·L2·L3·L4·L7 FAIL · L5·L6 PASS(캐시가 없어도 «다시 잰다» 는 지키는 계약)
#   + 변이 4종(사본 bin 치환 → 그 시험 FAIL → 복구) · 모든 실행은 timeout 70초(칸별 -k 분리 · 하드 룰 22): V1 캐시 조회 무시 · V2 예산 끄기 · V3 on_timeout 저장에서 lint 칸 빼기 · V4 oid 비교 빼기(stem 만)
#   + 회귀(stall 시험 py 12종) — 신판 rc 0 · 예외 하나: test_stall_scan_heartbeat_desk_r1143.py 는 기준판(origin/main)도 rc 1
#     (2026-11-05 실측: test_r3_out_of_window_heartbeat_wording «h? desk 대상 밖 — 현역 팀장 없음» · 이 카드 무관 · 착수 전부터 깨짐) → 신판 rc 1 을 기대값으로 적는다
#   · 70초 상한에 걸린 파일은 «재시도 1회»(하드 룰 12) — test_ft_stall_scan.py 39케이스·test_stall_scan_headline_age.py 31케이스는 부하 35에서 단독 58~66초(같은 파일 기준판도 같다)
#   · STEPS=0 이면 회귀 끔
# 단계 선택(하드 룰 22 — 한 단계 < 4분): bash test_stall_scan_lint_cache_r1392.sh [all|green|base|mut|reg] (기본 all)
# 격리: 임시 리포(bare origin + 체크아웃)·가짜 명부·tmux·mbox·seat-status·lint — 네트워크 0 · 실 루트 0 · 실 좌석 깨우기 0 · 자기 재호출 0(가드 RSG_ACTIVE 가 막는다).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STAGE="${1:-all}"; BASE=""
fail=0; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-t0))초"; t0=$SECONDS; }
want() { case "$STAGE" in all) return 0 ;; *) [ "$STAGE" = "$1" ] ;; esac; }
run_py() {  # $1=bin $2=시험 파일 [$3=-k] — 하드 룰 22: 한 실행 70초 상한(칸별로 쪼개 부른다)
  (ulimit -u 2000; cd "$SC" && R1392_BIN="$1" timeout 70 python3.11 -m pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1)
}
base_bin() {   # 기준판(팩 origin/main) bin — 한 번만 푼다
  [ -n "$BASE" ] && return 0
  mkdir -p "$T/base"; git -C "$PACK" archive origin/main feature-pack/fable-team/harness/kit/fable-team/bin | tar -x -C "$T/base"
  BASE="$T/base/feature-pack/fable-team/harness/kit/fable-team/bin"
}

# ① 신판 green — 칸별(L1~L7) 1실행 = timeout 70초 상한
if want green; then
  rcs=""
  for k in l1 l2 l3 l4 l5 l6 l7; do
    run_py "$KIT" test_stall_scan_lint_cache_r1392.py "test_$k"; rc=$?
    ck "L $k rc=$rc $(grep -Eo '[0-9]+ passed' "$T/py.log")" "$rc"; rcs="$rcs $k=$rc"
  done
  echo "칸별 rc0:$rcs"
  lap green
fi

# ② 기준판(팩 origin/main) — L1·L2·L3·L4·L7 FAIL · L5·L6 PASS
if want base; then
  base_bin
  for k in l1 l2 l3 l4 l7; do run_py "$BASE" test_stall_scan_lint_cache_r1392.py "test_$k"; [ $? -ne 0 ]; ck "기준판 $k FAIL(캐시·예산 없음)" $?; done
  for k in l5 l6; do run_py "$BASE" test_stall_scan_lint_cache_r1392.py "test_$k"; ck "기준판 $k PASS(캐시 없어도 다시 잰다)" $?; done; lap 기준판
fi

# ③ 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다(실 파일 치환 0 · 사본만)
if want mut; then
  cp -Rp "$KIT" "$T/bin"
  sha_before="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" "$KIT/ft_stall_state.py" | awk '{print $1}' | tr '\n' ' ')"
  mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
    cp -p "$KIT/$2" "$T/bin/$2"
    python3 -I - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
    run_py "$T/bin" test_stall_scan_lint_cache_r1392.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
    cp -p "$KIT/$2" "$T/bin/$2"
  }
  mutate "V1 캐시 조회 무시" ft_stall_detect.py 'hit = cache.get(card.stem) if cache is not None and oid and stamp else None' 'hit = None' "l2 or l4"
  mutate "V2 예산 끄기" ft_stall_detect.py 'if budget is not None and not budget():' 'if False:' l1
  mutate "V3 on_timeout 저장에서 lint 칸 빼기" ft_stall_scan.py 'stm.save_seats(state_dir, held[0].st["seats"], held[0].lint_store())' 'stm.save_seats(state_dir, held[0].st["seats"])' l3
  mutate "V4 oid 비교 빼기(stem 만)" ft_stall_detect.py 'hit.get("oid") == oid and hit.get("lint") == stamp' 'hit.get("lint") == stamp' l4
  sha_after="$(shasum "$TRK/ft_stall_detect.py" "$KIT/ft_stall_detect.py" "$KIT/ft_stall_scan.py" "$KIT/ft_stall_state.py" | awk '{print $1}' | tr '\n' ' ')"
  [ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?; lap 변이
fi

# ④ 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일 · 새 시험 모드 100644
if want green || want mut; then
  for n in ft_stall_detect.py ft_stall_scan.py ft_stall_state.py; do
    cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
  done
  for f in "$HERE/test_stall_scan_lint_cache_r1392.sh" "$SC/test_stall_scan_lint_cache_r1392.py"; do
    [ "$(stat -f %Lp "$f")" = 644 ]; ck "새 시험 모드 644 $(basename "$f")" $?
  done
fi

# ⑤ 회귀 — 기존 stall 시험: 신판 rc = 기준판 rc (같은 결과 · 이미 기준판에서 깨지는 시험도 «같으면» 통과)
if want reg && [ "${STEPS:-1}" != 0 ]; then
  for t in test_ft_stall_scan.py test_ft_stall_scan_off_roster.py test_ft_stall_scan_wake_r638.py test_ft_stall_news_cell.py test_stall_heartbeat_promoted_r1154.py test_stall_lead_alert_cron_r1152.py test_stall_scan_headline_age.py test_stall_scan_headline_seats_r1290.py test_stall_scan_lead_heartbeat_r1001.py test_stall_scan_skip_paused_r1307.py test_stall_waiting_cards_ref_tree_r1330.py; do
    run_py "$KIT" "$t"; rc=$?
    if [ "$rc" = 124 ]; then echo "  · 재시도 1 — $t 이 70초 상한에 걸림(부하 · 하드 룰 12)"; run_py "$KIT" "$t"; rc=$?; fi
    ck "회귀 $t rc=$rc $(grep -Eo '[0-9]+ passed' "$T/py.log")" $rc
  done
  run_py "$KIT" test_stall_scan_heartbeat_desk_r1143.py; rc=$?; [ "$rc" = 1 ]; ck "회귀 test_stall_scan_heartbeat_desk_r1143.py rc=$rc (기준판도 rc1 · 위 머리말)" $?
  lap 회귀
fi
echo "FAIL=$fail"; [ "$fail" = 0 ]
