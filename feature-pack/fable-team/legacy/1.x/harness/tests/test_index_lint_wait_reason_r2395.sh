#!/usr/bin/env bash
# test_index_lint_wait_reason_r2395.sh — r2395 K4: 대기/ 카드에 «- 대기 사유:» 줄이 없으면 사유 1줄(새 카드 = REJECT · 옛 카드 = WARN 만).
#   ⑦ 새 카드 줄 없음 = REJECT · ⑧ 새 카드 줄 있음 = OK · ⑨ 옛 카드 줄 없음 = OK + WARN · ⑫ 진행/ 카드 줄 없음 = 사유 0(단계 가림)
#   ⑬ 머리 0 · 본문 예시에만 그 줄 = REJECT(머리 한정 · DA#56 H1) · ⑭ 머리 표식 = OK
#   변이 M4 = 새 카드 REJECT 를 WARN 으로(⑦ FAIL) · M7 = 단계 가림 삭제(⑫ FAIL) · M8 = 머리 한정 지움(⑬ FAIL) · 기준판(팩 origin/main) = ⑦ Red.
# 임시 리포만(실 카드·실 리포·네트워크 0) · 하드 룰 22: 이 파일 70초 안(단계별 초를 찍는다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2395_T0=$SECONDS; R2380_T0=$SECONDS
. "$HERE/scripts/_r2380_lint_world.sh"
r2380_lint_world "$T" || { echo "FAIL 세계"; exit 1; }
export FT_CARD_ADDED_MAP_FILE="$T/added.tsv"   # 첫 추가일 = 사전 파일(새/옛 카드를 시험이 정한다 · git log 0)
: > "$FT_CARD_ADDED_MAP_FILE"

mkcard() {  # $1=단계 폴더 $2=이름 $3=첫 추가일 $4=머리 줄들 → 카드 경로 stdout
  local f="$W/design/harness/indices/$1/$2.md"
  mkdir -p "$(dirname "$f")"
  { echo "# 인덱스: $2"; echo '- 제안서: 없음 — 시험 카드'; echo '- 설치: 없음'; printf '%s\n' "$4"; echo "## 골 원문"
    printf '%s\n%s\n%s\n' "$R2380_G1" "$R2380_G2" "$R2380_G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '시험 통과.'
    echo "## 계약↔시험 대응표"; echo '| 계약 | 입력 | 기대 | 시험 |'; echo '|---|---|---|---|'
    echo '| C1 대기 사유 줄 | 줄 없음 | 새 카드 REJECT | ⑦ |'; echo '| C2 단계 가림 | 진행/ 카드 | 사유 0 | ⑫ |'
    echo "## 상태"; echo '- 시험'; } > "$f"
  printf '%s\t%s\n' "$2.md" "$3" >> "$FT_CARD_ADDED_MAP_FILE"
  printf '%s' "$f"
}
lint_at() {  # $1=bin 폴더 $2=카드 — 출력은 $OUT, rc 를 돌려준다
  OUT="$( cd "$W" && bash "$1/ft-index-lint.sh" "$2" 2>&1 )"; return $?
}
reason() { printf '%s' "$OUT" | grep -c '^  - 대기/ 카드에 「- 대기 사유:」 줄 없음'; }   # REJECT 사유만(WARN 줄은 안 센다)

C7="$(mkcard 대기 new-bare 2026-11-21 '- 배정: 없음')"
C8="$(mkcard 대기 new-ok 2026-11-21 $'- 배정: 없음\n- 대기 사유: 없음')"
C9="$(mkcard 대기 old-bare 2026-11-01 '- 배정: 없음')"
C12="$(mkcard 진행 prog-bare 2026-11-21 '- 배정: 없음')"
C13="$(mkcard 대기 body-only 2026-11-21 '- 배정: 없음')"; printf '\n## 참고 예시\n- 대기 사유: 없음\n' >> "$C13"   # 머리 0 · 본문에만 그 줄

