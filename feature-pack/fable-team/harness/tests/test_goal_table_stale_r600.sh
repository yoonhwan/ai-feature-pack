#!/usr/bin/env bash
# test_goal_table_stale_r600.sh — 골 표 가드가 «옛 판 골 표 복붙» 을 통과시키지 않는다 (r600).
#   ⓐ 마커 sha = 지금 ref 보다 첫 부모 13커밋 앞 · 골 칸 같음 → rc3 «REJECT 골 표 낡음 — …첫 부모 13커밋 앞(상한 12) · ft-goal-table.sh 를 다시 돌려 붙인다»
#   ⓑ 마커 sha = 지금 ref → GOAL-OK   ⓒ 12커밋 앞 → GOAL-OK(렌더~발신 사이 main 이동 허용)
#   ⓓ 마커 sha 가 지금 ref 첫 부모 줄기에 없음(다른 가지) → rc3 «… 첫 부모 줄기에 없다»
#   ⓔ block_only(뉴스·매거진)도 같은 규칙 · 새로 렌더한 판 = GOAL-OK(회귀 0)
# 픽스처 = mktemp 임시 git 리포 1(첫 부모 커밋 17 + 다른 가지 1) · 실 리포·실 원격·실 좌석·외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="${R600_REPO:-$HERE/../..}"
TOOL="$REPO/harness/bin/ft_goal_table.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
CPATH=design/planner/AUTONOMY-GOAL-A6-20261018.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner"; git -C "$R" init -q -b main
canon_txt() {
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  for i in 1 2 3 4 5 6; do printf '| goal-%s-test | 팀%s | 착지 sha |\n' "$i" "$i"; done
}
ledger_txt() {
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
  for i in 1 2 3 4 5 6; do printf '| 원장 글자 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "$1"; }
canon_txt > "$R/$CPATH"; ledger_txt > "$R/$LPATH"; commit c0; git -C "$R" tag c0
for i in $(seq 1 16); do echo "$i" > "$R/other$i"; commit "c$i"; git -C "$R" tag "c$i"; done
git -C "$R" update-ref refs/remotes/origin/main HEAD
TIP="$(git -C "$R" rev-parse origin/main)"; C3="$(git -C "$R" rev-parse c3)"; C4="$(git -C "$R" rev-parse c4)"
git -C "$R" checkout -q -b side c0; echo side > "$R/sidefile"; commit side; SIDE="$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q main
[ "$(git -C "$R" rev-list --first-parent --count "$C3..origin/main")" = 13 ] && [ "$(git -C "$R" rev-list --first-parent --count "$C4..origin/main")" = 12 ] \
  && ok "⓪ 픽스처: c3 13커밋 앞 · c4 12커밋 앞" || bad "⓪ 픽스처 거리"

render_at() {  # <ref> → 골 표 블록(마커 = 그 ref 판)
  env -u FT_ROOT -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="gitref:$1:$CPATH" FT_GOAL_A6_LEDGER="gitref:$1:$LPATH" \
    FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" 2>&1
}
check_body() {  # <본문> [--block-only] — 정본 출처 = origin/main(지금 ref)
  OUT="$(printf '%s\n' "$1" | env -u FT_ROOT -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="gitref:origin/main:$CPATH" \
    FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check ${2:-} 2>&1)"; RC=$?
}
COORD='골좌표: 1 — goal-1-test'
git -C "$R" tag r3 "$C3" >/dev/null 2>&1; git -C "$R" tag r4 "$C4" >/dev/null 2>&1; git -C "$R" tag rtip "$TIP" >/dev/null 2>&1; git -C "$R" tag rside "$SIDE" >/dev/null 2>&1
if [ -n "$SIDE" ] && ! git -C "$R" merge-base --is-ancestor "$SIDE" origin/main; then ok "⓪ 픽스처: 다른 가지 = 첫 부모 줄기에 없음(${SIDE:0:10})"; else bad "⓪ 픽스처: 다른 가지($SIDE)"; fi
B3="$(render_at r3)"; B4="$(render_at r4)"; BTIP="$(render_at rtip)"; BSIDE="$(render_at rside)"
case "$(printf '%s\n' "$B3" | head -1)" in "★골 표 A6 (r3@${C3:0:10} · "*) ok "⓪ 렌더: 마커 = 그 판 sha10(${C3:0:10})";; *) bad "⓪ 마커 :: $(printf '%s\n' "$B3" | head -1)";; esac

