#!/usr/bin/env bash
# test_card_assign_lint_human_reason_r2162.sh — r2162 카드 lint(ft-index-lint ⑭): 기준 시각(2026-11-17T12:00) 이후 «- 배정: 대기(사람 · 시각)» 은
# 머리에 «- 사람 사유: <kill|삭제|force push|외부 설정|새 범위|비용> …» 줄이 있어야 rc0 · 없으면 REJECT 1줄 rc1.
# 반례 ①~⑥ · ⑧ + 변이 M1~M3(각 변이 = 원본 대조 1회). 임시 git 리포 · 임시 카드 · lint 직접 호출 · 실 리포·실 원장 0 · sleep 0.
# 돌리기: timeout 70 bash harness/tests/test_card_assign_lint_human_reason_r2162.sh  (TOOL=<다른 판 .py> 로 기준판 대조)
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; TOOL="${TOOL:-$BIN/ft_card_assign_watch.py}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
R="$T/r"; H="$R/design/harness/indices"; mkdir -p "$H/대기" "$H/진행" "$H/완성" "$R/.fable-team/state/card-assign"
git -C "$R" init -q -b main; export FT_ROOT="$R"
MSG='사람 보류 사유 없음 — «- 사람 사유: <kill|삭제|force push|외부 설정|새 범위|비용> …» 또는 대기(DA · 시각) · 없음'
card() {  # card <폴더> <배정 값> [머리 추가 줄] [상태 절 줄] → 카드 경로
  local f="$H/$1/c$RANDOM.md"
  { echo "# 인덱스: c — 끝: 시험"; echo "- 배정: $2"; [ -n "${3:-}" ] && echo "$3"; echo "- 설치: 없음"; echo; echo "## 상태"; [ -n "${4:-}" ] && echo "$4"; } > "$f"
  echo "$f"
}
lint() { OUT="$(python3 "${2:-$TOOL}" lint "$1" 2>&1)"; RC=$?; }
expect() {  # expect <이름> <rc> <카드> [도구]
  lint "$3" "${4:-}"
  if [ "$2" = 1 ]; then [ "$RC" = 1 ] && [ "$OUT" = "$MSG" ] && ok "$1 → REJECT 1줄 rc1" || bad "$1 rc=$RC :: $OUT"
  else [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "$1 → rc0" || bad "$1 rc=$RC :: $OUT"; fi
}
NEW='대기(사람 · 2026-11-17T13:00)'
C1="$(card 대기 "$NEW")"
C2="$(card 대기 "$NEW" '- 사람 사유: 되돌릴 수 있음 · 오빠 확인')"
C3="$(card 대기 "$NEW" '- 사람 사유: force push — 공유 가지 되감기')"
C4="$(card 대기 "$NEW" '- 사람 사유: 외부')"
C5="$(card 대기 '대기(사람 · 2026-11-04T09:58)')"
C6="$(card 대기 '대기(DA · 2026-11-17T13:00)')"; C6b="$(card 완성 "$NEW")"
C8="$(card 대기 "$NEW" '' '- 사람 사유: force push — 옛 일')"
expect "① 대기/ 새 사람 보류 · 사유 줄 0" 1 "$C1"
expect "② 사유 첫 낱말 허용 밖" 1 "$C2"
expect "③ 사유 force push" 0 "$C3"
expect "④ 사유 «외부» 만(앞자리 경계)" 1 "$C4"
expect "⑤ 기준 이전 사람 보류 · 사유 줄 0" 0 "$C5"
expect "⑥ 대기(DA · 기준 이후) · 사유 줄 0" 0 "$C6"
expect "⑥ 완성/ 폴더의 ① 꼴" 0 "$C6b"
expect "⑧ 머리 밖(상태 절) 사유 줄만" 1 "$C8"
C3s="$(card 진행 '대기(사람 · 2026-11-17T12:00:00)' '- 사람 사유: 외부 설정 — Slack 앱')"
expect "③ 진행/ · 기준 시각 같음(초 칸) · 외부 설정 — Slack 앱" 0 "$C3s"
lap cases

# ── 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조)
mut() { mkdir -p "$T/$1"; cp "$BIN"/ft_*.py "$T/$1/"; python3 - "$TOOL" "$T/$1/ft_card_assign_watch.py" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mrun() {  # mrun <이름> <변이 도구> <카드> <원본 기대 rc> — 변이 = 반대 rc 여야 잡힘
  lint "$3" "$2"; local m=$RC; lint "$3"; local o=$RC
  [ "$m" != "$4" ] && [ "$o" = "$4" ] && ok "$1 잡힘(변이 rc=$m · 원본 rc=$o)" || bad "$1 변이 rc=$m 원본 rc=$o"
}
mut m1 '            return human_reason(text, vals[0])' '            return 0'
mrun "M1 사유 검사 지움 → ①" "$T/m1/ft_card_assign_watch.py" "$C1" 1
mrun "M1 사유 검사 지움 → ②" "$T/m1/ft_card_assign_watch.py" "$C2" 1
mut m2 ' or iso(m.group(1)) < iso(HUMAN_SINCE)' ''
mrun "M2 기준 시각 비교 지움 → ⑤" "$T/m2/ft_card_assign_watch.py" "$C5" 0
mut m3 'for ln in head(text) if ln.startswith("- 사람 사유:")' 'for ln in text.splitlines() if ln.startswith("- 사람 사유:")'
mrun "M3 사유 줄 찾기를 본문 전체로 → ⑧" "$T/m3/ft_card_assign_watch.py" "$C8" 1
lap mutation

cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit ft_card_assign_watch.py 같은 내용" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && ok "py_compile" || bad "문법"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
