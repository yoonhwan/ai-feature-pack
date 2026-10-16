#!/usr/bin/env bash
# test_verdict_row.sh — 판정 원장 «두 꼴»(글머리 `- **N**` · 표 행 `| N |`) 공용 함수 시험 (R255 · R257).
#   ⓐ fv_row_re 경계 · ⓑ fv_max 두 꼴 최대 · ⓒ 번호 0개 rc≠0 · ⓓ proxy-decide 다음 번호 = 표 최대+1
#   ⓔ 번호 0개 원장 → proxy-decide 발급 0 · ⓕ lint 가 표 행 «조건부 승인» 으로 HOLD 예외 통과(글머리도 그대로)
# 격리: 임시 FT_ROOT·상태·원장 + 임시 git 저장소 — 실 원장·실 상태·실 mbox 쓰기 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; KIT="$HERE/../../scripts/harness-install/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ===== ⓐⓑⓒ 공용 함수 =====
[ -f "$BIN/ft-verdict-row.sh" ] && bash -n "$BIN/ft-verdict-row.sh"; ck "함수 파일 존재 · bash -n" $?
. "$BIN/ft-verdict-row.sh" 2>/dev/null; rc=$?; ck "함수 파일 source" $rc
[ "$(wc -l < "$BIN/ft-verdict-row.sh" 2>/dev/null || echo 99)" -le 40 ]; ck "함수 파일 40줄 이하" $?
cmp -s "$BIN/ft-verdict-row.sh" "$KIT/ft-verdict-row.sh"; ck "키트 사본 cmp 0" $?

m() { printf '%s\n' "$1" | grep -qE "$(fv_row_re 1646)"; }
m '| 1646 | 00:2x | 내용 |';          ck "ⓐ 표 행 맞음" $?
m '|1646| 00:2x | 내용 |';            ck "ⓐ 표 행 공백 없음 맞음" $?
m '|   1646   | 00:2x | 내용 |';      ck "ⓐ 표 행 공백 여럿 맞음" $?
m '- **1646** 내용';                  ck "ⓐ 글머리 맞음" $?
! m '| 16460 | 00:2x | 내용 |';        ck "ⓐ 표 행 16460 안 맞음" $?
! m '| 11646 | 00:2x | 내용 |';        ck "ⓐ 표 행 11646 안 맞음" $?
! m '- **1646a** 내용';                ck "ⓐ 글머리 1646a 안 맞음" $?
! m '- **16460** 내용';                ck "ⓐ 글머리 16460 안 맞음" $?
! m '| 1 | 본문 1646 언급 |';           ck "ⓐ 다른 번호 행 본문의 1646 안 맞음" $?
fv_row_re abc >/dev/null 2>&1; [ $? = 2 ]; ck "ⓐ 숫자 아닌 n → rc 2" $?
fv_row_re '' >/dev/null 2>&1; [ $? = 2 ]; ck "ⓐ 빈 n → rc 2" $?

mixed="$(printf '%s\n' '- **1969** a' '- **1970** [대리] b' '| 1971 | 00:0x | c |' '| 1980 | 00:1x | d |' '|1975| e |' '- **1646a** x' '본문 2500 언급' '| 표머리 | 시각 |')"
[ "$(printf '%s\n' "$mixed" | fv_max)" = 1980 ]; ck "ⓑ 글머리 1970 + 표 1980 섞임 → 1980" $?
[ "$(printf '%s\n' '- **1970** a' '| 1960 | b |' | fv_max)" = 1970 ]; ck "ⓑ 글머리가 최대일 때 → 1970" $?
out="$(printf '%s\n' '본문만' '| 표머리 | 시각 |' | fv_max)"; rc=$?; [ "$rc" != 0 ] && [ -z "$out" ]; ck "ⓒ 번호 0개 → rc≠0 · 빈 출력" $?
out="$(printf '' | fv_max)"; rc=$?; [ "$rc" != 0 ] && [ -z "$out" ]; ck "ⓒ 빈 입력 → rc≠0 · 빈 출력" $?

# ===== ⓓⓔ proxy-decide =====
S="$T/state"; P="$T/planner"; mkdir -p "$S" "$P"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$P" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" = on ]; ck "준비: 자율 ON" $?
D() { out="$(cd "$T" && "$BASH" "$BIN/ft-proxy-decide.sh" --kind press-order --q "순서 $RANDOM" --choice "A 다음 B" --why 근거 --undo 되돌림 2>"$T/err")"; rc=$?; }