# ⓐ 13커밋 앞 + 골 칸 같음 → «골 표 낡음» rc3
check_body "$B3"$'\n'"$COORD"
[ "$RC" = 3 ] && case "$OUT" in *"REJECT 골 표 낡음 — 마커 ${C3:0:10} 은 지금 origin/main(${TIP:0:10})보다 첫 부모 13커밋 앞(상한 12) · ft-goal-table.sh 를 다시 돌려 붙인다"*) true;; *) false;; esac \
  && ok "ⓐ 13커밋 앞 옛 표 복붙 → rc3 낡음(도구 다시 돌려 붙이라)" || bad "ⓐ rc=$RC :: $OUT"
# ⓑ 마커 = 지금 ref → GOAL-OK
check_body "$BTIP"$'\n'"$COORD"
[ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK n=1'*) true;; *) false;; esac && ok "ⓑ 지금 판 → GOAL-OK n=1" || bad "ⓑ rc=$RC :: $OUT"
# ⓒ 12커밋 앞(상한 경계) → GOAL-OK
check_body "$B4"$'\n'"$COORD"
[ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK n=1'*) true;; *) false;; esac && ok "ⓒ 12커밋 앞(경계) → GOAL-OK" || bad "ⓒ rc=$RC :: $OUT"
# ⓓ 다른 가지(첫 부모 줄기에 없음) → rc3
check_body "$BSIDE"$'\n'"$COORD"
[ "$RC" = 3 ] && case "$OUT" in *"REJECT 골 표 낡음 — 마커 sha 가 origin/main 첫 부모 줄기에 없다"*) true;; *) false;; esac \
  && ok "ⓓ 다른 가지 판 → rc3 첫 부모 줄기에 없다" || bad "ⓓ rc=$RC :: $OUT"
# ⓔ block_only(뉴스·매거진) — 같은 규칙 · 새로 렌더한 판 = GOAL-OK
check_body "$B3" --block-only
[ "$RC" = 3 ] && case "$OUT" in *'REJECT 골 표 낡음'*) true;; *) false;; esac && ok "ⓔ1 block_only 옛 판 → rc3 낡음" || bad "ⓔ1 rc=$RC :: $OUT"
check_body "$BTIP" --block-only
[ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK block-only'*) true;; *) false;; esac && ok "ⓔ2 block_only 새 판 → GOAL-OK(회귀 0)" || bad "ⓔ2 rc=$RC :: $OUT"
# ⓔ3 파일 정본(FT_GOAL_A6_MD=파일)은 신선도 검사 생략 — 옛 판 그대로 통과
BFILE="$(env -u FT_ROOT -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="$R/$CPATH" FT_GOAL_A6_LEDGER="$R/$LPATH" FT_GOAL_REPO="$R" python3 "$TOOL" 2>&1)"
OUT="$(printf '%s\n%s\n' "$BFILE" "$COORD" | env -u FT_ROOT -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="$R/$CPATH" FT_GOAL_A6_LEDGER="$R/$LPATH" FT_GOAL_REPO="$R" python3 "$TOOL" check 2>&1)"; RC=$?
[ "$RC" = 0 ] && case "$OUT" in *'GOAL-OK n=1'*) true;; *) false;; esac && ok "ⓔ3 파일 정본 = 신선도 검사 생략(변경 0)" || bad "ⓔ3 rc=$RC :: $OUT"
# ⓔ4 git 이 죽으면 fail-closed rc3 (삼키기 0)
OUT="$(printf '%s\n%s\n' "$BTIP" "$COORD" | env -u FT_ROOT FT_GOAL_A6_MD="gitref:nosuchref:$CPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check 2>&1)"; RC=$?
[ "$RC" = 3 ] && case "$OUT" in *'REJECT 골 표 신선도 확인 실패'*) true;; *) false;; esac && ok "ⓔ4 git 실패 → rc3 신선도 확인 실패(통과 0)" || bad "ⓔ4 rc=$RC :: $OUT"

echo "== test_goal_table_stale_r600: fail=$fail"; [ "$fail" = 0 ]
