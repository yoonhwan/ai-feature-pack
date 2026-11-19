#!/usr/bin/env bash
# test_hil_plan_judge_multiline_quote_r2294.sh — r2294: 계획 판정기가 여러 줄 따옴표 문자열을 닫힐 때까지 한 논리 줄로 읽는다.
#   사례 ①~⑤(카드 반례 동결) · 변이 M1(따옴표 잇기 지움) · M2(줄 번호 = 마지막 물리 줄) — 변이마다 원본으로 같은 사례 1회 더
#   격리: 임시 폴더 계획 파일 · 판정기 --plan 만(실행 0) · 실 h 폴더·실 팩 쓰기 0 · 고정 sleep 0
#   기준판 대조: R2294_BIN=<다른 bin> 이면 그 판정기로 사례만 돈다(변이 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R2294_BIN:-$HERE/../bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
run() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

plan() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/$1.hil"; }  # 줄 1 = 셔뱅 · 본문 = 줄 2부터
plan dq 'LIST="kit/a.sh|x
kit/b.sh|y
kit/c.sh|z"
echo "$LIST"'
plan sq "bash -c 'echo 1
scripts/x.sh
'"
plan after 'A="x
y"
bash scripts/run.sh'
plan subst 'A="x
$(bash scripts/x.sh)
y"'
plan open 'A="x
kit/b.sh'
J() { JO="$(python3 "$1/ft_hil_plan_syntax_judge.py" --plan "$T/$2.hil" 2>&1)"; JV=$?; }  # <bin> <계획 이름>
c1() { J "$1" dq && [ "$JV" = 0 ] && [ "$JO" = ok ]; }
c2() { J "$1" sq && [ "$JV" = 0 ] && [ "$JO" = ok ]; }
c3() { J "$1" after && [ "$JV" = 1 ] && [ "$JO" = "reject 상대 경로 — 절대 경로로: scripts/run.sh — 줄 4" ]; }
c4() { J "$1" subst; [ "$JV" = 1 ] && [ "$JO" = "reject 상대 경로 — 절대 경로로: scripts/x.sh — 줄 2" ]; }
c5() { J "$1" open; [ "$JV" = 1 ] && case "$JO" in "reject 계획 문법 오류"*) return 0;; esac; return 1; }

sec "①~⑤ 여러 줄 따옴표"
run "① 큰따옴표 여러 줄 LIST 안 kit/b.sh|y = ok rc0" c1 "$BIN0"
run "② 작은따옴표 여러 줄 안 scripts/x.sh = ok rc0" c2 "$BIN0"
run "③ 따옴표 닫힌 뒤 bash scripts/run.sh = reject — 줄 4(밀리지 않음)" c3 "$BIN0"
run "④ 따옴표 안 \$(bash scripts/x.sh) = reject — 줄 2(논리 줄 첫 줄)" c4 "$BIN0"
run "⑤ 끝까지 안 닫힌 따옴표 = reject 계획 문법 오류 rc1" c5 "$BIN0"

if [ -z "${R2294_BIN:-}" ]; then
  sec "변이 M1·M2(사본)"
  mut() {  # <폴더 이름> <옛 글> <새 글> — bin 사본에 변이 1곳(못 찾으면 빈 값)
    local d="$T/$1"; cp -R "$BIN0" "$d"
    python3 - "$d/ft_hil_plan_syntax_judge.py" "$2" "$3" <<'PY' || return 0
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
    printf '%s\n' "$d"
  }
  caught() {  # <설명> <사례함수> <변이 bin>
    if [ -z "$3" ]; then bad "$1 사본 못 만듦"; return; fi
    if "$2" "$3" >/dev/null 2>&1; then bad "변이 $1 를 못 잡음($2 가 변이 사본에서도 통과)"; else ok "변이 $1 → $2 FAIL 검출"; fi
    if "$2" "$BIN0" >/dev/null 2>&1; then ok "원본 $2 1회 더 PASS"; else bad "원본 $2 1회 더 FAIL"; fi
  }
  M1="$(mut mut1 '        if q:' '        if False:')"
  caught "M1(따옴표 잇기 지움)" c1 "$M1"
  caught "M1(따옴표 잇기 지움)" c2 "$M1"
  caught "M2(줄 번호 = 마지막 물리 줄)" c4 "$(mut mut2 '        yield start, full' '        yield n, full')"
fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
