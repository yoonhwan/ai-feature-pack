#!/usr/bin/env bash
# test_goal_table_budget_width8_r1210.sh — 원장 머리 « · 상태 낡음»(+바이트)이 붙자 12자 폭으로도 골 표가 예산(1600B)을 넘어 전 팀 [발주]가 막히던 것 → 폭 사다리에 8자 단계를 더했다(r1210).
#   ⓐ R1 낡은 원장 + 12자에서 넘치고 8자에서 드는 정본 = 직전 판 rc1 «예산 초과» → 지금 판 rc0 · ≤1600B · 골 원문 절단 0 · 칸 폭 8자(+«…» = 9자)
#   ⓑ R2 짧은 정본 = 직전 판과 바이트 같은 출력(회귀 0 · 24자 폭 그대로)
#   ⓒ R3 8자로도 넘치는 정본 = ERROR 골 표 예산 초과 rc1(골 원문 절단 0)
#   ⓓ R4 8자 폭 렌더 블록 + 골좌표 = check GOAL-OK
#   ⓔ bin·kit 같은 내용(cmp0)   ⓕ 변이: 8자 단계 뺌 → ⓐ 픽스처 rc1(빨강이 잡힌다)   ⓖ 격리 = 실 쪽지 0
# 격리 = 임시 git 리포·임시 루트·가짜 mbox(인자 기록만) — 실 리포·실 쪽지·외부 호출 0 · 자기 재호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd -- "$HERE/../.." && pwd)"
TOOL="$REPO/harness/bin/ft_goal_table.py"; KIT="$REPO/harness/kit/fable-team/bin/ft_goal_table.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
CPATH=design/planner/AUTONOMY-GOAL-A6-20261031.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner"; git -C "$R" init -q -b main
export MBOX_LOG="$T/mbox.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$MBOX_LOG"\n' > "$T/mbox.sh"
PAD40="$(printf 'y%.0s' $(seq 1 40))"; PAD40E="$(printf 'z%.0s' $(seq 1 40))"; PAD40S="$(printf 'q%.0s' $(seq 1 40))"
# 직전 판(고정 sha · r1210 직전 팩 main) 도구 = 대조군 · origin/main 을 쓰지 않는다(r733 · 이 카드가 들어가면 대조군도 고친 판이 된다).
mkdir -p "$T/prevbin" "$T/mutbin"; cp "$REPO"/harness/bin/*.py "$T/prevbin/"; cp "$REPO"/harness/bin/*.py "$T/mutbin/"
TOP="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"; PREV=""; PREVSHA=6d448481a774693b332f83b942a133918898689b
if [ -n "$TOP" ]; then REL="${TOOL#"$TOP"/}"; git -C "$TOP" show "$PREVSHA:$REL" > "$T/prevbin/ft_goal_table.py" 2>/dev/null && PREV="$T/prevbin/ft_goal_table.py"; fi
canon() {  # <골 원문 길이> — 골 6행 · 팀·증거 칸 40자
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local i pad; pad="$(printf 'x%.0s' $(seq 1 "$1"))"
  for i in 1 2 3 4 5 6; do printf '| g%s-%s | t%s | e%s |\n' "$i" "$pad" "$PAD40" "$PAD40E"; done
}
canon_short() {
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local i; for i in 1 2 3 4 5 6; do printf '| 골%s | 팀%s | 증거%s |\n' "$i" "$i" "$i"; done
}
ledger() {  # <상태 칸> — 마지막 갱신 2026-01-01 = 늘 24h 넘김(머리 « · 상태 낡음»)
  printf '# 원장\n\n> 마지막 갱신: 2026-01-01 09:00 · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n'
  local i; for i in 1 2 3 4 5 6; do printf '| 렛%s | s%s | 남%s |\n' "$i" "$1" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
render() {  # [<도구 경로>] — 격리 env
  local tool="${1:-$TOOL}"
  env -u FT_GOAL_MAX FT_SEAT=t-r1210 FT_MBOX="$T/mbox.sh" FT_ROOT="$R" \
    FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" \
    FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$tool" 2>&1
}
width_of() { printf '%s\n' "$1" | sed -n '4p' | python3 -c 'import sys; print(len(sys.stdin.read().split("|")[2].strip()))'; }
bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }
FIT=152   # 낡은 원장 머리에서 12자 폭 = 1630B(초과) · 8자 폭 = 1558B(예산 안) · 경계 148~159자

# ── ⓐ R1
canon "$FIT" > "$R/$CPATH"; ledger "$PAD40S" > "$R/$LPATH"; commit fit; rm -rf "$R/.fable-team/state"
OUT="$(render)"; RC=$?
case "$(printf '%s\n' "$OUT" | head -1)" in *'상태 낡음'*) ok "⓪ 머리 = « · 상태 낡음»";; *) bad "⓪ 머리에 «상태 낡음» 없음 :: $(printf '%s\n' "$OUT" | head -1)";; esac
if [ -n "$PREV" ]; then
  POUT="$(render "$PREV")"; PRC=$?
  { [ "$PRC" = 1 ] && case "$POUT" in *'ERROR 골 표 예산 초과'*) true;; *) false;; esac; } \
    && ok "ⓐ 직전 판(12자 끝): 'ERROR 골 표 예산 초과' rc1 :: ${POUT#ERROR 골 표 예산 초과 }" || bad "ⓐ 직전 판 rc=$PRC :: $POUT"
else
  echo "SKIP ⓐ 직전 판 대조 — 고정 sha($PREVSHA) 판을 못 읽음"
fi
[ "$RC" = 0 ] && ok "ⓐ 지금 판: 같은 픽스처 → rc0" || bad "ⓐ 지금 판 rc=$RC :: $OUT"
[ "$(bytes "$OUT")" -le 1600 ] && ok "ⓐ 출력 $(bytes "$OUT")B ≤ 1600B" || bad "ⓐ 출력 $(bytes "$OUT")B > 1600B"
GOK=1; for i in 1 2 3 4 5 6; do case "$OUT" in *"| g$i-$(printf 'x%.0s' $(seq 1 "$FIT")) |"*) ;; *) GOK=0;; esac; done
[ "$GOK" = 1 ] && ok "ⓐ 골 원문 6행 글자 그대로(절단·«…» 0)" || bad "ⓐ 골 원문이 잘렸다"
[ "$(width_of "$OUT")" = 9 ] && ok "ⓐ 줄어든 폭 = 8자 + «…»(9자)" || bad "ⓐ 팀 칸 폭 $(width_of "$OUT") ≠ 9"
OK_BLOCK="$OUT"

# ── ⓑ R2 짧은 정본 = 직전 판과 바이트 같음
canon_short > "$R/$CPATH"; ledger "상태" > "$R/$LPATH"; commit short
OUT="$(render)"; RC=$?
{ [ "$RC" = 0 ] && ! printf '%s\n' "$OUT" | grep -q '…'; } && ok "ⓑ 짧은 정본 = rc0 · «…» 0($(bytes "$OUT")B)" || bad "ⓑ 짧은 정본 rc=$RC :: $OUT"
if [ -n "$PREV" ]; then
  [ "$(render "$PREV")" = "$OUT" ] && ok "ⓑ 짧은 정본 출력 = 직전 판과 바이트 같음(회귀 0)" || bad "ⓑ 짧은 정본 출력이 직전 판과 다르다"
else
  echo "SKIP ⓑ 회귀 대조 — 고정 sha($PREVSHA) 판을 못 읽음"
fi

# ── ⓒ R3 8자로도 넘침 → ERROR rc1
canon 400 > "$R/$CPATH"; ledger "$PAD40S" > "$R/$LPATH"; commit huge; rm -rf "$R/.fable-team/state"
OUT="$(render)"; RC=$?
{ [ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 예산 초과'*'골 원문 칸은 절단하지 않는다'*) true;; *) false;; esac; } \
  && ok "ⓒ 400자 골 6행 = 8자 폭으로도 초과 → ERROR rc1(골 원문 절단 0)" || bad "ⓒ rc=$RC :: $OUT"

# ── ⓓ R4 8자 폭 블록 + 골좌표 → check GOAL-OK
canon "$FIT" > "$R/$CPATH"; ledger "$PAD40S" > "$R/$LPATH"; commit fit2
OK_BLOCK="$(render)"
COUT="$(printf '%s\n골좌표: 1 — g1-xxxxxxxxx\n' "$OK_BLOCK" | env -u FT_ROOT -u FT_GOAL_A6_LEDGER FT_GOAL_A6_MD="gitref:origin/main:$CPATH" \
  FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check 2>&1)"; CRC=$?
{ [ "$CRC" = 0 ] && case "$COUT" in 'GOAL-OK n=1'*) true;; *) false;; esac; } && ok "ⓓ check = $COUT" || bad "ⓓ check rc=$CRC :: $COUT"

# ── ⓔ bin·kit 같은 내용
cmp -s "$TOOL" "$KIT" && ok "ⓔ bin·kit cmp0" || bad "ⓔ bin·kit 내용이 다르다"

# ── ⓕ 변이: 8자 단계 뺌 → ⓐ 픽스처 rc1
python3 - "$T/mutbin/ft_goal_table.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); src = p.read_text(encoding="utf-8")
old = "GOAL_CELLS = (24, 20, 16, 12, 8)"
assert old in src, "변이 지점(8자 단계) 없음"
p.write_text(src.replace(old, "GOAL_CELLS = (24, 20, 16, 12)"), encoding="utf-8")
PY
OUT="$(render "$T/mutbin/ft_goal_table.py")"; RC=$?
{ [ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 예산 초과'*) true;; *) false;; esac; } \
  && ok "ⓕ 변이(8자 단계 뺌) → 예산 초과 rc1 — 시험이 잡는다" || bad "ⓕ 변이 rc=$RC :: $OUT"

# ── ⓖ 격리
[ ! -s "$MBOX_LOG" ] && ok "ⓖ 실 쪽지 0(가짜 mbox 기록 비어 있음)" || bad "ⓖ 쪽지가 나갔다 :: $(cat "$MBOX_LOG")"

echo "---"; [ "$fail" = 0 ] && echo "ALL PASS (r1210)" || echo "FAIL $fail 건"
exit $([ "$fail" = 0 ] && echo 0 || echo 1)
