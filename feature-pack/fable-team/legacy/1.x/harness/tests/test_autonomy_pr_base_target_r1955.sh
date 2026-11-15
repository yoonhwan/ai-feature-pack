#!/usr/bin/env bash
# test_autonomy_pr_base_target_r1955.sh — r1955 범위 승인 S 가 PR 의 실제 base(gh baseRefName)로 분류 · 승인 base 결속 (반례 ①②③④⑤⑦⑧ · 변이 M1~M6 대상)
#   격리: 임시 BYZ·팩 리포(로컬 bare origin) · 실 분류기 · 가짜 gh(PATH 앞 · lib/fake_gh_base.sh) · FT_NOW 고정 · 실 상태·실 GitHub 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"; . "$HERE/lib/fake_gh_base.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; fake_gh_base "$T/ghb"; T0=1800000000; S="$T/state"; LOG="$S/autonomy.log"
# ── BYZ 리포: ops/main-base = main + .claude/ 501개(전역 규칙 = forbid) · PR head = ops + 문서 3
mkrepo "$T/byz"; B="$W"; git -C "$B" checkout -q -b ops
mkdir -p "$B/.claude/archives"; for i in $(seq 501); do echo "$i" > "$B/.claude/archives/f$i.md"; done; cm "$B" ops
git -C "$B" push -q origin ops:ops/main-base; git -C "$B" checkout -q -b pr1; mkdir -p "$B/design/r1955"
for i in 1 2 3; do echo "doc $i" > "$B/design/r1955/d$i.md"; done; cm "$B" docs; H1="$(sha "$B" HEAD)"; git -C "$B" fetch -q origin
mkrepo "$T/pack"; P="$W"; mkdir -p "$P/kit/fable-team"; echo x > "$P/kit/fable-team/.keep"; cm "$P" kit; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" FT_HARNESS_ROOT="$P" FT_CRITICAL_OFF=1
onfix() { rm -rf "$S"; mkdir -p "$S"; printf '%s\ton\tA17\n' "$T0" > "$LOG"
  printf '{"mode":"on","since":%s,"event":"A17","until":null,"level":"full"}\n' "$T0" > "$S/autonomy.json"
  printf 'approve-scope S1 A17 %s until=%s max=30 daily=15 classes=docs,ff repos=byz,pack\n' "$T0" "$((T0 + 3600))" >> "$LOG"; }
sa() { out="$(FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" scope-approve "$@" 2>&1)"; rc=$?; }
nw() { find "$S/autonomy-merge-approved" "$S/autonomy-merge-target" -type f 2>/dev/null | grep -c .; }   # 승인·결속 파일 수
land() { out="$(cd "$T" && FT_GH="$T/nogh" "$BASH" "$BIN/ft-merge-land.sh" 1 --approve-sha "$1" --repo "$B" --target "$2" 2>&1)"; rc=$?; }
printf '#!/bin/sh\necho "gh-stub-fail" >&2; exit 1\n' > "$T/nogh"; chmod +x "$T/nogh"