lint_at "$KIT" "$C7"; rc=$?
{ [ $rc -eq 1 ] && [ "$(reason)" -eq 1 ]; }; ck "⑦ 새 카드 · 줄 없음 = REJECT(사유 1줄)" $?
lint_at "$KIT" "$C8"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$OUT" | grep -q '^OK ' && [ "$(reason)" -eq 0 ]; }; ck "⑧ 새 카드 · 줄 있음 = OK" $?
lint_at "$KIT" "$C9"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$OUT" | grep -q '^WARN .*대기 사유' && [ "$(reason)" -eq 0 ]; }; ck "⑨ 옛 카드 · 줄 없음 = OK + WARN 1줄" $?
lint_at "$KIT" "$C12"; rc=$?
{ [ $rc -eq 0 ] && ! printf '%s' "$OUT" | grep -q '대기 사유'; }; ck "⑫ 진행/ 카드 = 사유 0(단계 가림)" $?
lint_at "$KIT" "$C13"; rc=$?
{ [ $rc -eq 1 ] && [ "$(reason)" -eq 1 ]; }; ck "⑬ 머리 0 · 본문 예시에만 그 줄 = REJECT(머리 한정)" $?
lint_at "$KIT" "$C8"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$OUT" | grep -q '^OK ' && [ "$(reason)" -eq 0 ]; }; ck "⑭ 머리 표식 = OK(본문 0 이어도)" $?
lap 신판
cp -R "$KIT" "$T/mut"; SRC="$T/mut/ft-index-lint.sh"; cp "$SRC" "$T/orig.sh"
mutant() {  # $1=이름 $2=옛 글 $3=새 글 → 사본 판정기(사본은 매번 원본에서 다시 만든다)
  cp "$T/orig.sh" "$SRC"
  python3 - "$SRC" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
mutant M4 '  if [ "$new" = 1 ]; then bad+=("대기/ 카드에' '  if false; then bad+=("대기/ 카드에' || { echo "FAIL 변이 M4 글자 없음"; fail=$((fail+1)); }
lint_at "$T/mut" "$C7"; rc=$?
{ [ $rc -eq 0 ] && [ "$(reason)" -eq 0 ]; }; ck "M4 새 카드 REJECT 를 WARN 으로 = ⑦ FAIL" $?
mutant M7 'case "$1" in */대기/*) ;; *) return 0;; esac' ':' || { echo "FAIL 변이 M7 글자 없음"; fail=$((fail+1)); }
lint_at "$T/mut" "$C12"; rc=$?
{ [ $rc -eq 1 ] && [ "$(reason)" -eq 1 ]; }; ck "M7 단계 가림 삭제 = ⑫ FAIL" $?
mutant M8 "awk '/^##[[:space:]]/{exit} {print}' \"\$1\" | grep -qE '^[-*][[:space:]]*대기 사유:'" "grep -qE '^[-*][[:space:]]*대기 사유:' \"\$1\"" || { echo "FAIL 변이 M8 글자 없음"; fail=$((fail+1)); }
lint_at "$T/mut" "$C13"; rc=$?
{ [ $rc -eq 0 ] && [ "$(reason)" -eq 0 ]; }; ck "M8 머리 한정 지움(파일 전체 grep) = ⑬ FAIL" $?
cp "$T/orig.sh" "$SRC"
lint_at "$T/mut" "$C7"; rc=$?
{ [ $rc -eq 1 ] && [ "$(reason)" -eq 1 ]; }; ck "원본으로 같은 사례 1회 더 = PASS" $?
lint_at "$T/mut" "$C13"; rc=$?
{ [ $rc -eq 1 ] && [ "$(reason)" -eq 1 ]; }; ck "원본으로 ⑬ 사례 1회 더 = PASS" $?
lap 변이
mkdir -p "$T/base"
git -C "$PACK" archive origin/main feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin | tar -x -C "$T/base" 2>/dev/null
BASE="$T/base/feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin"
if [ -f "$BASE/ft-index-lint.sh" ]; then
  lint_at "$BASE" "$C7"; rc=$?
  { [ $rc -eq 0 ] && [ "$(reason)" -eq 0 ]; }; ck "기준판 ⑦ FAIL(새 카드 줄 없음 · 사유 0)" $?
else
  echo "WARN 기준판 없음(origin/main 에 팩 없음) — 대조 건너뜀"
fi
lap 기준판
echo "fail=$fail"; [ "$fail" -eq 0 ]
