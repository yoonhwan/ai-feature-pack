#!/usr/bin/env bash
# test_index_lint_small_card_remaining_r2206.sh — r2206: 작은 카드 줄 수는 «- 남은 범위:» 줄(ft-nano-record 기록 줄)을 빼고 센다.
#   다른 줄은 지금처럼 센다. 임시 리포·사본만 · 실 리포 쓰기 0 · sleep 0.
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; KIT="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"
fail=0; ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc ${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; export HOME="$T/home"; mkdir -p "$HOME"
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_LANDED_MARKER FT_ROOT FT_TEAM FT_GOAL_LINES_FILE
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
BIN="$T/bin"; cp -Rp "$KIT" "$BIN"; rc=0; out=""
mutate() { python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if old not in s: raise SystemExit("mutant target missing: " + old)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
FIXED="grep -vcE '^- 남은 범위:' \"\$f\""; ORIG="awk 'END{print NR}' \"\$f\""
# 기준판 사본(고친 줄을 되돌린 것) — ⑤ ⑥ «기준판과 같은 판정» 대조용. 기준판 자체에서 돌리면 되돌릴 줄이 없어 그대로 둔다.
BASE="$T/base"; cp -Rp "$BIN" "$BASE"; mutate "$BASE/ft-index-lint.sh" "$FIXED" "$ORIG" 2>/dev/null || true
# ── 카드 리포(r1844 시험 꼴)
R="$T/repo"; IDX="$R/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$R/src"
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$R/design/TEAMS.md"
echo '원장: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$R/design/LEDGER.md"; echo x > "$R/src/target.sh"
g "$R" init -q -b main; g "$R" add -A; g "$R" commit -qm base
L="$IDX/대기"
small() { local f="$L/$1.md" k; { echo "# 인덱스: $1 — 끝: 시험"; echo '<!-- ledger: design/LEDGER.md -->'
  for k in '지시 #: t#1' '골좌표: 4 · 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」' '원인 1줄: 시험' '대상(쓰기 = 나노): src/target.sh' \
    '계약: x' '반례: ① x' '변이: M1 x' '회귀: x' '크기: x' '범위 밖: x' '설치: 없음' '상태: 대기'; do [ "$k" = "${2:-}" ] || echo "- $k"; done
  echo; echo '## 상태'; for k in $(seq "$3"); do echo "- s$k"; done; } > "$f"; echo "$f"; }
lint() { out="$(cd "$R" && timeout 70 bash "${2:-$BIN/ft-index-lint.sh}" "$1" 2>&1)"; rc=$?; }
nl_of() { wc -l < "$1" | tr -d ' '; }
REM='- 남은 범위: 없음 — 시험(r2206)'
# ── ② 20줄 작은 카드 + 남은 범위 1줄 = 21줄 → OK (기준판 = REJECT)
s0=$SECONDS; f2="$(small s2 '' 4)"; lint "$f2"; [ "$(nl_of "$f2")" = 20 ] && [ "$rc" = 0 ]; ck "② 전제: 20줄 작은 카드 OK" $?
echo "$REM" >> "$f2"; [ "$(nl_of "$f2")" = 21 ]; ck "② 카드 21줄" $?
lint "$f2"; [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^OK '; ck "② 20줄 + 남은 범위 1줄 → OK ($((SECONDS-s0))s)" $?
# ── ③ 남은 범위 2줄 → OK
f3="$(small s3 '' 4)"; printf '%s\n' "$REM" '- 남은 범위: 둘째 줄' >> "$f3"; [ "$(nl_of "$f3")" = 22 ]; ck "③ 카드 22줄" $?
lint "$f3"; [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^OK '; ck "③ 남은 범위 2줄 → OK" $?
# ── ④ ② 와 같은데 머리 키 «원인 1줄» 없음 → 작은 카드 검사 그대로
f4="$(small s4 '원인 1줄: 시험' 5)"; echo "$REM" >> "$f4"; [ "$(nl_of "$f4")" = 21 ]; ck "④ 카드 21줄" $?
lint "$f4"; [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^  - ')" = 1 ] && printf '%s\n' "$out" | grep -q '^  - 작은 카드: 머리 키 없음: 원인 1줄$'
ck "④ 원인 1줄 없음 → REJECT «작은 카드: 머리 키 없음: 원인 1줄»" $?
# ── ⑤ 20줄 작은 카드 + 다른 줄(«- 메모: x») = 21줄 → 기준판과 같은 REJECT(큰 카드 절 검사)
f5="$(small s5 '' 4)"; echo '- 메모: x' >> "$f5"; [ "$(nl_of "$f5")" = 21 ]; ck "⑤ 카드 21줄" $?
case5() { lint "$f5" "${1:-}"; local o="$out" r="$rc"; lint "$f5" "$BASE/ft-index-lint.sh"
  [ "$r" = 1 ] && [ "$o" = "$out" ] && printf '%s\n' "$o" | grep -q '^  - 절 없음: 골 원문' && ! printf '%s\n' "$o" | grep -q '작은 카드'; }
case5; ck "⑤ 다른 줄 1줄 → 기준판과 같은 REJECT" $?
# ── ⑥ 21줄 큰 카드(골 원문 절 있음) + 남은 범위 줄 → 기준판과 같은 판정(큰 카드 길)
f6="$(small s6 '' 2)"; { echo; echo '## 골 원문'; echo 'x'; echo "$REM"; } >> "$f6"; [ "$(nl_of "$f6")" = 22 ]; ck "⑥ 카드 22줄(남은 범위 빼면 21줄)" $?
lint "$f6"; o6="$out"; r6="$rc"; lint "$f6" "$BASE/ft-index-lint.sh"
[ "$r6" = "$rc" ] && [ "$o6" = "$out" ] && ! printf '%s\n' "$o6" | grep -q '작은 카드'; ck "⑥ 큰 카드 + 남은 범위 → 기준판과 같은 판정(rc=$r6)" $?
# ── 변이 M1: «- 남은 범위:» 대신 모든 «- » 줄을 뺌 → ⑤ FAIL · 원본으로 같은 사례 1회 더 = PASS
cp -Rp "$BIN" "$T/m1"; mutate "$T/m1/ft-index-lint.sh" "grep -vcE '^- 남은 범위:'" "grep -vcE '^- '"
case5 "$T/m1/ft-index-lint.sh"; [ $? != 0 ]; ck "M1 모든 «- » 줄 뺌 → ⑤ FAIL(적중)" $?
case5; ck "M1 대조: 원본 → ⑤ PASS" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
