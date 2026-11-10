#!/usr/bin/env bash
# test_merge_land_baseline_paths_r1132.sh — r1132: 기준판을 고정 sha 로 꺼내는 merge_land 시험이 «경로가 달라도» 참이다.
#   R5 deny_stale·doc_auto_merge 를 /var(논리) 경로와 /private/var(실경로) 사본에서 각각 → rc0 · SKIP 0
#   R6 git 아닌 사본(git archive 꼴 = .git 없음) → 기준판 칸만 SKIP 1줄 · PASS 는 1칸만 준다 · rc0
#   변이 PFX 의 pwd -P 제거 → /var 사본에서 «기준판을 못 꺼냄» rc≠0 (= 실경로 맞춤이 판정을 흔든다)
#   사본 = 임시 폴더(mktemp) · git 사본은 clone --shared(객체 공유 · 원격 0) — 실 원격·실 push 0 · 자기 재호출 0 · 고정 sleep 0
#   상한: 하위 시험은 한 단계에 3개까지 동시 · 각 timeout 60 · 이 시험 단독 70초 안(하드 룰 22) — R1~R4·R7 lint 칸은 test_test_reentry_lint.sh ⓜ
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"; H="$(cd "$HERE/.." && pwd -P)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)" || { echo "FAIL 이 시험은 git 사본에서만 돈다(판정 불가)"; exit 2; }
fail=0; t0=$SECONDS
ck() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fail=$((fail+1)); fi; }   # ck <rc> <이름> — rc 는 조건 바로 뒤 r=$? 로 잡는다(이름 속 $(…) 가 $? 를 바꾼다)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; TP="$(cd "$T" && pwd -P)"
case "$T" in /var/*) ;; *) echo "SKIP /var 논리 경로 아님(TMPDIR=$T) — R5 의 두 경로가 같아진다";; esac

# 사본 — git(c: clone --shared + 지금 harness 폴더 그대로) · 비 git(a: harness 폴더만)
git clone -q --shared --no-checkout "$TOP" "$T/c" || { echo "FAIL git 사본 못 만듦"; exit 1; }
mkdir -p "$T/c/feature-pack/fable-team" "$T/a/fable-team" && cp -R "$H" "$T/c/feature-pack/fable-team/harness" && cp -R "$H" "$T/a/fable-team/harness" || { echo "FAIL 사본 복사"; exit 1; }
LT="$T/c/feature-pack/fable-team/harness/tests"; RT="$TP/c/feature-pack/fable-team/harness/tests"; AT="$T/a/fable-team/harness/tests"
python3 - "$LT/test_merge_land_doc_auto_merge_r1121.sh" "$LT/mut_pfx.sh" <<'PY' || { echo "FAIL 변이 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old = 'PFX="$(cd "$HERE/.." && pwd -P)"'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, 'PFX="$(cd "$HERE/.." && pwd)"', 1))
PY
echo "단계 초: 사본 $((SECONDS-t0))s"

run() { ( cd "$T" && timeout 60 bash "$2" > "$T/$1.out" 2>&1; echo $? > "$T/$1.rc" ) & }   # run <이름> <시험 경로> — 백그라운드 1개
rcof() { cat "$T/$1.rc" 2>/dev/null || echo none; }
skips() { grep -c '^SKIP 기준판' "$T/$1.out" | tr -d ' '; }
passes() { grep -c '^PASS' "$T/$1.out" | tr -d ' '; }

# 1단계 — deny_stale 세 사본(/var · /private/var · 비 git)
s=$SECONDS; run dl "$LT/test_merge_land_deny_stale.sh"; run dr "$RT/test_merge_land_deny_stale.sh"; run da "$AT/test_merge_land_deny_stale.sh"; wait
echo "단계 초: deny_stale 3사본 $((SECONDS-s))s"
[ "$(rcof dl)" = 0 ] && [ "$(skips dl)" = 0 ]; r=$?; ck "$r" "ⓒ R5 deny_stale /var 경로 사본 rc0 · 기준판 칸 돎(SKIP 0) :: rc=$(rcof dl) $(grep -m1 '^FAIL' "$T/dl.out")"
[ "$(rcof dr)" = 0 ] && [ "$(skips dr)" = 0 ]; r=$?; ck "$r" "ⓒ R5 deny_stale /private/var 실경로 사본 rc0 · SKIP 0 :: rc=$(rcof dr) $(grep -m1 '^FAIL' "$T/dr.out")"
[ "$(rcof da)" = 0 ] && [ "$(skips da)" = 1 ] && [ "$(passes da)" = "$(( $(passes dl) - 1 ))" ]
r=$?; ck "$r" "ⓒ R6 git 아닌 사본 → 기준판 칸만 SKIP 1줄 · PASS $(passes da) = $(passes dl) - 1 · rc0 :: rc=$(rcof da)"

# 2단계 — doc_auto_merge 두 사본 + 변이(pwd -P 제거 · /var 경로)
s=$SECONDS; run ml "$LT/test_merge_land_doc_auto_merge_r1121.sh"; run mr "$RT/test_merge_land_doc_auto_merge_r1121.sh"; run mu "$LT/mut_pfx.sh"; wait
echo "단계 초: doc_auto_merge 2사본 + 변이 $((SECONDS-s))s"
[ "$(rcof ml)" = 0 ] && [ "$(skips ml)" = 0 ]; r=$?; ck "$r" "ⓒ R5 doc_auto_merge /var 경로 사본 rc0 · SKIP 0 :: rc=$(rcof ml) $(grep -m1 '^FAIL' "$T/ml.out")"
[ "$(rcof mr)" = 0 ] && [ "$(skips mr)" = 0 ]; r=$?; ck "$r" "ⓒ R5 doc_auto_merge /private/var 실경로 사본 rc0 · SKIP 0 :: rc=$(rcof mr) $(grep -m1 '^FAIL' "$T/mr.out")"
case "$T" in
  /var/*) [ "$(rcof mu)" != 0 ] && grep -q '기준판을 못 꺼냄' "$T/mu.out"; r=$?; ck "$r" "ⓒ 변이(PFX pwd -P 제거) → /var 사본 «기준판을 못 꺼냄» rc≠0 = 시험이 잡음 :: rc=$(rcof mu)";;
  *) echo "SKIP 변이 칸 — /var 논리 경로 아님";;
esac

echo "초: 전체 $((SECONDS-t0))"
echo "---- fail=$fail"; [ "$fail" -eq 0 ]
