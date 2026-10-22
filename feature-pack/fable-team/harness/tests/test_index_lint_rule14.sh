#!/usr/bin/env bash
# test_index_lint_rule14.sh — ft-index-lint 「소환: 규칙14」 길 시험 (하드 룰 14 · planner 판정 2654 · chatbot E1 · r767 r1). 임시 리포에서만 돈다.
#   보류 횟수 = «라운드 수»(사전검증의 「DA:」 줄 하나 = 한 라운드 판정문 · 서로 다른 경로·내용 · 각 파일 마지막 판정 HOLD) — 낱말 셈 아님
#   ⓐ' 라운드 1개(낱말 2회) REJECT ⓑ' 라운드 2개 OK ⓒ' 같은 경로 2줄 REJECT ⓓ' 내용 같은 2파일 REJECT
#   ⓔ' 원장 줄에 「규칙 14」 없음 REJECT ⓕ' 카드 id 없음 REJECT ⓖ' 둘 다 있음 OK ⓗ' 「합본 DA⑥ 생략」 REJECT ⓘ' 변이 3 ⓙ' 기존 5길 회귀
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team/bin"
LINT="$KIT/ft-index-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design/planner src
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| planner | `design/planner/` | p | 현역 |\n' > design/TEAMS.md
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\nl2\nl3\n' > src/target.sh
printf '판정 1: HOLD\n' > design/da-r1.md                       # 라운드 1
printf '판정 2: HOLD\n판정 3: HOLD\n' > design/da-r2.md         # 라운드 2 (내용이 다르다)
cp design/da-r1.md design/da-r1-copy.md                          # ⓓ' 내용 같은 2파일
printf '판정: HOLD\nHOLD 사유: 두 번째 보류\n' > design/da-holdwords.md   # ⓐ' 낱말 2회 · 라운드 1개
printf '판정 1: APPROVE\n' > design/da-ok.md
printf '판정 1: HOLD\n판정 2: APPROVE\n' > design/da-approve-last.md
{ echo '# 시험용 planner 원장'
  echo '- **2654** (시험) 카드 사전검증 «규칙 14» 생략 승인 — r767 합본 DA⑥ 고정'
  echo '- **9001** (시험) 사전 DA 2회 소진 → ① 조건부 승인 · 잔여 HOLD 고정'
  echo '- **9002** (시험) 규칙 14 생략 승인 — 무관한 카드 e9 의 판정'
  echo '- **7001** (시험) 규칙 14 — e10 카드 승인'
  echo '- **7002** (시험) 규칙 14 — we1-export 승인'
  echo '- **7003** (시험) 규칙 14 — E1 재설계 승인'
  echo '- **7007** (시험) e1 카드 일반 승인'
  echo '- **7006** (시험) 규칙 14 — e9 카드'; } > design/planner/VERDICTS-planner-1-20261012.md
{ echo '# 시험용 planner 원장 2'; echo '- **7006** (시험) r767 일반 승인'; } > design/planner/VERDICTS-planner-2-20261013.md   # 같은 번호가 2파일에 나뉜 꼴
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
export FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md" FT_CARD_REQUIRE_PREVERIFY=1

