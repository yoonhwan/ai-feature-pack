#!/usr/bin/env bash
# test_goal_table_budget_shrink_r731.sh — 골 정본이 길어지자 골 표가 예산(1600B) 초과로 rc1 멈추던 것 → «재조정» 칸 라벨 축소(지금) 뒤에 팀·상태·증거 칸 폭을 24→20→16→12자로 차례로 줄여 예산 안에 들인다(r731).
#   ⓐ 예산 초과 픽스처(칸 40자 · 재조정 기록 없음) = 직전 판 rc1 «예산 초과» → 지금 판 rc0 (20자 폭에서 들어감)
#   ⓑ 지금 판 출력 ≤1600B · 골 원문 6행 글자 그대로(절단 0 · «…» 0) · 팀·상태·증거 칸만 «…»(20자 폭 = 21자)
#   ⓒ 축소 순서 = ①재조정 라벨 글자만(폭 24 그대로) ②칸 20 — 라벨 축소만으로 들어가는 픽스처는 칸이 24자(25자) 그대로
#   ⓓ 12자로도 넘치면 ERROR rc1(골 원문은 끝까지 절단 0) · 짧은 정본 = 직전 판과 바이트 같은 출력(회귀 0)
#   ⓔ 변이: 폭 축소 단계 삭제 → ⓐ 픽스처 rc1(빨강이 잡힌다)
#   ⓕ 격리 = 임시 git 리포·임시 루트·가짜 mbox(인자 기록만) — 실 리포·실 쪽지·외부 호출 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd -- "$HERE/../.." && pwd)"
TOOL="$REPO/harness/bin/ft_goal_table.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
CPATH=design/planner/AUTONOMY-GOAL-A6-20261021.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner"; git -C "$R" init -q -b main
export MBOX_LOG="$T/mbox.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$MBOX_LOG"\n' > "$T/mbox.sh"
PAD40="$(printf 'y%.0s' $(seq 1 40))"; PAD40E="$(printf 'z%.0s' $(seq 1 40))"; PAD40S="$(printf 'q%.0s' $(seq 1 40))"
# 직전 판(origin/main) 도구 — «지금 판 rc1» 의 대조군. 없으면 그 항목만 건너뛴다(다른 항목은 그대로 잡는다).
# 직전 판(origin/main) 도구 — «지금 판 rc1» 의 대조군. import 이웃(ft_goal_ledger 등)이 필요해 bin 사본과 같이 돈다.
#   없으면 그 항목만 건너뛴다(다른 항목은 그대로 잡는다).
mkdir -p "$T/prevbin" "$T/mutbin"; cp "$REPO"/harness/bin/*.py "$T/prevbin/"; cp "$REPO"/harness/bin/*.py "$T/mutbin/"
TOP="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"; PREV=""
if [ -n "$TOP" ]; then REL="${TOOL#"$TOP"/}"; git -C "$TOP" show "origin/main:$REL" > "$T/prevbin/ft_goal_table.py" 2>/dev/null && PREV="$T/prevbin/ft_goal_table.py"; fi
canon() {  # <골 원문 길이> — 골 6행(길이 가변) · 팀·증거 칸 40자
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local i pad; pad="$(printf 'x%.0s' $(seq 1 "$1"))"
  for i in 1 2 3 4 5 6; do printf '| g%s-%s | t%s | e%s |\n' "$i" "$pad" "$PAD40" "$PAD40E"; done
}
canon_short() {  # 짧은 정본 = 어떤 칸도 24자를 넘지 않는다(지금 판·직전 판 출력이 같아야 한다)
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local i; for i in 1 2 3 4 5 6; do printf '| 골%s | 팀%s | 증거%s |\n' "$i" "$i" "$i"; done
}
ledger_short() {  # 짧은 상태 칸(24자를 넘지 않는다)
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오뻐 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
  local i; for i in 1 2 3 4 5 6; do printf '| 렛%s | 상태%s | 남%s |\n' "$i" "$i" "$i"; done
}
ledger() {  # 팀·상태·증거의 «지금 상태» 칸(원장) — 40자
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
  local i; for i in 1 2 3 4 5 6; do printf '| 렛%s | s%s | 남%s |\n' "$i" "$PAD40S" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
readjust() {  # 재조정 회차 파일 — 라벨 뒤 «·카드2·대응 모름» 이 붙어 폭 24자에 닿는다(ⓒ 순서 확인용)
  local dir="$R/.fable-team/state/goal-readjust/rounds"; mkdir -p "$dir"
  python3 - "$R/$CPATH" "$dir/20261022-1-01.json" <<'PY'
import hashlib, json, pathlib, re, sys, unicodedata
canon, out = sys.argv[1], sys.argv[2]
raw = pathlib.Path(canon).read_bytes()
cells = [re.sub(r"\s+", " ", unicodedata.normalize("NFC", ln.split("|")[1])).strip()
         for ln in raw.decode("utf-8").splitlines() if ln.startswith("| g")]
rows = [{"n": i, "goal_hash": hashlib.sha256(c.encode("utf-8")).hexdigest()[:10],
         "label": "확장", "cards_added": 2, "unknown": ["대응 유지 모름"]} for i, c in enumerate(cells, 1)]
pathlib.Path(out).write_text(json.dumps({"status": "OK", "run": "20261022-1", "finished": "2026-10-22 15:00:00",
                                         "inputs": {"canon_sha10": hashlib.sha256(raw).hexdigest()[:10]}, "rows": rows},
                                        ensure_ascii=False), encoding="utf-8")
PY
}
render() {  # [<도구 경로>] — 격리 env(임시 루트·임시 리포·가짜 mbox)
  local tool="${1:-$TOOL}"
  env -u FT_GOAL_MAX FT_NOW="2026-10-22 16:00" FT_SEAT=t-r731 FT_MBOX="$T/mbox.sh" FT_ROOT="$R" \
    FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" \
    FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$tool" 2>&1
}
width_of() { printf '%s\n' "$1" | sed -n '4p' | python3 -c 'import sys; print(len(sys.stdin.read().split("|")[2].strip()))'; }  # 글자 수(awk length 는 바이트)
mt() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

# ── ⓐ 예산 초과 픽스처: 직전 판 rc1 → 지금 판 rc0
canon 116 > "$R/$CPATH"; ledger > "$R/$LPATH"; commit over; rm -rf "$R/.fable-team/state"
if [ -n "$PREV" ]; then
  OUT="$(render "$PREV")"; RC=$?
  { [ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 예산 초과'*) true;; *) false;; esac; } \
    && ok "ⓐ 직전 판: 40자 칸 픽스처 → 'ERROR 골 표 예산 초과' rc1" || bad "ⓐ 직전 판 rc=$RC :: $OUT"
else
  echo "SKIP ⓐ 직전 판 대조 — origin/main 판을 못 읽음"
fi
OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && ok "ⓐ 지금 판: 같은 픽스처 → rc0 (폭 20자에서 예산 안)" || bad "ⓐ 지금 판 rc=$RC :: $OUT"

# ── ⓑ ≤1600B · 골 원문 절단 0 · 팀·상태·증거만 «…»
BYTES="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
[ "$BYTES" -le 1600 ] && ok "ⓑ 출력 ${BYTES}B ≤ 1600B" || bad "ⓑ 출력 ${BYTES}B > 1600B"
GOK=1; for i in 1 2 3 4 5 6; do case "$OUT" in *"| g$i-$(printf 'x%.0s' $(seq 1 116)) |"*) ;; *) GOK=0;; esac; done
[ "$GOK" = 1 ] && ok "ⓑ 골 원문 6행 글자 그대로(절단·«…» 0)" || bad "ⓑ 골 원문이 잘렸다"
GOALCUT=0; printf '%s\n' "$OUT" | sed -n '4,9p' | grep -q '^| \(g[0-9]-x*…\) |' && GOALCUT=1
[ "$GOALCUT" = 0 ] && ok "ⓑ 골 칸 절단 없음(«…» 가 붙은 골 행 0)" || bad "ⓑ 골 칸이 잘렸다"
CUTS="$(printf '%s\n' "$OUT" | sed -n '4,9p' | grep -c '…')"
[ "$CUTS" = 6 ] && ok "ⓑ 팀·상태·증거 칸만 «…»(6행 전부)" || bad "ⓑ «…» 행 수 $CUTS ≠ 6"
[ "$(width_of "$OUT")" = 21 ] && ok "ⓑ 줄어든 폭 = 20자 + «…»(21자)" || bad "ⓑ 팀 칸 폭 $(width_of "$OUT") ≠ 21"

# ── ⓒ 순서 = 라벨 축소(폭 24 그대로) 먼저 — 라벨 축소만으로 들어가는 픽스처(123자: 라벨을 떼면 1600B 로 들어간다 · 폭은 24자 그대로)
canon 123 > "$R/$CPATH"; ledger > "$R/$LPATH"; readjust; commit label
OUT="$(render)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(width_of "$OUT")" = 25 ]; } \
  && ok "ⓒ 라벨 축소만으로 들어가면 폭은 24자 그대로(25자 칸)" || bad "ⓒ rc=$RC 폭=$(width_of "$OUT") :: $OUT"
printf '%s\n' "$OUT" | sed -n '4p' | grep -q '확장 |$' \
  && ok "ⓒ 재조정 칸 = 라벨 글자만(«·카드2·대응 모름» 뗌)" || bad "ⓒ 재조정 칸이 안 줄었다 :: $(printf '%s\n' "$OUT" | sed -n '4p')"

# ── ⓓ 12자로도 넘치면 ERROR rc1 · 짧은 정본 = 직전 판과 같은 출력
canon 400 > "$R/$CPATH"; commit huge; rm -rf "$R/.fable-team/state"
OUT="$(render)"; RC=$?
{ [ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 예산 초과'*'골 원문 칸은 절단하지 않는다'*) true;; *) false;; esac; } \
  && ok "ⓓ 400자 골 6행 = 12자 폭으로도 초과 → ERROR rc1(골 원문 절단 0)" || bad "ⓓ rc=$RC :: $OUT"
canon_short > "$R/$CPATH"; ledger_short > "$R/$LPATH"; commit short
OUT="$(render)"; RC=$?
NOWF="$T/short_now.txt"; printf '%s' "$OUT" > "$NOWF"
{ [ "$RC" = 0 ] && [ "$(mt "$NOWF")" -le 1600 ] && ! printf '%s\n' "$OUT" | grep -q '…'; } \
  && ok "ⓓ 짧은 정본 = rc0 · «…» 0($(mt "$NOWF")B)" || bad "ⓓ 짧은 정본 rc=$RC :: $OUT"
if [ -n "$PREV" ]; then
  printf '%s' "$(render "$PREV")" > "$T/short_prev.txt"
  cmp -s "$T/short_prev.txt" "$NOWF" && ok "ⓓ 짧은 정본 출력 = 직전 판과 바이트 같음(회귀 0)" \
    || bad "ⓓ 짧은 정본 출력이 직전 판과 다르다"
else
  echo "SKIP ⓓ 회귀 대조 — origin/main 판을 못 읽음"
fi

# ── ⓔ 변이: 폭 축소 단계 삭제 → ⓐ 픽스처가 다시 rc1
canon 116 > "$R/$CPATH"; ledger > "$R/$LPATH"; commit back
python3 - "$T/mutbin/ft_goal_table.py" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
old = "[(False, w) for w in GOAL_CELLS]"
assert old in src, "변이 지점(폭 사다리) 없음"
pathlib.Path(sys.argv[1]).write_text(src.replace(old, "[(False, GOAL_CELLS[0])]"), encoding="utf-8")
PY
OUT="$(render "$T/mutbin/ft_goal_table.py")"; RC=$?
{ [ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 예산 초과'*) true;; *) false;; esac; } \
  && ok "ⓔ 변이(폭 사다리 삭제) → 예산 초과 rc1 — 시험이 삭제를 잡는다" || bad "ⓔ 변이 rc=$RC :: $OUT"

# ── ⓕ 격리: 실 쪽지 0
[ "$(mt "$MBOX_LOG")" = 0 ] && ok "ⓕ 실 쪽지 0(가짜 mbox 기록 비어 있음)" || bad "ⓕ 쪽지 $(mt "$MBOX_LOG")건 나갔다"

echo "---"; [ "$fail" = 0 ] && echo "ALL PASS (r731)" || echo "FAIL $fail 건"
exit $([ "$fail" = 0 ] && echo 0 || echo 1)