# ① PR base = ops/main-base → ops 기준 분류 = docs · 승인 · 결속 파일 = ops/main-base
onfix; export FAKE_GH_BASE=ops/main-base; sa "$H1" --pr 1 --repo byz
[ "$rc" = 0 ] && has "^SCOPE-OK $H1 class=(docs|ff)" && [ "$(cat "$S/autonomy-merge-target/$H1")" = ops/main-base ] && [ -f "$S/autonomy-merge-approved/$H1" ]; ck "① ops PR → ops 기준 docs(ff) · 승인 + 결속 ops/main-base" $?
cp -R "$S" "$T/state-ops"
# ② 같은 head · PR base = main → main 기준(.claude/ = forbid 거절 · 회귀)
onfix; FAKE_GH_BASE=main sa "$H1" --pr 1 --repo byz
[ "$rc" = 2 ] && has 'FORBID kind=global-rule' && [ "$(nw)" = 0 ]; ck "② main PR → main 기준 forbid 거절 · 쓰기 0" $?
# ③ 팩 PR base = ops/main-base → 허용 목록 밖
onfix; git -C "$P" checkout -q -b px; echo y > "$P/README.md"; cm "$P" px; HP="$(sha "$P" HEAD)"
FAKE_GH_BASE=ops/main-base sa "$HP" --pr 2 --repo pack
[ "$rc" = 2 ] && has '판정 불가 PR base\(PR #2 · pack · 받은 값: ops/main-base\)' && [ "$(nw)" = 0 ]; ck "③ 팩 ops PR → 판정 불가 PR base · 쓰기 0" $?
# ④ gh 실패(rc1) · 빈 base → 판정 불가 · 승인 쓰기 0 · log 줄 그대로
onfix; n0="$(wc -l < "$LOG")"; FAKE_GH_RC=1 sa "$H1" --pr 1 --repo byz
[ "$rc" = 2 ] && has '판정 불가 PR base\(PR #1 · byz · 받은 값: 없음\)' && [ "$(nw)" = 0 ] && [ "$(wc -l < "$LOG")" = "$n0" ]; ck "④ gh 실패 → 판정 불가 · 쓰기 0" $?
FAKE_GH_BASE='' sa "$H1" --pr 1 --repo byz; [ "$rc" = 2 ] && has '판정 불가 PR base' && [ "$(nw)" = 0 ]; ck "④ 빈 base → 판정 불가 · 쓰기 0" $?
# ⑤ env 로 target 을 줘도 PR base(main) 결과 그대로
onfix; FAKE_GH_BASE=main FT_AUTONOMY_TARGET=ops/main-base SCOPE_TARGET=ops/main-base D2_TARGET=ops/main-base sa "$H1" --pr 1 --repo byz
[ "$rc" = 2 ] && has 'FORBID kind=global-rule' && [ "$(nw)" = 0 ]; ck "⑤ env target 무시 → ② 결과 그대로" $?
# 다: origin/<target> 이 로컬에 없으면 판정 불가(fetch 0)
onfix; git -C "$B" update-ref -d refs/remotes/origin/ops/main-base; FAKE_GH_BASE=ops/main-base sa "$H1" --pr 1 --repo byz
[ "$rc" = 2 ] && [ "$(nw)" = 0 ]; ck "다 origin/ops/main-base 없음 → 거절 · 쓰기 0" $?; git -C "$B" fetch -q origin
# M4 상한 계산 기준 = 같은 target(ops 차이 3 → 7초 · main 차이 504 → 18초)
al() { (HERE="$BIN"; STATE="$S"; . "$BIN/ft-autonomy-scope.sh"; SCOPE_REPO="$B"; SCOPE_TARGET="$1"; scope_alarm_secs "$H1"); }
[ "$(al ops/main-base)" = 7 ] && [ "$(al main)" = 18 ]; ck "M4 scope_alarm_secs merge-base = SCOPE_TARGET(ops 7 · main 18)" $?
# ⑦ ① 의 ops 승인 → PR 을 main 으로 retarget → 착지 --target main REJECT · try-auto 다시 = NOOP 아님 판정 불가
rm -rf "$S"; cp -R "$T/state-ops" "$S"; land "$H1" main
[ "$rc" = 1 ] && has '승인 base ops/main-base ≠ 착지 base main'; ck "⑦ ops 승인 · 착지 main → REJECT" $?
out="$(FAKE_GH_BASE=main FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" try-auto "$H1" --pr 1 --repo byz --card "$T/c.md" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has '^TRY-REJECT .*판정 불가 — 승인 base ops/main-base ≠ 지금 PR base main \(retarget 뒤 재사용 0\)' && ! has NOOP; ck "⑦ retarget 뒤 try-auto → NOOP 아님 · 판정 불가 rc≠0" $?
FAKE_GH_BASE=ops/main-base sa "$H1" --pr 1 --repo byz; [ "$rc" = 0 ] && has "^SCOPE-NOOP $H1"; ck "⑦ 대조: base 그대로면 NOOP" $?
land "$H1" ops/main-base; ! has '승인 base'; ck "⑦ 대조: 착지 ops/main-base → 결속 검사 통과(다음 단계로)" $?
# ⑧ 옛 승인(결속 파일 없음) = main · --target main 통과 · ops/main-base REJECT
rm -f "$S/autonomy-merge-target/$H1"; land "$H1" main; ! has '승인 base' && has 'gh pr view 1 실패'; ck "⑧ 옛 승인 + main → 결속 검사 통과(지금 길)" $?
land "$H1" ops/main-base; [ "$rc" = 1 ] && has '승인 base main ≠ 착지 base ops/main-base'; ck "⑧ 옛 승인 + ops/main-base → REJECT" $?
# ⑧' 오빠 손 approve-merge 만(분류 줄 0 · 결속 파일 0) = 분류 base 없음 → 결속 검사 대상 밖(r1687 ops 착지 길 그대로)
mkdir -p "$S/autonomy-merge-approved"; printf 'approve-merge %s A17 %s\n' "$HP" "$T0" | tee -a "$LOG" > "$S/autonomy-merge-approved/$HP"
land "$HP" ops/main-base; ! has '승인 base' && has 'gh pr view 1 실패'; ck "⑧' 오빠 손 승인 + ops/main-base → 결속 검사 통과" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