mkc() {  # <이름> <사전검증 본문> <완료 조건 본문> → 카드 경로
  local f="$T/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; printf '%b\n' "$3"
    echo "## 사전검증"; printf '%b\n' "$2"
    echo "## 조사 근거"; echo '- src/target.sh:2 확인'
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
run() { ( env -u TMUX -u TMUX_PANE bash "$1" "$2" 2>&1 ); }   # <린트> <카드>
expect_ok()  { local out rc; out="$(run "${3:-$LINT}" "$1")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$rc $out"; }
expect_rej() { local out rc; out="$(run "${4:-$LINT}" "$1")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -qF "$3" && ok "$2" || bad "$2 → rc=$rc $out"; }

R2='소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 2654'
DONE='시험 통과.\n합본 DA⑥: 구현 뒤 외부 DA 1문항'
ROUNDS="규칙 14 는 보류 2회부터"

# ⓐ' (빨강 먼저) DA: 1줄 · 그 파일에 HOLD 낱말 2회 → 라운드는 1개다
expect_rej "$(mkc r767-a '소환: 규칙14\nDA: design/da-holdwords.md\n- 규칙 14: 판정 2654' "$DONE")" "ⓐ' 라운드 1개(낱말 2회) REJECT" "$ROUNDS"

# ⓑ' 라운드 2개 → 통과 + INFO
B="$(mkc r767-b "$R2" "$DONE")"
expect_ok "$B" "ⓑ' DA 줄 2개(r1·r2 · 각 마지막 HOLD) → OK"
out="$(run "$LINT" "$B")"
echo "$out" | grep -qxF "INFO 사전검증: 규칙 14 · 판정 2654 · 합본 DA⑥ 필수 · DA: 줄 2개 = 라운드 2 으로 셈(원문·요약 중복 금지)" && ok "ⓑ' INFO 줄 바이트 동일" || bad "ⓑ' INFO 줄 → $out"

# ⓒ' 같은 경로 2줄 = 라운드 1개
expect_rej "$(mkc r767-c '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r1.md\n- 규칙 14: 판정 2654' "$DONE")" "ⓒ' 같은 경로 2줄 REJECT" "$ROUNDS"

# ⓓ' 경로는 다르나 내용이 같다 = 라운드 1개
expect_rej "$(mkc r767-d '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r1-copy.md\n- 규칙 14: 판정 2654' "$DONE")" "ⓓ' 내용 같은 2파일 REJECT" "$ROUNDS"

# ⓔ' 원장 줄은 있으나 「규칙 14」 가 없다
expect_rej "$(mkc r767-e '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 9001' "$DONE")" "ⓔ' 원장 줄에 「규칙 14」 없음 REJECT" "카드 id(r767) 가 없다"
# ⓕ' 「규칙 14」 는 있으나 카드 id 가 없다
expect_rej "$(mkc r767-f '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 9002' "$DONE")" "ⓕ' 원장 줄에 카드 id 없음 REJECT" "카드 id(r767) 가 없다"
# ⓖ' 둘 다 있으면 통과 (ⓑ' 가 그 길 — 재확인)
expect_ok "$(mkc r767-g "$R2" "$DONE")" "ⓖ' 원장 줄에 «규칙 14» + 카드 id 둘 다 → OK"

# ⓗ' 「합본 DA⑥ 생략」 꼴
expect_rej "$(mkc r767-h "$R2" '시험 통과.\n합본 DA⑥ 생략 — 구현 뒤 DA 없이 닫는다')" "ⓗ' 합본 DA⑥ 생략 REJECT" "합본 DA⑥ 를 생략하는 꼴"

# r2 ⓐ — 생략 낱말은 «붙어 있을 때만»
expect_ok  "$(mkc r767-a2 "$R2" '시험 통과.\n합본 DA⑥ — 잔여 HOLD 없음 확인')" "r2ⓐ 「합본 DA⑥ — 잔여 HOLD 없음 확인」 통과"
expect_rej "$(mkc r767-a3 "$R2" '시험 통과.\n합본 DA⑥: 불요')" "r2ⓐ 「합본 DA⑥: 불요」 REJECT" "합본 DA⑥ 를 생략하는 꼴"

# r2 ⓑ — 카드 id 경계 (부분 문자열 금지)
expect_rej "$(mkc r76-b '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 2654' "$DONE")" "r2ⓑ r76 카드 + 원장 「규칙 14 … r767」 → REJECT(경계)" "카드 id(r76) 가 없다"
expect_rej "$(mkc e1-b '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 7001' "$DONE")" "r2ⓑ e1 카드 + 원장 「규칙 14 — e10」 → REJECT" "카드 id(e1) 가 없다"
expect_rej "$(mkc e1-b2 '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 7002' "$DONE")" "r2ⓑ e1 카드 + 원장 「규칙 14 — we1-export」 → REJECT" "카드 id(e1) 가 없다"
expect_ok  "$(mkc e1-c '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 7003' "$DONE")" "r2ⓑ e1 카드 + 원장 「규칙 14 — E1 재설계」 → 통과(대소문자 무시)"
# r2 ⓒ — 같은 번호가 원장 2파일에 나뉘면 «한 줄» 조건 깨짐
expect_rej "$(mkc r767-c2 '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 7006' "$DONE")" "r2ⓒ 같은 번호 2파일(규칙14 줄 + id 줄 따로) → REJECT" "카드 id(r767) 가 없다"
expect_rej "$(mkc e1-d '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 7007' "$DONE")" "r2ⓓ 원장 줄에 id 만 있고 「규칙 14」 없음 → REJECT" "카드 id(e1) 가 없다"

# ⓙ' 기존 길 회귀 — 판정 번호 없음 / 표식 없음 / 마지막 APPROVE / 기존 세 길 출력 바이트
expect_rej "$(mkc r767-i "$R2" '시험 통과.')" "ⓙ' 완료 조건 「합본 DA⑥」 없음 REJECT" "완료 조건에 「합본 DA⑥」 표식 없음"
expect_rej "$(mkc r767-j '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-r2.md\n- 규칙 14: 판정 9999' "$DONE")" "ⓙ' 원장에 판정 9999 없음 REJECT" "planner 원장에 판정 9999 줄 없음"
expect_rej "$(mkc r767-k '소환: 규칙14\nDA: design/da-r1.md\nDA: design/da-approve-last.md\n- 규칙 14: 판정 2654' "$DONE")" "ⓙ' 마지막 DA 줄이 APPROVE REJECT" "APPROVE 면 「소환: 예」 로"
OLD="$T/old-lint.sh"; git -C "$HERE" show origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-index-lint.sh > "$OLD" 2>/dev/null
if [ -s "$OLD" ]; then
  expect_rej "$B" "ⓙ' 구판(origin/main)은 규칙14 카드를 REJECT(빨강)" "「소환: 예」 또는 「소환: 아니오」 줄 없음" "$OLD"
else bad "ⓙ' 구판 사본을 못 떴다 (origin/main 경로 확인)"; fi
CG="$(mkc g '소환: 예\nDA: design/da-ok.md' '시험 통과.')"
out="$(run "$LINT" "$CG")"; [ "$out" = "OK $CG (ledger=design/LEDGER.md)" ] && ok "ⓙ' 「소환: 예」 APPROVE 출력 바이트 동일" || bad "ⓙ' 예 → $out"
CG2="$(mkc g2 '소환: 아니오\n면제: 오타 수정 한 줄이라 설계 불필요 — arch 서명 byz-harness-arch-claude#6' '시험 통과.')"
out="$(run "$LINT" "$CG2")"; [ "$out" = "OK $CG2 (ledger=design/LEDGER.md)" ] && ok "ⓙ' 「소환: 아니오」 면제 출력 바이트 동일" || bad "ⓙ' 아니오 → $out"
CG3="$(mkc g3 '소환: 예\nDA: design/da-r2.md\n- lint 예외 1건: 판정 9001 ① 조건부 승인' '시험 통과.\n잔여 HOLD: 시험 잔여 결함 고정')"
out="$(run "$LINT" "$CG3")"
[ "$out" = "INFO 사전검증: DA 마지막 판정 HOLD — planner 판정 9001 조건부 승인으로 통과
OK $CG3 (ledger=design/LEDGER.md)" ] && ok "ⓙ' HOLD 조건부 예외 출력 바이트 동일" || bad "ⓙ' 조건부 → $out"

# ⓘ' 변이 3 — 검사를 지우면 그 카드가 «통과해 버린다»(= 그 검사가 실제로 막고 있다)
MUT="$T/mut"; mkdir -p "$MUT"; for f in "$KIT"/*; do ln -s "$f" "$MUT/"; done; rm -f "$MUT/ft-index-lint.sh"
mut() { sed -E "$1" "$LINT" > "$MUT/ft-index-lint.sh"; bash -n "$MUT/ft-index-lint.sh" || bad "변이 문법"; }
mut 's|\[ "\$cnt" -ge 2 \]|[ "$(grep -owE HOLD "${_ds[@]}" 2>/dev/null \| wc -l)" -ge 2 ]|'
out="$(run "$MUT/ft-index-lint.sh" "$T/r767-a.md")"; [ $? -eq 0 ] && ok "ⓘ' 라운드 셈→낱말 셈 되돌림 → ⓐ' 가 통과해 버린다(변이 검출)" || bad "ⓘ' 라운드 변이 → 여전히 REJECT: $out"
mut '/무관한 판정 번호/d'
out="$(run "$MUT/ft-index-lint.sh" "$T/r767-e.md")"; [ $? -eq 0 ] && ok "ⓘ' 원장 줄 내용 검사 삭제 → ⓔ' 가 통과해 버린다(변이 검출)" || bad "ⓘ' 원장 변이 → 여전히 REJECT: $out"
mut '/합본 DA⑥ 를 생략하는 꼴/d'
out="$(run "$MUT/ft-index-lint.sh" "$T/r767-h.md")"; [ $? -eq 0 ] && ok "ⓘ' 생략 낱말 검사 삭제 → ⓗ' 가 통과해 버린다(변이 검출)" || bad "ⓘ' 생략 변이 → 여전히 REJECT: $out"

# r2 ⓓ 변이 쪼개기(4) — 각 검사를 «따로» 지우면 그 반례가 통과/오거절된다
mutb() { sed "$1" "$LINT" > "$MUT/ft-index-lint.sh"; bash -n "$MUT/ft-index-lint.sh" || bad "변이 문법"; }   # BRE(괄호·|·? 를 글자로 다룬다)
mutp() { S="$1" R="$2" perl -pe 's/\Q$ENV{S}\E/$ENV{R}/' "$LINT" > "$MUT/ft-index-lint.sh"; bash -n "$MUT/ft-index-lint.sh" || bad "변이 문법"; }   # 글자 그대로 치환(quotemeta — 메타문자 포함 검색어용)
mutb '/(규칙|룰) ?14/d'
out="$(run "$MUT/ft-index-lint.sh" "$T/e1-d.md")"; [ $? -eq 0 ] && ok "r2ⓓ 「규칙 14」 검사만 삭제 → id 만 있는 원장 줄이 통과해 버린다" || bad "r2ⓓ 규칙14 변이 → $out"
mutp 'grep -qiE "(^|[^[:alnum:]])${id}([^[:alnum:]]|$)"' 'grep -qiF -- "$id"'
out="$(run "$MUT/ft-index-lint.sh" "$T/r76-b.md")"; [ $? -eq 0 ] && ok "r2ⓓ id 경계→부분 문자열 → r76 카드가 r767 줄에 통과해 버린다" || bad "r2ⓓ id 경계 변이 → $out"
mutb 's@ || continue@@'
out="$(run "$MUT/ft-index-lint.sh" "$T/r767-c2.md")"; [ $? -eq 0 ] && ok "r2ⓓ 같은 줄 조건 해제(|| continue 삭제) → ⓒ 가 통과해 버린다" || bad "r2ⓓ 같은 줄 변이 → $out"
mutp '합본 DA⑥[[:space:]」:—-]*(생략|없음|면제|불요)' '합본 DA⑥.*(생략|없음|면제|불요)'
out="$(run "$MUT/ft-index-lint.sh" "$T/r767-a2.md")"; [ $? -eq 1 ] && ok "r2ⓓ 붙은 낱말→줄 전체 → 「잔여 HOLD 없음 확인」 이 오거절된다" || bad "r2ⓓ 낱말 변이 → $out"

# 격리 — 판정은 임시 리포에서 · 원장은 ref 로만 본다
[ "$(cd "$T" && git rev-parse --show-toplevel)" = "$T" ] && ok "격리: 판정이 임시 리포 안에서만 돈다" || bad "격리: 임시 리포 밖에서 돌았다"
git update-ref -d refs/remotes/origin/main
expect_rej "$B" "격리: origin/main ref 없음 → 원장 확인 불가 REJECT(로컬 파일로 새지 않는다)" "원장 확인 불가"
git update-ref refs/remotes/origin/main HEAD
expect_ok "$B" "격리: ref 복구 → 다시 OK"

echo "fail=$fail"; [ $fail -eq 0 ]
