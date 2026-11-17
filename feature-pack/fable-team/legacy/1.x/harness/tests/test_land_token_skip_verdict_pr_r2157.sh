#!/usr/bin/env bash
# test_land_token_skip_verdict_pr_r2157.sh — r2157: planner 판정 PR(가지 planner/verdict-<숫자>) 착지는 장부 카드 토큰 0
#   fm_land_turn_first 를 부르고 fm_land_turn_ledger 를 대역으로 바꿔 받은 토큰 인자를 찍는다(장부·git·쪽지 0)
#   fm_card_tokens 직접 호출 = 착지 알림 · 카드 착지 줄 · D2 Slack 칸 불변(손 0)
#   반례 ①~④ · ⑥(카드 r2157 동결 · ⑤ = 기존 시험 목록 재실행은 따로) · 변이 M1~M3 = 사본 bin + 원본 대조 · sleep 0
#   FT_R2157_BIN = 다른 bin(기준판) 주입
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "${FT_R2157_BIN:-$HERE/../bin}" && pwd -P)" || { echo "판정 불가 — bin 없음(${FT_R2157_BIN:-})"; exit 2; }; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; OUT=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: out=[$OUT]"; fail=$((fail + 1)); fi; }
miss() { ! "$@"; }
led() {  # led <bin> <가지> <제목> → OUT = fm_land_turn_first 가 장부에 넘긴 토큰(공백 이음)
  OUT="$(. "$1/ft-merge-lib.sh" && fm_land_turn_ledger() { shift 3; printf '%s' "$*"; } && fm_land_turn_first "$T" 1 "$2" "$3")"
}
tok() { OUT="$(. "$1/ft-merge-lib.sh" && fm_card_tokens "$2" "$3")"; }   # tok <bin> <가지> <제목>

V1T="[docs] planner 판정 4385 — harness 나노 r2156 닫기"
c1() { led "$1" planner/verdict-4385 "$V1T"; [ -z "$OUT" ]; }
c2() { led "$1" planner/verdict-12 "[docs] planner 판정 12 — r10 r11"; [ -z "$OUT" ]; }
c3() { led "$1" planner/verdict-note "r2156"; [ "$OUT" = r2156 ]; }
c3x() { led "$1" planner/verdict-4385-x "$V1T"; [ "$OUT" = r2156 ]; }   # P2: 숫자 뒤 꼬리 = 판정 PR 꼴 아님
c3e() { led "$1" planner/verdict- "$V1T"; [ "$OUT" = r2156 ]; }         # P2: 빈 꼬리 = 판정 PR 꼴 아님
c4() { led "$1" docs/harness-r2150-x "r2149 r2150"; [ "$OUT" = "r2149 r2150" ] && [ "$OUT" = "$(. "$1/ft-merge-lib.sh" && fm_card_tokens docs/harness-r2150-x "r2149 r2150")" ]; }
c4n() { led "$1" nano/r2156-idle-scan-keep-tester "x r9999"; [ "$OUT" = r2156 ]; }
c6a() { tok "$1" planner/verdict-4385 "$V1T"; [ "$OUT" = r2156 ]; }
c6b() { tok "$1" planner/verdict-12 "[docs] planner 판정 12 — r10 r11"; [ "$OUT" = "r10 r11" ]; }

echo "### 반례 (bin=$BIN)"
ck "① planner/verdict-4385 · 제목 r2156 → 장부 토큰 빈 값" c1 "$BIN"
ck "② planner/verdict-12 · 제목 r10 r11 → 장부 토큰 빈 값" c2 "$BIN"
ck "③ planner/verdict-note · 제목 r2156 → 장부 토큰 r2156" c3 "$BIN"
ck "③ P2 planner/verdict-4385-x → 장부 토큰 r2156" c3x "$BIN"
ck "③ P2 planner/verdict- (빈 꼬리) → 장부 토큰 r2156" c3e "$BIN"
ck "④ docs/harness-r2150-x · 제목 r2149 r2150 → 지금 토큰(fm_card_tokens 와 같음)" c4 "$BIN"
ck "④ nano/r2156-idle-scan-keep-tester → 장부 토큰 r2156" c4n "$BIN"
ck "⑥ fm_card_tokens planner/verdict-4385 → r2156(알림·카드 착지 줄·D2 불변)" c6a "$BIN"
ck "⑥ fm_card_tokens planner/verdict-12 → r10 r11" c6b "$BIN"

echo "### 변이(사본 · 원본 대조)"
mut() {  # mut <이름> <옛 글자> <새 글자> [<옛> <새>…] — 사본 bin 에서 쌍마다 정확히 1곳
  local n="$1"; shift; rm -rf "${T:?}/${n:?}"; cp -R "$BIN" "$T/$n"
  python3 - "$T/$n/ft-merge-lib.sh" "$@" <<'PY' || { echo "FAIL $n 변이 못 끼움"; fail=$((fail + 1)); return 1; }
import sys
p, pr = sys.argv[1], sys.argv[2:]; s = open(p, encoding="utf-8").read()
for a, b in zip(pr[::2], pr[1::2]):
    if s.count(a) != 1: sys.exit(1)
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
}
SKIP='[[ "$3" =~ ^planner/verdict-[0-9]+$ ]] && tok=""'
if [ -z "${FT_R2157_BIN:-}" ]; then
  if mut m1 "$SKIP" ':'; then
    ck "M1 건너뜀 지움 → ① 잡힘" miss c1 "$T/m1"; ck "M1 건너뜀 지움 → ② 잡힘" miss c2 "$T/m1"
    ck "M1 원본 대조 ①" c1 "$BIN"; ck "M1 원본 대조 ②" c2 "$BIN"
  fi
  if mut m2 '^planner/verdict-[0-9]+$' '^planner/'; then
    ck "M2 planner/* 전부 빈 값 → ③ 잡힘" miss c3 "$T/m2"; ck "M2 원본 대조 ③" c3 "$BIN"
  fi
  if mut m3 "$SKIP" ':' 'fm_card_tokens() {' 'fm_card_tokens() { [[ "$1" =~ ^planner/verdict-[0-9]+$ ]] && return 0'; then
    ck "M3 건너뜀을 fm_card_tokens 로 옮김 → ⑥ 잡힘" miss c6a "$T/m3"; ck "M3 → ⑥ planner/verdict-12 잡힘" miss c6b "$T/m3"
    ck "M3 원본 대조 ⑥" c6a "$BIN"; ck "M3 원본 대조 ⑥ verdict-12" c6b "$BIN"
  fi
else echo "SKIP 변이(기준판 주입)"; fi

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-lib.sh)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
echo "단계별 초: 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
