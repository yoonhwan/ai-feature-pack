#!/usr/bin/env bash
# test_resource_reclaim_pressure.sh — r500 ft-resource-reclaim.sh 압력 티어(swap ≥85% 면 착지 나노 idle 문턱 30→5분) + «병합 끝 나노» = 가지 착지(ft-landed-check rc0)만.
# 공용 가짜 세계 = lib/fake_reclaim_world.sh(가짜 tmux·nano-close·seat-status·mbox · 임시 HOME · 가짜 팩 리포) · 진짜 tmux kill 0 · 외부 호출 0 · GIT_* env 0.
# 변이: 압력 티어 제거 → ⓐ FAIL · 착지 판정 제거(늘 착지) → ⓑ FAIL.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
SCRIPT_NAME=ft-resource-reclaim.sh
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

bash -n "$BIN/$SCRIPT_NAME" && ok "bash -n $SCRIPT_NAME" || bad "bash -n $SCRIPT_NAME"
cmp -s "$BIN/$SCRIPT_NAME" "$KIT/$SCRIPT_NAME" && ok "키트 사본 cmp 0 $SCRIPT_NAME" || bad "키트 사본 어긋남 $SCRIPT_NAME"

. "$HERE/lib/fake_reclaim_world.sh"

# 팩 리포에 미착지 가지(main 보다 1개 앞) + 시간 초과용 가지 — 착지 가지(nano/land)는 main 조상
git -C "$P" branch nano/land; git -C "$P" branch nano/slow
git -C "$P" checkout -q -b nano/un && echo un > "$P/un.txt" && git -C "$P" add un.txt && git -C "$P" -c user.name=t -c user.email=t@t commit -q -m "un work" && git -C "$P" checkout -q main
SWAP92="total = 9216.00M  used = 8500.00M  free = 716.00M  (encrypted)"
SWAP60="total = 9216.00M  used = 5530.00M  free = 3686.00M  (encrypted)"
printf '#!/bin/bash\ncase "$3" in nano/slow) sleep 10;; esac\nexec bash "%s/ft-landed-check.sh" "$@"\n' "$BIN" > "$F/landed-slow.sh"; chmod +x "$F/landed-slow.sh"
L() { printf '%s\n' "$out" | grep "$1 |"; }
NC() { awk '{print $1}' "$ST/nc.log"; }