LD1="$P/VERDICTS-planner-1-20261001.md"; LD2="$P/VERDICTS-planner-2-20261015.md"
printf '%s\n' '- **1970** (오빠) 글머리 최대' '- **1969** a' > "$LD1"
printf '%s\n' '| 번호 | 시각 | 내용 |' '|---|---|---|' '| 1980 | 00:1x | 표 최대 |' '| 1971 | 00:0x | 표 |' > "$LD2"
D; [ "$rc" = 0 ] && grep -q '^PROXY 판정 1981 ' <<<"$out"; ck "ⓓ 표 행이 최신인 원장 → PROXY 판정 1981(표 최대+1)" $?
[ "$(tail -n 1 "$LD2")" != '| 1971 | 00:0x | 표 |' ] && grep -q '^- \*\*1981\*\* \[대리' "$LD2"; ck "ⓓ 새 줄이 최신 원장(planner-2)에 1981 로 기록" $?

printf '%s\n' '(번호 없는 원장)' '| 표머리 | 시각 |' > "$LD2"; : > "$LD1"
n0="$(cat "$P"/VERDICTS-*.md | wc -l)"
D; [ "$rc" = 5 ] && ! grep -q '^PROXY' <<<"$out" && grep -q '번호' "$T/err"; ck "ⓔ 번호 0개 → rc 5 · PROXY 0 · 사유에 «번호»" $?
[ "$(cat "$P"/VERDICTS-*.md | wc -l)" = "$n0" ]; ck "ⓔ 번호 0개 → 원장 줄 쓰기 0(지어낸 1 발급 0)" $?

# ===== ⓕ lint 표 행 조건부 승인 =====
LINT="$KIT/ft-index-lint.sh"; R="$T/repo"; mkdir -p "$R/design/planner" "$R/src"; cd "$R" && git init -q . || { echo "FAIL git init"; exit 1; }
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\n' > src/target.sh; printf '판정 1: HOLD\n' > design/da-hold.md
{ echo '| 번호 | 시각 | 내용 |'; echo '|---|---|---|'
  echo '| 9101 | 00:2x | (시험) 사전 DA 소진 → ① 조건부 승인 · 잔여 HOLD 를 완료 조건으로 고정 |'
  echo '| 9102 | 00:2x | (시험) 반려 판정 |'
  echo '| 91010 | 00:2x | (시험) 이건 ① 조건부 승인 인데 번호가 다르다 |'
  echo '- **9103** (시험) 글머리 ① 조건부 승인 · 잔여 HOLD'; } > design/planner/VERDICTS-planner-1-20261012.md
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1; git update-ref refs/remotes/origin/main HEAD
export FT_GOAL_LINES_FILE="$R/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md" FT_CARD_REQUIRE_PREVERIFY=1
mkc() {  # <이름> <예외 판정 번호> → 카드 경로
  local f="$R/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'; echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; printf '시험 통과.\n잔여 HOLD: 시험 잔여 결함 고정\n'
    echo "## 사전검증"; printf '소환: 예\nDA: design/da-hold.md\n- lint 예외 1건: 판정 %s ① 조건부 승인\n' "$2"
    echo "## 조사 근거"; echo '- src/target.sh:1 확인'; echo "## 상태"; echo '- 시험'; } > "$f"; echo "$f"
}
lint() { out="$(cd "$R" && bash "$LINT" "$1" 2>&1)"; rc=$?; }
lint "$(mkc t1 9101)"; [ $rc = 0 ] && grep -q '^INFO 사전검증: DA 마지막 판정 HOLD — planner 판정 9101 조건부 승인으로 통과$' <<<"$out"; ck "ⓕ 표 행 «| 9101 | … ① 조건부 승인» → OK + INFO" $?
lint "$(mkc t2 9103)"; [ $rc = 0 ] && grep -q '^INFO ' <<<"$out"; ck "ⓕ 글머리 꼴 9103 도 그대로 통과" $?
lint "$(mkc t3 9102)"; [ $rc = 1 ] && grep -q 'APPROVE 가 아니다 (HOLD)' <<<"$out"; ck "ⓕ 표 행인데 조건부 승인 아님(9102) → REJECT" $?
lint "$(mkc t4 910)"; [ $rc = 1 ] && grep -q 'APPROVE 가 아니다 (HOLD)' <<<"$out"; ck "ⓕ 번호 경계: 910 은 9101·91010 에 안 걸림 → REJECT" $?
lint "$(mkc t5 9999)"; [ $rc = 1 ] && grep -q 'APPROVE 가 아니다 (HOLD)' <<<"$out"; ck "ⓕ 원장에 없는 번호 → REJECT" $?
# 함수 파일이 없으면 조용히 통과하지 않는다
FK="$T/kit-nofv"; cp -R "$KIT" "$FK"; rm -f "$FK/ft-verdict-row.sh"
out="$(cd "$R" && bash "$FK/ft-index-lint.sh" "$R/t1.md" 2>&1)"; rc=$?; [ $rc = 1 ] && ! grep -q '^INFO ' <<<"$out" && grep -q 'ft-verdict-row' <<<"$out"; ck "ⓕ 함수 파일 없음 → REJECT 줄(조용한 통과 0)" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
