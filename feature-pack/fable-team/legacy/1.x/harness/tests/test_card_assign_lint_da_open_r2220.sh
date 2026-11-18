#!/usr/bin/env bash
# test_card_assign_lint_da_open_r2220.sh — r2220 카드 lint(ft-index-lint ⑭): OPEN 카드 · 머리 «- 배정: 없음» · 본문 «사전 DA 확인칸» 있음 ·
# 줄머리 «- 사전 DA APPROVE» 0 → stdout «WARN <부른 인자> — 사전 DA 판정 전인데 「- 배정: 없음」 …» 1줄 · rc0(판정 그대로).
# 반례 ②~⑧ + 변이 M1~M3(각 변이 = 원본 대조 1회). 임시 git 리포 · 임시 카드 · 실 리포·실 카드·실 keeper 0 · sleep 0.
# 돌리기: timeout 70 bash harness/tests/test_card_assign_lint_da_open_r2220.sh  (TOOL=<다른 판 .py> 로 기준판 대조)
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; TOOL="${TOOL:-$BIN/ft_card_assign_watch.py}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
R="$T/r"; D=design/alpha/indices; mkdir -p "$R/$D/대기" "$R/$D/완성" "$R/src"
git -C "$R" init -q -b main; export FT_ROOT="$R"
printf 'l1\n' > "$R/src/t.sh"; printf '골 1\n골 2\n골 3\n' > "$T/goal.txt"
echo '원장: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$R/design/LEDGER.md"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| alpha | `design/alpha/` | a | 현역 |\n' > "$R/design/TEAMS.md"
TAIL='— 사전 DA 판정 전인데 「- 배정: 없음」'
card() {  # card <폴더> <이름> <배정 값> [상태 절 추가 줄…] → 상대경로(리포 기준)
  local f="$D/$1/$2.md"; shift 2; local v="$1"; shift
  printf '%s\n' "# 인덱스: $(basename "$f" .md) — 끝: 시험" '- 제안서: 없음 — 시험 카드' "- 배정: $v" '## 골 원문' '골 1' '골 2' '골 3' '## 골좌표' \
    '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '## 배경' '시험.' '## 구현 범위' '1. src/t.sh 수정' '## 완료 조건' '- 시험.' \
    '## 계약↔시험 대응표' '| 계약 | 시험 |' '|---|---|' '| ① 시험 | ⓐ 시험 |' '## 상태' '- 2026-11-18 · 생성' "$@" > "$R/$f"
  echo "$f"
}
lint() { OUT="$(cd "$R" && python3 "${2:-$TOOL}" lint "$1" 2>&1)"; RC=$?; }
warn() {  # warn <이름> <카드> [도구] — WARN 1줄(부른 인자 그대로) · rc0
  lint "$2" "${3:-}"
  [ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && case "$OUT" in "WARN $2 $TAIL"*) true;; *) false;; esac \
    && ok "$1 → WARN 1줄 rc0" || bad "$1 rc=$RC :: $OUT"
}
quiet() { lint "$2" "${3:-}"; [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "$1 → 출력 0 rc0" || bad "$1 rc=$RC :: $OUT"; }
CHK='- 사전 DA 확인칸: ⓐ 시험'
C2="$(card 대기 c2 없음 "$CHK")"
C3="$(card 대기 c3 '대기(DA · 2026-11-18T07:25)' "$CHK")"
C4="$(card 대기 c4 없음 "$CHK" '- 사전 DA APPROVE · 2026-11-18 · 시험')"
C8="$(card 대기 c8 없음 "$CHK" '- 계약 줄: … «사전 DA APPROVE» 없음 …')"
C5="$(card 완성 c5 없음 "$CHK")"
C6="$(card 대기 c6 없음)"
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm cards
warn "② 대기/ · 확인칸 · APPROVE 0 · 배정 없음(상대경로 인자)" "$C2"
quiet "③ 배정 = 대기(DA · 시각)" "$C3"
quiet "④ 줄머리 «- 사전 DA APPROVE» 있음" "$C4"
warn "⑧ 본문 글자 인용만(줄머리 판정 줄 0)" "$C8"
quiet "⑤ 완성/ (CLOSED)" "$C5"
quiet "⑥ 확인칸 줄 없음" "$C6"
lap cases

# ⑦ ft-index-lint 끝에서 끝 — WARN 줄 · rc0 · OK 줄 그대로
IX="$(cd "$R" && FT_GOAL_LEDGER=design/LEDGER.md FT_GOAL_LINES_FILE="$T/goal.txt" bash "$KIT/ft-index-lint.sh" "$C2" 2>&1)"; IXRC=$?
[ "$IXRC" = 0 ] && printf '%s\n' "$IX" | grep -qF "WARN $C2 $TAIL" && printf '%s\n' "$IX" | grep -q "^OK $C2 " \
  && ok "⑦ ft-index-lint → WARN 사전 DA 판정 전 · OK · rc0" || bad "⑦ rc=$IXRC :: $IX"
lap e2e

# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조)
mut() { mkdir -p "$T/$1"; cp "$BIN"/ft_*.py "$T/$1/"; python3 - "$TOOL" "$T/$1/ft_card_assign_watch.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mrun() {  # mrun <이름> <변이 도구> <카드> <원본 기대 출력 줄 수> — 변이 = 반대 결과여야 잡힘
  lint "$3" "$2"; local m; m="$(printf '%s' "$OUT" | grep -c .)"; lint "$3"; local o; o="$(printf '%s' "$OUT" | grep -c .)"
  [ "$m" != "$4" ] && [ "$o" = "$4" ] && ok "$1 잡힘(변이 줄=$m · 원본 줄=$o)" || bad "$1 변이 줄=$m 원본 줄=$o"
}
mut m1 ' and not re.search(r"^- 사전 DA APPROVE", text, re.M)' ''
mrun "M1 APPROVE 조건 뺌 → ④" "$T/m1/ft_card_assign_watch.py" "$C4" 0
mut m2 'val == "없음" and ' ''
mrun "M2 배정 값 조건 뺌 → ③" "$T/m2/ft_card_assign_watch.py" "$C3" 0
mut m3 're.search(r"^- 사전 DA APPROVE", text, re.M)' '"사전 DA APPROVE" in text'
mrun "M3 줄머리 조건을 본문 어디든으로 → ⑧" "$T/m3/ft_card_assign_watch.py" "$C8" 1
lap mutation

cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit ft_card_assign_watch.py 같은 내용" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && ok "py_compile" || bad "문법"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