suite() {   # $1=시험할 스크립트
  local S="$1" t0
  # ⓐⓑ swap 92% — 착지 나노 idle 6분·카드 진행/ → 문턱 5분 → CLOSED · 미착지 나노 idle 40분 → 미병합 나노 · 닫기 0 · 승인 범위 밖 줄
  setup; addnano "byz-t-nano-land#0" 6 "$T/c/indices/진행/land-card.md"; addnano "byz-t-nano-un#0" 40 "$T/c/indices/진행/un-card.md"
  out="$(FT_SWAPUSAGE="$SWAP92" run "$S" --preventive)"
  has "$(NC)" "byz-t-nano-land#0" "ⓐ swap 92% · 착지 나노 idle 6분(카드 진행/) → nano-close"
  has "$(L 'byz-t-nano-land#0')" "병합 끝 나노 | 나노 세션 정리 2026-10-02 · 워크트리 2026-09-25 | CLOSED" "ⓐ 표 행 = 병합 끝 나노 CLOSED"
  has "$out" "pressure=1 swap=92%" "ⓐ 요약 줄 pressure=1 swap=92%"
  has "$(grep '^PREVENTIVE ' "$T/root/.fable-team/state/reclaim.log")" "pressure=1 swap=92%" "ⓐ reclaim.log 요약 줄에 압력 꼬리"
  hasnt "$(NC)" "byz-t-nano-un#0" "ⓑ 미착지 나노 nano-close 0"
  has "$(L 'byz-t-nano-un#0')" "미병합 나노 | - | HIL(승인 범위 밖: 미병합 나노 — 착지 판정 no)" "ⓑ 미착지 나노 = 승인 범위 밖 줄(착지 판정 no)"
  # ⓐ dry-run 도 같은 판정(닫기 0)
  setup; addnano "byz-t-nano-land#0" 6 "$T/c/indices/진행/land-card.md"
  out="$(FT_SWAPUSAGE="$SWAP92" run "$S" --preventive --dry-run)"
  has "$(L 'byz-t-nano-land#0')" "WOULD-CLOSE(nano-close)" "ⓐ dry-run 착지 나노 WOULD-CLOSE"; eq "$(wc -l < "$ST/nc.log" | tr -d ' ')" 0 "ⓐ dry-run 닫기 0"

  # ⓒ swap 60% — 착지 나노 idle 6분·카드 진행/ → 문턱 30분 → SKIP(지금과 같음)
  setup; addnano "byz-t-nano-land#0" 6 "$T/c/indices/진행/land-card.md"
  out="$(FT_SWAPUSAGE="$SWAP60" run "$S" --preventive)"
  hasnt "$(NC)" "byz-t-nano-land#0" "ⓒ swap 60% · 착지 나노 6분 닫기 0"
  has "$(L 'byz-t-nano-land#0')" "분 < 30분" "ⓒ 문턱 30분 SKIP"; has "$out" "pressure=0 swap=60%" "ⓒ 요약 줄 pressure=0 swap=60%"

  # ⓓ swap 60% — 착지 나노 · 카드 완성/ → 5분(기존 DONE_IDLE_MIN · 회귀 0)
  setup; addnano "byz-t-nano-land#0" 6 "$T/c/indices/완성/land-card.md"
  out="$(FT_SWAPUSAGE="$SWAP60" run "$S" --preventive)"
  has "$(NC)" "byz-t-nano-land#0" "ⓓ 카드 완성/ 착지 나노 6분 → nano-close(압력 없어도 5분)"

  # ⓔ 착지 판정 7초 초과 → 미병합 나노(fail-closed) · 닫기 0 · 사유 «착지 판정 시간 초과»
  setup; addnano "byz-t-nano-slow#0" 40 "$T/c/indices/진행/slow-card.md"; t0=$SECONDS
  out="$(FT_SWAPUSAGE="$SWAP92" FT_LANDED_CHECK="$F/landed-slow.sh" run "$S" --preventive)"
  hasnt "$(NC)" "byz-t-nano-slow#0" "ⓔ 시간 초과 나노 닫기 0"
  has "$(L 'byz-t-nano-slow#0')" "미병합 나노 | - | HIL(승인 범위 밖: 미병합 나노 — 착지 판정 시간 초과)" "ⓔ 표 사유 착지 판정 시간 초과"
  [ $((SECONDS - t0)) -lt 15 ] && ok "ⓔ 7초 상한(전체 $((SECONDS - t0))초)" || bad "ⓔ 7초 상한이 안 걸렸다($((SECONDS - t0))초)"

  # ⓕ swap 측정 실패(빈 줄) → 압력 아님(30분) + WARN 1줄 · 요약 pressure=0 swap=?%
  setup; addnano "byz-t-nano-land#0" 6 "$T/c/indices/진행/land-card.md"
  out="$(FT_SWAPUSAGE="" run "$S" --preventive)"
  hasnt "$(NC)" "byz-t-nano-land#0" "ⓕ 측정 실패 = 압력 아님 → 6분 나노 닫기 0"
  eq "$(printf '%s\n' "$out" | grep -c '^WARN swap 측정 실패')" 1 "ⓕ WARN swap 측정 실패 1줄"
  has "$out" "pressure=0 swap=?%" "ⓕ 요약 줄 pressure=0 swap=?%"

  # ⓖ 가지가 BYZ 루트(커밋 0 · main 조상)와 팩(미착지) 둘 다에 있으면 미병합(하네스 나노 꼴) · 가지 없음도 미병합
  setup; addnano "byz-t-nano-un#0" 40 "$T/c/indices/진행/un-card.md"; addnano "byz-t-nano-ghost#0" 40 "$T/c/indices/진행/ghost-card.md"
  git -C "$T/root" init -q -b main; git -C "$T/root" -c user.name=t -c user.email=t@t commit -q --allow-empty -m byz
  git -C "$T/root" update-ref refs/remotes/origin/main HEAD; git -C "$T/root" branch nano/un
  out="$(FT_SWAPUSAGE="$SWAP92" run "$S" --preventive)"
  hasnt "$(NC)" "byz-t-nano-un#0" "ⓖ BYZ 빈 가지(ancestor)여도 팩 미착지면 닫기 0"
  has "$(L 'byz-t-nano-un#0')" "착지 판정 no)" "ⓖ BYZ+팩 = 팩 판정(no)"
  has "$(L 'byz-t-nano-ghost#0')" "HIL(승인 범위 밖: 미병합 나노 — 착지 판정 가지 없음)" "ⓖ 가지 없음 = 미병합"
  hasnt "$(NC)" "byz-t-nano-ghost#0" "ⓖ 가지 없음 닫기 0"
}

suite "$BIN/$SCRIPT_NAME"
[ "$fail" -eq 0 ] && ok "r500 실물 묶음 전부 통과" || bad "r500 실물 묶음 실패 ${fail}건"

MUT="$T/mut"; mkdir -p "$MUT"
sed 's/^  \[ "\$PRESSURE" != 1 \] || .*$//' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # 압력 티어 제거
saved=$fail; fail=0; suite "$MUT/$SCRIPT_NAME" >"$T/mut1.out"; m1=$fail; fail=$saved
[ "$m1" -gt 0 ] && ok "변이1(압력 티어 제거) → 단언 FAIL ${m1}건" || bad "변이1 이 잡히지 않음(시험이 약하다)"
sed 's/^landed_nano() {/landed_nano() { LN_RC=0; LN_WHY=x; return 0;/' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # 착지 판정 제거(늘 착지)
saved=$fail; fail=0; suite "$MUT/$SCRIPT_NAME" >"$T/mut2.out"; m2=$fail; fail=$saved
[ "$m2" -gt 0 ] && ok "변이2(착지 판정 제거) → 단언 FAIL ${m2}건" || bad "변이2 가 잡히지 않음(시험이 약하다)"

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare 이상"
echo "---- fail=$fail"
[ "$fail" -eq 0 ]
