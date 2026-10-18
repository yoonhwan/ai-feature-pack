#!/usr/bin/env bash
# test_autonomy_core.sh — 자율 대리 결정 모드 본체 3종(ft-autonomy · autonomy_classify · ft-proxy-decide) 시험.
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + PATH 앞 gh 스텁 — 실 state·원장·gh 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; MIR="$ROOT/harness/kit/fable-team/bin"
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$2" <<<"$1"; }   # has "<출력>" "<정규식>"

suite() {  # <셸 경로>
  local SH="$1" T; T="$(mktemp -d)"; echo "== suite $SH"
  export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" HIL_DIR="$T"
  mkdir -p "$T/state" "$T/planner" "$T/cards"
  printf '%s\n' '- **100** (오빠) foo-card 착수 승인' '- **101** (오빠) bar-card 설계만 승인' '- **102** (오빠) foo-card 설계만 승인' '- **103** (오빠) foo-card 구현 진행' > "$T/planner/VERDICTS-planner-1.md"
  local A="$SH $BIN/ft-autonomy.sh" C="python3 $BIN/autonomy_classify.py" D="$SH $BIN/ft-proxy-decide.sh" out rc s e
  local SHA="1111111111111111111111111111111111111111"
  # --- ft-autonomy: 상태 ---
  out="$($A status)"; has "$out" '^\[자율 OFF\]$'; ck "status 상태 없음 = OFF" $?
  $D --kind press-order --q "순서?" --choice "A 다음 B" --why "w" --undo "u" >/dev/null 2>&1; rc=$?; [ $rc = 3 ]; ck "OFF 면 대리 도구 rc 3 (got $rc)" $?
  out="$($A on)"; has "$out" '^\[자율 ON A1 · [0-9]{2}:[0-9]{2}~ · 끝 없음 · 대리 0 · 큐 0\]$'; ck "on → A1 status 꼴 ($out)" $?
  [ -f "$T/state/autonomy.json" ] && [ "$(wc -l < "$T/state/autonomy.log" | tr -d ' ')" = 1 ]; ck "json + log 1줄" $?
  # --- 판정기 ---
  for k in card-start press-order nano-reopen docs-push; do $C --kind $k --text "진행할까요" >/dev/null; ck "classify $k PROXY rc 0" $?; done
  out="$($C --kind push-merge --text "진행할까요")"; rc=$?; has "$out" '^QUEUE .*판정 1675' && [ $rc = 2 ]; ck "classify push-merge = QUEUE 고정 (판정 1675)" $?
  while IFS="$(printf '\t')" read -r name text; do
    out="$($C --kind press-order --text "$text")"; rc=$?; has "$out" '^QUEUE 제외 어휘' && [ $rc = 2 ]; ck "제외 어휘 [$name] → QUEUE" $?
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
  $D --kind press-order --q "브랜치 삭제 후 진행?" --choice y --why w --undo u >/dev/null; rc=$?; [ $rc = 2 ]; ck "종류 선언 무관 제외 어휘 = QUEUE" $?
  # --- push-merge = QUEUE 고정 (판정 1675) — 근거(sha·DA 판정문)가 완벽해도 대리 0 · ok 파일 쓰기 0 ---
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`\n' "$SHA" > "$T/da.md"; printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `2222222222222222222222222222222222222222`\n' > "$T/da-other.md"
  out="$($D --kind push-merge --q "머지 ok" --choice 머지 --why DA6 --undo "git revert $SHA" --sha "$SHA" --da "$T/da.md" --pr 7 2>&1)"; rc=$?
  [ $rc = 2 ] && has "$out" '^QUEUE main 병합·main push = 오빠 값\(판정 1675\)' && [ ! -e "$T/state/autonomy-merge-ok" ]; ck "push-merge 근거 일치여도 QUEUE rc 2 · ok 폴더 0 (rc $rc: $out)" $?
  # da-check(판정문 «마지막 판정 머리» 결속)는 판정기 하위 명령으로 남아 있다 — pm = 그 결과(0 PROXY · 2 QUEUE)
  pm() { python3 "$BIN/autonomy_classify.py" da-check "${3:-$T/da.md}" "${2:-$SHA}" >/dev/null 2>&1; }
  pm ok; ck "da-check 판정문 sha 일치 → PROXY" $?
  pm daother "$SHA" "$T/da-other.md"; [ $? = 2 ]; ck "DA 판정문에 그 sha 없음 → QUEUE" $?
  # --- H1: 판정문 «마지막 판정 머리» 결속 (실물 2장 + 합성) ---
  SA=555d30e73a6f7747f75de4e5d9625bd1decd4fad; SH=47c8e1c6bf6d1392aad4b1cdc94a72203cd6df3c
  pm realok "$SA" "$HERE/fixtures/da6-approve-real.md"; ck "H1 실물 APPROVE(머리·sha 별도 줄) → PROXY" $?
  pm realhold "$SH" "$HERE/fixtures/da6-hold-real.md"; [ $? = 2 ]; ck "H1 실물 HOLD → QUEUE" $?
  printf '# DA HOLD — 1건\n고정 세트 %s\n이전 결과: APPROVE %s\n현재 판정 HOLD\n' "$SHA" "$SHA" > "$T/da-cur-hold.md"
  pm curhold "$SHA" "$T/da-cur-hold.md"; [ $? = 2 ]; ck "H1 머리 HOLD + 과거 APPROVE → QUEUE" $?
  printf '# [DA⑥ t] HOLD — 1건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n' "$SHA" "$SHA" > "$T/da-r2-ok.md"
  pm r2ok "$SHA" "$T/da-r2-ok.md"; ck "H1 r2 절 APPROVE + sha → PROXY" $?
  printf '# [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] HOLD — 1건\n' "$SHA" > "$T/da-r2-hold.md"
  pm r2hold "$SHA" "$T/da-r2-hold.md"; [ $? = 2 ]; ck "H1 r2 절 HOLD → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n고정 세트 `%s`\n\n## r2 [DA⑥ t] APPROVE — 0건\n본문에 sha 없음\n' "$SHA" > "$T/da-r2-nosha.md"
  pm r2nosha "$SHA" "$T/da-r2-nosha.md"; [ $? = 2 ]; ck "H1 r2 절이 sha 를 말하지 않음 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE HOLD — 모순\n고정 세트 `%s`\n' "$SHA" > "$T/da-mixed.md"
  pm mixed "$SHA" "$T/da-mixed.md"; [ $? = 2 ]; ck "H1 머리에 판정어 둘(모순) → QUEUE" $?
  printf '본문만 있고 판정 머리 없음 %s\n' "$SHA" > "$T/da-nohead.md"
  pm nohead "$SHA" "$T/da-nohead.md"; [ $? = 2 ]; ck "H1 판정 머리 없음 → QUEUE" $?
  # --- r3: 최신 절의 «고정 세트» 줄 하나에서 대상 sha 를 뽑아 --sha 와 같을 때만 ---
  SB=4444444444444444444444444444444444444444
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`. 이전 세트 `%s` 는 HOLD 였다.\n' "$SB" "$SHA" > "$T/da-r3-two.md"
  pm r3two "$SHA" "$T/da-r3-two.md"; [ $? = 2 ]; ck "r3 고정 세트 줄에 40hex 2개 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`\n\n본문: 과거 세트 %s 는 HOLD 였다.\n' "$SB" "$SHA" > "$T/da-r3-past.md"
  pm r3past "$SHA" "$T/da-r3-past.md"; [ $? = 2 ]; ck "r3 B 승인 + A 는 과거 HOLD 설명 → A QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n본문에 세트 %s 가 있으나 고정 세트 줄 없음\n' "$SHA" > "$T/da-r3-noline.md"
  pm r3noline "$SHA" "$T/da-r3-noline.md"; [ $? = 2 ]; ck "r3 고정 세트 줄 없음 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 (해시 없음)\n본문 %s\n' "$SHA" > "$T/da-r3-zero.md"
  pm r3zero "$SHA" "$T/da-r3-zero.md"; [ $? = 2 ]; ck "r3 고정 세트 줄에 40hex 0개 → QUEUE" $?
  printf '# [DA⑥ t] APPROVE — 0건\n\n**고정 세트** `%s`, base `bc061f9c2b`\n' "$SHA" > "$T/da-r3-ok.md"
  pm r3ok "$SHA" "$T/da-r3-ok.md"; ck "r3 정상 A 승인(굵게·백틱 섞임) → PROXY" $?
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
  out="$($A status)"; has "$out" '^\[자율 ON A1 · .*대리 2 · 큐 [0-9]+\]$'; ck "status 대리·큐 카운트 ($out)" $?
  out="$($A off)"; has "$out" '대리 2 · 큐 [0-9]+'; ck "off 요약 «대리 N · 큐 M» ($out)" $?
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
# --- R185 (판정 1720 ①): 끝 시각(until)이 지나면 OFF 로 읽기 + expire 기록 — 가짜 시계 FT_NOW · 임시 상태 폴더만 ---
expire_suite() {  # <셸 경로>
  local SH="$1" T T0=1800000000 H=3600 A out rc nl; T="$(mktemp -d)"; echo "== expire suite $SH"
  export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" HIL_DIR="$T"; mkdir -p "$T/state" "$T/planner"
  A="$SH $BIN/ft-autonomy.sh"; offs() { grep -c "$(printf '\toff\t')" "$T/state/autonomy.log" 2>/dev/null; }
  FT_NOW=$T0 $A on --for 1h >/dev/null 2>&1; [ "$(FT_NOW=$T0 $A mode)" = on ]; ck "expire: 켠 직후 mode=on" $?
  # ⓑ 아직 전 = 기존 동작 그대로
  [ "$(FT_NOW=$((T0+H-1)) $A mode)" = on ]; ck "ⓑ until 1초 전 mode=on" $?
  out="$(FT_NOW=$((T0+H-1)) $A status)"; has "$out" '^\[자율 ON A1 · .* · ~[0-9]{2}:[0-9]{2}까지 · 대리 0 · 큐 0\]$'; ck "ⓑ until 1초 전 status = ON 꼴 ($out)" $?
  out="$(FT_NOW=$((T0+H-1)) $A expire)"; [ "$out" = NOOP ] && [ "$(offs)" = 0 ]; ck "ⓑ until 전 expire = NOOP · off 줄 0 ($out)" $?
  # ⓐ until 지남 → 쓰기 없이 off 로 읽는다(위변조 아님)
  [ "$(FT_NOW=$((T0+H)) $A mode)" = off ]; ck "ⓐ now ≥ until → mode=off" $?
  out="$(FT_NOW=$((T0+H)) $A status)"; has "$out" '^\[자율 OFF · A1 끝 도달 [0-9]{2}:[0-9]{2}\]$'; ck "ⓐ status = [자율 OFF · A1 끝 도달 HH:MM] ($out)" $?
  grep -q '"mode":"on"' "$T/state/autonomy.json" && [ "$(offs)" = 0 ]; ck "ⓐ 읽기만으로는 json·log 안 건드림" $?
  FT_NOW=$((T0+H)) $SH "$BIN/ft-proxy-decide.sh" --kind press-order --q q --choice c --why w --undo u >/dev/null 2>&1; rc=$?; [ $rc = 3 ]; ck "ⓐ 지난 ON 은 대리 도구 rc 3 (got $rc)" $?
  FT_NOW=$((T0+H)) $A approve-merge 1111111111111111111111111111111111111111 >/dev/null 2>&1; rc=$?; [ $rc = 0 ] && grep -qE '^approve-merge 1{40} OFF [0-9]+$' "$T/state/autonomy.log"; ck "ⓐ 지난 ON(=OFF 로 읽힘) 병합 승인 = 기록 rc 0 · 이벤트 OFF (R336 · got $rc)" $?
  # ⓒ expire 멱등 · ⓓ 뒤 정합
  out="$(FT_NOW=$((T0+H+5)) $A expire)"; [ "$out" = "EXPIRED A1" ] && [ "$(offs)" = 1 ]; ck "ⓒ expire 첫 호출 = EXPIRED A1 · off 줄 1 ($out)" $?
  out="$(FT_NOW=$((T0+H+9)) $A expire)"; [ "$out" = NOOP ] && [ "$(offs)" = 1 ]; ck "ⓒ expire 두 번째 = NOOP · off 줄 그대로 1 ($out)" $?
  [ "$(FT_NOW=$((T0+H+9)) $A mode)" = off ]; ck "ⓓ expire 뒤 mode=off (tamper 아님)" $?
  out="$(FT_NOW=$((T0+H+9)) $A status)"; [ "$out" = "[자율 OFF]" ]; ck "ⓓ expire 뒤 status = [자율 OFF] ($out)" $?
  # ⓔ 다시 on = 새 사건 번호
  out="$(FT_NOW=$((T0+H+20)) $A on --for 1h 2>&1)"; has "$out" 'ON A2'; ck "ⓔ 다시 on → A2 ($out)" $?
  [ "$(FT_NOW=$((T0+H+21)) $A mode)" = on ]; ck "ⓔ 새 구간 mode=on" $?
  # ⓒ ON 이 아니면 아무것도 안 쓴다 — 오빠가 끈 OFF 에 expire 는 NOOP
  $A off >/dev/null 2>&1; nl="$(wc -l < "$T/state/autonomy.log" | tr -d ' ')"
  out="$(FT_NOW=$((T0+9*H)) $A expire)"; [ "$out" = NOOP ] && [ "$(wc -l < "$T/state/autonomy.log" | tr -d ' ')" = "$nl" ]; ck "ⓒ OFF 에 expire = NOOP · log 그대로 ($out)" $?
  # ⓑ until 없음(null) = 끝 없음 그대로
  rm -rf "$T/state"; mkdir -p "$T/state"; FT_NOW=$T0 $A on >/dev/null 2>&1
  [ "$(FT_NOW=$((T0+999*H)) $A mode)" = on ] && [ "$(FT_NOW=$((T0+999*H)) $A expire)" = NOOP ]; ck "ⓑ until 없음 = 한참 뒤에도 on · expire NOOP" $?
  # 위변조 + until 지남 = 여전히 tamper(위변조가 먼저)
  rm -rf "$T/state"; mkdir -p "$T/state"; FT_NOW=$T0 $A on --for 1h >/dev/null 2>&1; sed -i.bak 's/"event":"A1"/"event":"A9"/' "$T/state/autonomy.json"
  [ "$(FT_NOW=$((T0+2*H)) $A mode)" = tamper ] && [ "$(FT_NOW=$((T0+2*H)) $A expire)" = NOOP ]; ck "위변조가 먼저 — until 지나도 tamper · expire NOOP" $?
  # 변이 1: 시각 비교를 지우면 ⓐ 가 FAIL(= 이 시험이 그 회귀를 잡는다)
  rm -rf "$T/state" "$T/mut"; mkdir -p "$T/state" "$T/mut"; sed 's/-ge "\$u" \]/-ge 99999999999 ]/' "$BIN/ft-autonomy.sh" > "$T/mut/ft-autonomy.sh"; ln -s "$BIN/ft-autonomy-start.sh" "$T/mut/ft-autonomy-start.sh"
  ! cmp -s "$BIN/ft-autonomy.sh" "$T/mut/ft-autonomy.sh"; ck "변이 1 사본이 원본과 다르다" $?
  FT_NOW=$T0 $SH "$T/mut/ft-autonomy.sh" on --for 1h >/dev/null 2>&1; [ "$(FT_NOW=$((T0+H)) $SH "$T/mut/ft-autonomy.sh" mode)" = on ]; ck "변이 1: 시각 비교 제거 → ⓐ 의 mode=off 가 깨진다(on 으로 남음)" $?
  # --- r3 (DA⑥ H1): 동시 expire 멱등 — 잠금 안에서 재확인·기록·교체. 동시 16호출 ×3 → OFF 줄 1 · EXPIRED 1 · NOOP 15 ---
  conc() {  # <ft-autonomy.sh 경로> → "<off 줄 수> <EXPIRED 수> <NOOP 수>"
    local S="$1" i; rm -rf "$T/state" "$T/cout"; mkdir -p "$T/state" "$T/cout"
    FT_NOW=$T0 $SH "$S" on --for 1h >/dev/null 2>&1
    for i in $(seq 16); do FT_NOW=$((T0+H+5)) $SH "$S" expire > "$T/cout/$i" 2>&1 & done; wait
    echo "$(offs) $(cat "$T/cout"/* | grep -c '^EXPIRED A1$') $(cat "$T/cout"/* | grep -c '^NOOP$')"
  }
  for i in 1 2 3; do
    out="$(conc "$BIN/ft-autonomy.sh")"
    [ "$out" = "1 1 15" ]; ck "동시 expire 16 #$i = OFF 줄 1 · EXPIRED 1 · NOOP 15 (got: $out)" $?
  done
  [ "$(FT_NOW=$((T0+H+9)) $A mode)" = off ] && [ "$(FT_NOW=$((T0+H+9)) $A status)" = "[자율 OFF]" ]; ck "동시 expire 뒤 mode=off(tamper 아님) · json/log 정합" $?
  [ ! -d "$T/state/.autonomy.lock" ] && ! ls "$T/state" | grep -q 'autonomy.json.tmp'; ck "동시 expire 뒤 잠금·임시 파일 잔류 0" $?
  sed 's/until mkdir "\$LOCKD" 2>\/dev\/null; do/until true; do/' "$BIN/ft-autonomy.sh" > "$T/mut/ft-autonomy-nolock.sh"; ! cmp -s "$BIN/ft-autonomy.sh" "$T/mut/ft-autonomy-nolock.sh"; ck "변이 2 사본이 원본과 다르다" $?
  bad=0; for i in 1 2 3 4 5; do [ "$(conc "$T/mut/ft-autonomy-nolock.sh")" = "1 1 15" ] || { bad=1; break; }; done; [ "$bad" = 1 ]; ck "변이 2: 잠금 제거 → 동시 expire 멱등이 깨진다(FAIL 검출)" $?
  rm -rf "$T/state"; mkdir -p "$T/state/.autonomy.lock"; out="$(FT_NOW=$T0 $A expire 2>&1)"; rc=$?; [ $rc = 1 ] && has "$out" '^REJECT 상태 잠금 선점 중'; ck "잠금 선점 중 = 상한 뒤 rc 1 REJECT(조용한 통과 0) (rc $rc: $out)" $?
  rmdir "$T/state/.autonomy.lock"
  # --- 틱: 매 루프 expire · EXPIRED 일 때만 planner 앞 쪽지 1통 · FT_TICK_AUTONOMY=0 으로 끔 ---
  rm -rf "$T/state" "$T/mb.log"; mkdir -p "$T/state"
  printf '#!/bin/bash\necho "$*" >> "%s/mb.log"\n' "$T" > "$T/mbox-stub.sh"
  printf '%s\n' '{"_master":"m1","_hil_route":"pl1","m1":{"role":"master","tick":null},"pl1":{"role":"pm","tick":null}}' > "$T/seats.json"
  tick() { (cd "$T" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY FT_NOW="$1" $TICK_X FT_TICK_SEATS="$T/seats.json" FT_TICK_STATE_DIR="$T/tick-state" FT_TICK_STAMP_PREFIX="$T/stamp-" FT_TICK_PIDFILE="$T/tick.pid" \
    FT_TICK_MBOX="$T/mbox-stub.sh" FT_TICK_AUTONOMY_BIN="$BIN/ft-autonomy.sh" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_NEWS_LEDGER=0 \
    FT_TICK_API_OUTAGE=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_LONG=0 FT_TICK_STALL_INTERVAL=9999999999 $SH "$BIN/ft-tick.sh" --once 2>&1); }
  FT_NOW=$T0 $A on --for 1h >/dev/null 2>&1
  TICK_X="FT_TICK_AUTONOMY=0" tick $((T0+H+5)) >/dev/null; [ "$(offs)" = 0 ] && [ ! -e "$T/mb.log" ]; ck "틱 FT_TICK_AUTONOMY=0 = expire 0 · 쪽지 0" $?
  TICK_X="" out="$(tick $((T0+H+5)))"; [ "$(offs)" = 1 ] && [ "$(wc -l < "$T/mb.log" | tr -d ' ')" = 1 ] && has "$(cat "$T/mb.log")" '^send pl1 ft-tick \[자율 A1 끝 도달 → OFF\]'; ck "틱 1회 = off 줄 1 · planner(_hil_route) 앞 쪽지 1통" $?
  has "$out" 'autonomy_expire: EXPIRED A1'; ck "틱 로그 1줄 EXPIRED A1" $?
  TICK_X="" tick $((T0+H+70)) >/dev/null; [ "$(offs)" = 1 ] && [ "$(wc -l < "$T/mb.log" | tr -d ' ')" = 1 ]; ck "틱 2회 = 멱등(off 줄 1 · 쪽지 1 그대로)" $?
  rm -rf "$T"; unset FT_NOW
}
expire_suite /bin/bash
# --- 정적 점검 ---
cmp -s "$BIN/ft-tick.sh" "$MIR/ft-tick.sh"; ck "키트 미러 cmp ft-tick.sh" $?
for f in ft-autonomy.sh autonomy_classify.py ft-proxy-decide.sh; do
  cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp $f" $?
  [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?
done
grep -qE '^CALL_TIMEOUT_S=7( |$)' "$BIN/ft-proxy-decide.sh" && grep -qE '^CALL_RETRIES=1( |$)' "$BIN/ft-proxy-decide.sh" \
  && grep -qE 'EXTERNAL_CALL_TIMEOUT_S: float = 7\.0' "$ROOT/shared/config/external_call.py" && grep -qE 'EXTERNAL_CALL_MAX_RETRIES: int = 1' "$ROOT/shared/config/external_call.py"; ck "7초+재시도 1회 = external_call.py 값과 같음" $?
echo "== $n checks, fail=$fail"; [ "$fail" = 0 ]
