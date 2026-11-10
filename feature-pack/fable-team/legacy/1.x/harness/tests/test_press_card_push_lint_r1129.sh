#!/usr/bin/env bash
# test_press_card_push_lint_r1129.sh — tester press 카드 push lint(r1129) 반례 R1~R7 + 변이 2.
#   임시 git 저장소(+ 임시 bare origin)만 · 실 원격·press·오디오 0 · 자기 재호출 0 · 고정 sleep 0.
#   훅 칸(R7 훅 · 연결)은 BYZ 훅 경로가 필요하다: FT_DEFERRAL_GATE=<BYZ>/.claude/hooks/deferral-lint-gate.sh (없으면 FAIL · 건너뜀 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="$BIN/ft-press-card-push-lint.sh"; JUDGE="$BIN/ft-press-baseline-check.sh"
GATE="${FT_DEFERRAL_GATE:-$HERE/../../.claude/hooks/deferral-lint-gate.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$TOOL" && ok "bash -n tool" || bad "bash -n tool"
cmp -s "$TOOL" "$KIT/ft-press-card-push-lint.sh" && ok "ⓔ bin·kit 같은 내용(cmp0)" || bad "ⓔ bin·kit cmp"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; X="design/teams/v65"; IN="$X/indices/inbox/tester"
mkdir -p "$R/worker" "$R/$X/baselines" "$R/$IN/done"
git init -q -b main "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `%s/` | x | 현역 |\n' "$X" > "$R/design/TEAMS.md"
printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/$X/baselines/FLAGS.md"
echo 'x = 1' > "$R/worker/a.py"
SELF_PROSE='기준선: self — 이 세트의 default-3bubble 1회(회차 1)가 기준선이자 재현 시도다'
printf '# 옛 카드\n%s\n실험: 없음\n' "$SELF_PROSE" > "$R/$IN/090-old-block.md"   # R5: 이미 있던 BLOCK 카드
git -C "$R" add -A && git -C "$R" commit -qm base
git init -q --bare "$T/origin.git" && git -C "$R" remote add origin "$T/origin.git" && git -C "$R" push -q origin main 2>/dev/null

