#!/usr/bin/env bash
# test_autonomy_core.sh — 자율 대리 결정 모드 본체 3종(ft-autonomy · autonomy_classify · ft-proxy-decide) 시험.
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + PATH 앞 gh 스텁 — 실 state·원장·gh 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/scripts/fable-team-bin"; MIR="$ROOT/scripts/harness-install/fable-team/bin"
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$2" <<<"$1"; }   # has "<출력>" "<정규식>"

suite() {  # <셸 경로>
  local SH="$1" T; T="$(mktemp -d)"; echo "== suite $SH"
  export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" HIL_DIR="$T"
  mkdir -p "$T/state" "$T/planner" "$T/stubs" "$T/cards"
  printf '%s\n' '- **100** (오빠) foo-card 착수 승인' '- **101** (오빠) bar-card 설계만 승인' '- **102** (오빠) foo-card 설계만 승인' '- **103** (오빠) foo-card 구현 진행' > "$T/planner/VERDICTS-planner-1.md"
  printf '%s\n' '#!/bin/bash' '[ "${GH_FAIL:-0}" = 1 ] && exit 1' '[ "${GH_IGNORE_TERM:-0}" = 1 ] && trap "" TERM' '[ -n "${GH_DELAY:-}" ] && sleep "$GH_DELAY"' \
    'case "$*" in *"pr view"*) echo "${GH_HEAD:-}";; *"pr checks"*) printf "%s\n" ${GH_CHECKS:-pass};; esac' > "$T/stubs/gh"
  chmod +x "$T/stubs/gh"; export PATH="$T/stubs:$PATH"
  local A="$SH $BIN/ft-autonomy.sh" C="python3 $BIN/autonomy_classify.py" D="$SH $BIN/ft-proxy-decide.sh" out rc s e
  local SHA="1111111111111111111111111111111111111111"
  # --- ft-autonomy: 상태 ---
  out="$($A status)"; has "$out" '^\[자율 OFF\]$'; ck "status 상태 없음 = OFF" $?
  $D --kind press-order --q "순서?" --choice "A 다음 B" --why "w" --undo "u" >/dev/null 2>&1; rc=$?; [ $rc = 3 ]; ck "OFF 면 대리 도구 rc 3 (got $rc)" $?
  out="$($A on)"; has "$out" '^\[자율 ON A1 · [0-9]{2}:[0-9]{2}~ · 대리 0 · 큐 0\]$'; ck "on → A1 status 꼴 ($out)" $?
  [ -f "$T/state/autonomy.json" ] && [ "$(wc -l < "$T/state/autonomy.log" | tr -d ' ')" = 1 ]; ck "json + log 1줄" $?
  # --- 판정기 ---
  for k in push-merge card-start press-order; do $C --kind $k --text "머지 승인 진행할까요" >/dev/null; ck "classify $k PROXY rc 0" $?; done
  while IFS="$(printf '\t')" read -r name text; do
    out="$($C --kind push-merge --text "$text")"; rc=$?; has "$out" '^QUEUE' && [ $rc = 2 ]; ck "제외 어휘 [$name] → QUEUE" $?
  done < "$HERE/fixtures/autonomy-exclusions.tsv"
  out="$($C --kind reversible-choice --text "되돌릴 수 있는 선택")"; has "$out" '^QUEUE'; ck "reversible-choice = QUEUE" $?
  out="$($C --kind 아무거나 --text "x")"; has "$out" '^QUEUE'; ck "모르는 종류 = QUEUE" $?
  out="$($C 2>/dev/null)"; rc=$?; has "$out" '^QUEUE' && [ $rc = 2 ]; ck "판정기 인자 오류 = QUEUE rc 2" $?
  # --- 대리 도구: PROXY / QUEUE ---
  out="$($D --kind press-order --q "순서?" --choice "A 다음 B" --why "w1" --undo "u1")"; rc=$?
  [ $rc = 0 ]; ck "press-order PROXY rc 0 (got $rc: $out)" $?
  tail -1 "$T/planner/VERDICTS-planner-1.md" | grep -qE '^- \*\*104\*\* \[대리 · 자율 ON A1\] 순서\? → A 다음 B · 근거 w1 · 되돌림 u1$'; ck "원장 줄 꼴 (번호 = 최대+1)" $?
  out="$($D --kind reversible-choice --q "q2" --choice c --why w --undo u)"; rc=$?; [ $rc = 2 ]; ck "QUEUE rc 2 (got $rc)" $?
  grep -qF '| A1 |' "$T/planner/AUTONOMY-QUEUE.md"; ck "큐 행 1" $?
  $D --kind reversible-choice --q "q2" --choice c --why w --undo u >/dev/null; rc=$?
  [ $rc = 2 ] && [ "$(grep -cF '| A1 |' "$T/planner/AUTONOMY-QUEUE.md")" = 1 ]; ck "같은 질문 재시도 rc 2 · 큐 행 안 늘어남" $?
  $D --kind push-merge --q "브랜치 삭제 후 머지?" --choice y --why w --undo u >/dev/null; rc=$?; [ $rc = 2 ]; ck "종류 선언 무관 제외 어휘 = QUEUE" $?
  # --- push-merge 결속 ---
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`\n' "$SHA" > "$T/da.md"; printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `2222222222222222222222222222222222222222`\n' > "$T/da-other.md"
  pm() { $D --kind push-merge --q "머지 $1" --choice 머지 --why "DA6" --undo "git revert $SHA" --sha "${2:-$SHA}" --da "${3:-$T/da.md}" --pr 7 >/dev/null 2>&1; }
  GH_HEAD=$SHA GH_CHECKS="pass pass" pm ok; ck "push-merge 근거 일치 → PROXY" $?
  GH_HEAD=3333333333333333333333333333333333333333 pm headdiff; [ $? = 2 ]; ck "PR head ≠ --sha → QUEUE" $?
  GH_HEAD=$SHA GH_CHECKS="pass fail" pm checkfail; [ $? = 2 ]; ck "checks 하나 실패 → QUEUE" $?
  GH_HEAD=$SHA GH_CHECKS="pass" pm daother "$SHA" "$T/da-other.md"; [ $? = 2 ]; ck "DA 판정문에 그 sha 없음 → QUEUE" $?
  GH_HEAD=$SHA GH_FAIL=1 pm ghfail; [ $? = 2 ]; ck "gh 실패 → QUEUE" $?
  s=$(date +%s); GH_HEAD=$SHA GH_DELAY=8 pm slow; rc=$?; e=$(( $(date +%s) - s ))
  [ $rc = 2 ] && [ $e -lt 30 ]; ck "gh 지연 8초 = QUEUE (${e}s)" $?
  # --- H1: 판정문 «마지막 판정 머리» 결속 (실물 2장 + 합성) ---
  SA=555d30e73a6f7747f75de4e5d9625bd1decd4fad; SH=47c8e1c6bf6d1392aad4b1cdc94a72203cd6df3c
  GH_HEAD=$SA GH_CHECKS=pass pm realok "$SA" "$HERE/fixtures/da6-approve-real.md"; ck "H1 실물 APPROVE(머리·sha 별도 줄) → PROXY" $?
  GH_HEAD=$SH GH_CHECKS=pass pm realhold "$SH" "$HERE/fixtures/da6-hold-real.md"; [ $? = 2 ]; ck "H1 실물 HOLD → QUEUE" $?
  printf '# DA HOLD — 1건\n고정 세트 %s\n이전 결과: APPROVE %s\n현재 판정 HOLD\n' "$SHA" "$SHA" > "$T/da-cur-hold.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm curhold "$SHA" "$T/da-cur-hold.md"; [ $? = 2 ]; ck "H1 머리 HOLD + 과거 APPROVE → QUEUE" $?
  printf '# [DA⑥ t] HOLD — 1건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n' "$SHA" "$SHA" > "$T/da-r2-ok.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r2ok "$SHA" "$T/da-r2-ok.md"; ck "H1 r2 절 APPROVE + sha → PROXY" $?
  printf '# [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] HOLD — 1건\n' "$SHA" > "$T/da-r2-hold.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r2hold "$SHA" "$T/da-r2-hold.md"; [ $? = 2 ]; ck "H1 r2 절 HOLD → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] APPROVE — 0건\n본문에 sha 없음\n' "$SHA" > "$T/da-r2-nosha.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r2nosha "$SHA" "$T/da-r2-nosha.md"; [ $? = 2 ]; ck "H1 r2 절이 sha 를 말하지 않음 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE HOLD — 모순\n고정 세트 `%s`\n' "$SHA" > "$T/da-mixed.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm mixed "$SHA" "$T/da-mixed.md"; [ $? = 2 ]; ck "H1 머리에 판정어 둘(모순) → QUEUE" $?
  printf '본문만 있고 판정 머리 없음 %s\n' "$SHA" > "$T/da-nohead.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm nohead "$SHA" "$T/da-nohead.md"; [ $? = 2 ]; ck "H1 판정 머리 없음 → QUEUE" $?
  # --- r3: 최신 절의 «고정 세트» 줄 하나에서 대상 sha 를 뽑아 --sha 와 같을 때만 ---
  SB=4444444444444444444444444444444444444444
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`. 이전 세트 `%s` 는 HOLD 였다.\n' "$SB" "$SHA" > "$T/da-r3-two.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r3two "$SHA" "$T/da-r3-two.md"; [ $? = 2 ]; ck "r3 고정 세트 줄에 40hex 2개 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`\n\n본문: 과거 세트 %s 는 HOLD 였다.\n' "$SB" "$SHA" > "$T/da-r3-past.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r3past "$SHA" "$T/da-r3-past.md"; [ $? = 2 ]; ck "r3 B 승인 + A 는 과거 HOLD 설명 → A QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n본문에 세트 %s 가 있으나 고정 세트 줄 없음\n' "$SHA" > "$T/da-r3-noline.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r3noline "$SHA" "$T/da-r3-noline.md"; [ $? = 2 ]; ck "r3 고정 세트 줄 없음 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 (해시 없음)\n본문 %s\n' "$SHA" > "$T/da-r3-zero.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r3zero "$SHA" "$T/da-r3-zero.md"; [ $? = 2 ]; ck "r3 고정 세트 줄에 40hex 0개 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n**고정 세트** `%s`, base `bc061f9c2b`\n' "$SHA" > "$T/da-r3-ok.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm r3ok "$SHA" "$T/da-r3-ok.md"; ck "r3 정상 A 승인(굵게·백틱 섞임) → PROXY" $?
  # --- H4: 시도마다 7초 deadline — TERM 무시 호출이 9초에 일치 응답해도 채택 0 ---
  printf '# [DA⑥ t] APPROVE\n고정 세트 `%s`\n' "$SHA" > "$T/da-h4.md"
  GH_HEAD=$SHA GH_CHECKS=pass pm h4ctl "$SHA" "$T/da-h4.md"; ck "H4 대조군(빠른 응답) → PROXY" $?
  s=$(date +%s); GH_HEAD=$SHA GH_CHECKS=pass GH_DELAY=9 GH_IGNORE_TERM=1 pm lateok "$SHA" "$T/da-h4.md"; rc=$?; e=$(( $(date +%s) - s ))
  [ $rc = 2 ]; ck "H4 늦은 rc0(9초·TERM 무시) 채택 0 → QUEUE (rc $rc, ${e}s)" $?
  [ $e -lt 26 ]; ck "H4 총 시간 상한(7초×2 + 유예) (${e}s)" $?
  # --- card-start 결속 ---
  printf '# 인덱스: foo-card\n## 배경\n평범한 도구 추가.\n## 구현 범위\n1. 도구 하나.\n## 완료 조건\n통과.\n' > "$T/cards/foo-card.md"
  printf '# 인덱스: bad-card\n## 구현 범위\n1. git push --force 로 덮어쓴다.\n' > "$T/cards/bad-card.md"
  printf '%s\n' '- **200** (오빠) bad-card 착수 승인' '- **201** (오빠) foo-card-rotate 착수 승인' '- **202** (오빠) my-foo-card 착수 승인' > "$T/planner/VERDICTS-planner-2.md"
  cs() { $D --kind card-start --q "착수 $1?" --choice y --why w --undo u --card "$2" --verdict "$3" >/dev/null 2>&1; }
  cs a "$T/cards/foo-card.md" 100; ck "card-start 판정 줄에 slug+착수 → PROXY" $?
  cs b "$T/cards/foo-card.md" 101; [ $? = 2 ]; ck "판정 줄이 다른 카드만 → QUEUE" $?
  cs c "$T/cards/foo-card.md" 102; [ $? = 2 ]; ck "«설계만» → QUEUE" $?
  cs d "$T/cards/bad-card.md" 200; [ $? = 2 ]; ck "카드 본문에 제외 어휘 → QUEUE" $?
  cs e "$T/cards/none.md" 100; [ $? = 2 ]; ck "카드 못 읽음 → QUEUE" $?
  cs f "$T/cards/foo-card.md" 201; [ $? = 2 ]; ck "판정 줄이 foo-card-rotate 만 승인 → foo-card QUEUE (접두)" $?
  cs g "$T/cards/foo-card.md" 202; [ $? = 2 ]; ck "판정 줄이 my-foo-card 만 승인 → foo-card QUEUE (접미)" $?
  printf '%s\n' '- **203** (오빠) foo-card 착수 보류' '- **204** (오빠) foo-card 착수하지 않는다' '- **205** (오빠) foo-card 착수 금지' '- **206** (오빠) foo-card 착수 안 함' '- **207** (오빠) foo-card 착수 중단' '- **208** (오빠) foo-card 착수 취소' '- **209** (오빠) foo-card 착수 대기' >> "$T/planner/VERDICTS-planner-2.md"
  for v in 203 204 205 206 207 208 209; do cs "neg$v" "$T/cards/foo-card.md" $v; [ $? = 2 ]; ck "H2 부정어 판정 $v → QUEUE" $?; done
  # --- H3: 기록 실패에 PROXY·QUEUE 성공을 말하지 않는다 (#0 RULE) ---
  L="$T/planner/VERDICTS-planner-2.md"; n0=$(wc -l < "$L" | tr -d ' ')
  chmod 444 "$L"; FT_PROXY_LEDGER="$L" $D --kind press-order --q "원장 실패" --choice c --why w --undo u >"$T/o" 2>"$T/e"; rc=$?; chmod 644 "$L"
  [ $rc != 0 ] && [ $rc != 2 ] && [ -s "$T/e" ] && ! grep -q '^PROXY' "$T/o" && [ "$(wc -l < "$L" | tr -d ' ')" = "$n0" ]; ck "H3 원장 쓰기 실패 → rc≠0·stderr·PROXY 0 (rc $rc)" $?
  FT_PROXY_LEDGER="$T/planner" $D --kind press-order --q "원장 디렉터리" --choice c --why w --undo u >"$T/o" 2>"$T/e"; rc=$?
  [ $rc != 0 ] && [ $rc != 2 ] && ! grep -q '^PROXY' "$T/o"; ck "H3 원장이 디렉터리 → PROXY 0 (rc $rc)" $?
  chmod 444 "$T/planner/AUTONOMY-QUEUE.md"; $D --kind reversible-choice --q "큐 실패" --choice c --why w --undo u >"$T/o" 2>"$T/e"; rc=$?; chmod 644 "$T/planner/AUTONOMY-QUEUE.md"
  [ $rc != 0 ] && [ $rc != 2 ] && [ -s "$T/e" ]; ck "H3 큐 쓰기 실패 → rc≠0·stderr (rc $rc)" $?
  chmod 444 "$T/state/autonomy.queued"; $D --kind reversible-choice --q "seen 실패" --choice c --why w --undo u >"$T/o" 2>"$T/e"; rc=$?; chmod 644 "$T/state/autonomy.queued"
  [ $rc != 0 ] && [ $rc != 2 ] && [ -s "$T/e" ]; ck "H3 재시도 기록(SEEN) 쓰기 실패 → rc≠0·stderr (rc $rc)" $?
  # --- 상태: 요약·위변조 ---
  out="$($A status)"; has "$out" '^\[자율 ON A1 · .*대리 7 · 큐 [0-9]+\]$'; ck "status 대리·큐 카운트 ($out)" $?
  out="$($A off)"; has "$out" '대리 7 · 큐 [0-9]+'; ck "off 요약 «대리 N · 큐 M» ($out)" $?
  has "$out" 'AUTONOMY-QUEUE.md'; ck "off 요약에 큐 파일 경로" $?
  out="$($A on)"; has "$out" 'ON A2'; ck "다시 on → A2" $?
  sed -i.bak 's/"mode": *"on"/"mode":"off"/' "$T/state/autonomy.json"
  out="$($A status)"; has "$out" '^\[자율 \?\? 위변조 → OFF\]$'; ck "json 만 고침 → 위변조 표시" $?
  $D --kind press-order --q "q9" --choice c --why w --undo u >/dev/null 2>&1; rc=$?; [ $rc = 3 ]; ck "위변조 = OFF 취급 (대리 rc 3)" $?
  $A bogus >/dev/null 2>&1; [ $? = 2 ]; ck "알 수 없는 인자 rc 2" $?
  rm -rf "$T"
}
suite /bin/bash
B5="$(command -v bash)"; [ "$("$B5" -c 'echo ${BASH_VERSINFO[0]}')" -ge 5 ] 2>/dev/null && suite "$B5" || echo "SKIP bash5 없음"
# --- 정적 점검 ---
for f in ft-autonomy.sh autonomy_classify.py ft-proxy-decide.sh; do
  cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp $f" $?
  [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?
done
grep -qE '^CALL_TIMEOUT_S=7( |$)' "$BIN/ft-proxy-decide.sh" && grep -qE '^CALL_RETRIES=1( |$)' "$BIN/ft-proxy-decide.sh" \
  && grep -qE 'EXTERNAL_CALL_TIMEOUT_S: float = 7\.0' "$ROOT/shared/config/external_call.py" && grep -qE 'EXTERNAL_CALL_MAX_RETRIES: int = 1' "$ROOT/shared/config/external_call.py"; ck "7초+재시도 1회 = external_call.py 값과 같음" $?
echo "== $n checks, fail=$fail"; [ "$fail" = 0 ]
