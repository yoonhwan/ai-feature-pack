#!/bin/sh
# r2383 pre-push 나노 가드 ft2 갈래 시험 — 반례 ⑪~⑰ · ㉑ · ㉓ · ㉔ · 변이 M4 · M6 · M8.
# 공통 대역 = tests/pre_push_nano_guard_r2383_lib.sh (임시 bare 리포 · 가짜 python3 로 호출 세기) · 실 원격 0 · sleep 0.
# 실행: sh tests/test_pre_push_nano_guard_legacy_r2383.sh
. "$(dirname "$0")/pre_push_nano_guard_r2383_lib.sh"

c11() {   # ⑪ ft2 바뀜 · 위반 0 → rc 0 · guard 1회
  MK_HOOK=$1; d=$(mk "c11$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 1 ] || { echo "  guard $(calls "$d")회(기대 1)"; return 1; }
}
c12() {   # ⑫ 위반 1 → PUSH_DENIED legacy_guard 위반 1건 · rc 1
  MK_HOOK=$1; d=$(mk "c12$2") || return 1
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "PUSH_DENIED legacy_guard 위반 1건 — 첫 줄: core/x.py:1: probe" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 1 ] || { echo "  guard $(calls "$d")회(기대 1)"; return 1; }
}
c13() {   # ⑬ ft2 밖만 바뀜 → guard 0회 · rc 0
  MK_HOOK=$1; d=$(mk "c13$2") || return 1
  printf 'x\n' >> "$d/c/design/harness/note.md"; mkc "$d" "문서만" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c14() {   # ⑭ 나노 아닌 좌석 → rc 0 · guard 0회
  MK_HOOK=$1; d=$(mk "c14$2") || return 1
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c15() {   # ⑮ 새 가지 · origin/main 없음 → 판정 불가 + PUSH_DENIED
  MK_HOOK=$1; d=$(mk "c15$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  g -C "$d/c" update-ref -d refs/remotes/origin/main >/dev/null 2>&1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard merge-base rc=1" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c16() {   # ⑯ 가지 지우는 push(local_sha 0×40) → guard 0회 · rc 0 (DA#54 F1)
  MK_HOOK=$1; d=$(mk "c16$2") || return 1
  pushof "$d" "" HEAD:refs/heads/nano/x || { echo "  준비 실패 $(why "$d")"; return 1; }
  : > "$d/calls"
  pushof "$d" "$NANO" --delete refs/heads/nano/x; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c17() {   # ⑰ 한 push ref 3줄(같은 sha 2 · 다른 sha 1) → guard 2회 (DA#54 F2)
  MK_HOOK=$1; d=$(mk "c17$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 1" || return 1
  printf 'b = 1\n' > "$d/c/feature-pack/fable-team/ft2/b.py"; mkc "$d" "ft2 2" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/a HEAD:refs/heads/nano/b HEAD~1:refs/heads/nano/c; rc=$?
  [ "$rc" = 0 ] || { echo "  rc=$rc $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 2 ] || { echo "  guard $(calls "$d")회(기대 2)"; return 1; }
}
c21() {   # ㉑ 나노 좌석 main·ops/main-base — r1900·r1999 출력 그대로 · guard 0회
  MK_HOOK=$1; d=$(mk "c21$2") || return 1
  pushof "$d" "" HEAD:refs/heads/ops/main-base || { echo "  준비 실패 $(why "$d")"; return 1; }
  mkdir -p "$d/c/design/harness/indices"; printf 'x\n' > "$d/c/design/harness/indices/r1.md"; mkc "$d" "카드" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/ops/main-base; rc=$?
  [ "$rc" = 0 ] || { echo "  ops/main-base rc=$rc(카드 전용 면제 깨짐) $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
  setguard "$d" viol; mkc "$d" "ft2 위반" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/main; rc=$?
  [ "$rc" != 0 ] || { echo "  main push rc=0"; return 1; }
  grep -qF "PUSH_DENIED 나노 좌석 $NANO 의 refs/heads/main push — 착지 = master" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c23() {   # ㉓ archive 는 바이트 정상·rc 42 → 판정 불가 + PUSH_DENIED · guard 0회 (DA#56 H2)
  MK_HOOK=$1; d=$(mk "c23$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  wrap_git "$d" 42
  EXECP="$d/exec"; pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?; EXECP=
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard archive rc=42" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}
c24() {   # ㉔ 풀기는 정상·tar rc 43 → 판정 불가 + PUSH_DENIED · guard 0회 (DA#56 H2)
  MK_HOOK=$1; d=$(mk "c24$2") || return 1
  printf 'a = 1\n' > "$d/c/feature-pack/fable-team/ft2/a.py"; mkc "$d" "ft2 손" || return 1
  wrap_tar "$d" 43
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard tar rc=43" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ "$(calls "$d")" = 0 ] || { echo "  guard $(calls "$d")회(기대 0)"; return 1; }
}

run_case 11 c11
run_case 12 c12
run_case 13 c13
run_case 14 c14
run_case 15 c15
run_case 16 c16
run_case 17 c17
run_case 21 c21
run_case 23 c23
run_case 24 c24

mtest M4 12 '      g=$(guard_once "$local_sha")▸      g=0'
mtest M6 13 '      [ "$k" = 1 ] && continue   # ft2 안 바뀜 = guard 0회▸      :   # 변이 M6 — ft2 안 바뀜도 검사'
mtest M8 17 '  if [ -f "$cache" ]; then cat "$cache"; return; fi▸  if false; then cat "$cache"; return; fi'

lib_done "반례 ⑪~⑰ · ㉑ · ㉓ · ㉔ · 변이 M4 · M6 · M8"