# case <이름> <경로=내용>… — main 에서 가지를 새로 따 파일을 쓰고 커밋(upstream = origin/main)
case_br() {
  local name="$1"; shift
  git -C "$R" checkout -q -B "c-$name" origin/main && git -C "$R" branch -q --set-upstream-to=origin/main
  while [ $# -gt 0 ]; do mkdir -p "$(dirname "$R/${1%%=*}")"; printf '%s\n' "${1#*=}" > "$R/${1%%=*}"; shift; done
  git -C "$R" add -A && git -C "$R" commit -qm "$name"
}
run() { OUT="$(timeout 60 bash "${TOOL_UNDER:-$TOOL}" --repo "$R" "$@" 2>&1)"; RC=$?; }
SELF_OK=$'# 기준선 카드\n기준선: self\n종류: 기준선\n회차: 1\n실험: 없음\n프로필: default-3bubble'
R2_CARD="# 114 꼴"$'\n'"$SELF_PROSE"$'\n실험: 없음'

r1() { case_br r1 "$IN/101-ok.md=$SELF_OK"; run --base origin/main
  [ $RC -eq 0 ] && grep -q '^OK 기준선 self' <<<"$OUT" && grep -q '카드 1장 통과' <<<"$OUT"; }
r2() { case_br r2 "$IN/114-prose.md=$R2_CARD"; run --base origin/main
  local solo l; solo="$(bash "$JUDGE" --card "$R/$IN/114-prose.md" --repo "$R" 2>&1)"
  [ $RC -eq 1 ] && grep -q '^BLOCK 기준선 파일: 없음(self — ' <<<"$OUT" || return 1
  while IFS= read -r l; do grep -qxF -- "$l" <<<"$OUT" || return 1; done <<<"$solo"; }   # ⓐ 판정기 단독 출력 줄 전부 그대로
r3() { case_br r3 "$IN/102-nofile.md="$'기준선: '"$X/baselines/BASELINE-nope.md"$'\n실험: 없음'; run --base origin/main
  [ $RC -eq 1 ] && grep -q '^BLOCK 기준선 파일: 없음' <<<"$OUT"; }
r4() { case_br r4 "$IN/103-order.md=# ORDER 카드"$'\n조사만 한다' "$IN/README.md=$R2_CARD" "$IN/done/050-x.md=$R2_CARD" "$X/indices/inbox/arch/1.md=$R2_CARD"
  run --base origin/main; [ $RC -eq 0 ] && grep -qx 'PRESS-CARD-LINT OK 검사 대상 0' <<<"$OUT"; }
r5() { case_br r5 "$X/notes.md=다른 파일만"; run --base origin/main
  [ $RC -eq 0 ] && grep -qx 'PRESS-CARD-LINT OK 검사 대상 0' <<<"$OUT"; }
r6() { case_br r6 "$IN/104-ex.md=$R2_CARD"$'\n- press-card-lint: ok 조사 카드 — 발사 없음'; run --base origin/main
  [ $RC -eq 0 ] && grep -qx "면제 $IN/104-ex.md 조사 카드 — 발사 없음" <<<"$OUT"; }

r1 && ok "R1 판정기 통과 꼴 → rc0" || bad "R1 → rc=$RC $OUT"
r2 && ok "R2 «self — 산문»(114 꼴) → rc1 · 판정기 단독 출력 줄 그대로(ⓐ)" || bad "R2 → rc=$RC $OUT"
r3 && ok "R3 없는 기준선 파일 → rc1 BLOCK" || bad "R3 → rc=$RC $OUT"
r4 && ok "R4 «기준선:» 없는 카드·README·done/·다른 inbox → 검사 대상 0" || bad "R4 → rc=$RC $OUT"
r5 && ok "R5 옛 BLOCK 카드 그대로 · 다른 파일만 → rc0" || bad "R5 → rc=$RC $OUT"
r6 && ok "R6 면제 줄 → rc0 + «면제» 1줄" || bad "R6 → rc=$RC $OUT"

# 병합 유입: 가지를 올린 뒤 main 에 BLOCK 카드가 들어오고 가지가 main 을 병합 → 기준 둘 다 주면 대상 0
case_br merge "$X/notes.md=가지 일" && git -C "$R" push -q origin c-merge 2>/dev/null
git -C "$R" checkout -q main && printf '%s\n' "$R2_CARD" > "$R/$IN/120-main.md" && git -C "$R" add -A && git -C "$R" commit -qm main-card && git -C "$R" push -q origin main 2>/dev/null
git -C "$R" checkout -q c-merge && git -C "$R" fetch -q origin && git -C "$R" merge -q --no-edit origin/main
run --base origin/c-merge --base origin/main
[ $RC -eq 0 ] && grep -qx 'PRESS-CARD-LINT OK 검사 대상 0' <<<"$OUT" && ok "병합 유입 카드(기준 둘) → 대상 0" || bad "병합 유입 → rc=$RC $OUT"

# R7 판정기 없음 → 도구 rc2 «검사 불가»
case_br r7 "$IN/105-ok.md=$SELF_OK"
OUT="$(FT_PRESS_BASELINE_CHECK_BIN="$T/nope.sh" bash "$TOOL" --repo "$R" --base origin/main 2>&1)"; RC=$?
[ $RC -eq 2 ] && grep -q '^PRESS-CARD-LINT 검사 불가 — 판정기 없음' <<<"$OUT" && ok "R7 판정기 없음 → 도구 rc2 검사 불가" || bad "R7 도구 → rc=$RC $OUT"

# 훅 연결(ⓓ) — PreToolUse JSON 을 BYZ 훅에 넣는다
gate() { # <cwd> [env…] → OUT·RC
  local cwd="$1"; shift
  OUT="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"git push origin HEAD"}}))' "$cwd" \
    | env FT_DEFERRAL_LINT_BIN="$BIN/ft-deferral-lint.sh" FT_PRESS_CARD_LINT_BIN="$TOOL" "$@" timeout 70 bash "$GATE" 2>&1)"; RC=$?; }
if [ -f "$GATE" ]; then
  gate "$R" FT_PRESS_BASELINE_CHECK_BIN="$T/nope.sh"
  [ $RC -eq 2 ] && grep -q '검사 불가 — 조용한 허용 0: press 카드 lint rc=2' <<<"$OUT" && ok "R7 훅: 판정기 없음 → exit 2 검사 불가" || bad "R7 훅 → rc=$RC $OUT"
  gate "$R" FT_PRESS_CARD_LINT_BIN="$T/nope-tool.sh"
  [ $RC -eq 2 ] && grep -q 'press 카드 lint rc=127' <<<"$OUT" && ok "훅: 도구 없음 → exit 2 검사 불가" || bad "훅 도구 없음 → rc=$RC $OUT"
  gate "$R"; [ $RC -eq 0 ] && ok "훅: 통과 카드 push → exit 0" || bad "훅 통과 → rc=$RC $OUT"
  case_br hook-r2 "$IN/114-prose.md=$R2_CARD"; gate "$R"
  [ $RC -eq 2 ] && grep -q 'tester press 카드 머리줄이 판정기에 BLOCK' <<<"$OUT" && grep -q '^BLOCK 기준선 파일: 없음(self — ' <<<"$OUT" && ok "훅: R2 카드 push → exit 2 + 판정기 BLOCK 줄" || bad "훅 R2 → rc=$RC $OUT"
else
  bad "훅 파일 없음($GATE) — FT_DEFERRAL_GATE=<BYZ>/.claude/hooks/deferral-lint-gate.sh 로 다시"
fi

# 변이 2 — 변이 도구로 같은 칸을 다시 단언: 칸이 FAIL 해야 변이를 잡은 것
mutant() { sed "$1" "$TOOL" > "$T/mut.sh" && ! cmp -s "$TOOL" "$T/mut.sh" || { bad "변이 적용 실패($2)"; return 1; }; }
mutant 's/out="$(timeout "$STEP_S" bash "$JUDGE" /out="$(true /' "판정기 건너뜀" \
  && { TOOL_UNDER="$T/mut.sh"; export FT_PRESS_BASELINE_CHECK_BIN="$JUDGE"
       r2 && bad "변이1(판정기 건너뜀) 생존 — R2 가 rc=$RC" || ok "변이1(판정기 건너뜀) → R2 FAIL(잡힘 · rc=$RC)"; unset TOOL_UNDER FT_PRESS_BASELINE_CHECK_BIN; }
mutant 's/diff --name-only --diff-filter=AM "$b...HEAD"/ls-files/' "폴더 전체" \
  && { TOOL_UNDER="$T/mut.sh"; export FT_PRESS_BASELINE_CHECK_BIN="$JUDGE"
       r5 && bad "변이2(diff 대신 폴더 전체) 생존 — R5 rc=$RC" || ok "변이2(diff 대신 폴더 전체) → R5 FAIL(잡힘 · rc=$RC)"; unset TOOL_UNDER FT_PRESS_BASELINE_CHECK_BIN; }

echo "fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
