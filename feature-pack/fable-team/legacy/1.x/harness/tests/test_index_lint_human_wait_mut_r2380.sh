#!/usr/bin/env bash
# test_index_lint_human_wait_mut_r2380.sh — r2380 변이(카드 고정): 사본 bin 한 곳을 무력화하면 그 시험이 FAIL 해야 한다.
#   M1 ts 검사 지움 → ① · M2 «오빠» 낱말 판정 지움 → ④ · M3 «없음» 빼기 지움 → ⑤-a · M3b 취소선 빼기 지움 → ⑤-b · M4 스위치 무시(늘 REJECT) → ③
#   실 파일은 안 건드린다(사본만) · 끝에 실 파일 sha 무변경 확인.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$HERE/scripts/_r2380_lint_world.sh"
r2380_lint_world "$T" || { echo "FAIL 세계"; exit 1; }
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$KIT/ft-index-lint.sh" | awk '{print $1}')"
mutate() {  # $1 이름 $2 원문(고정 문자열 · 1곳) $3 바꿀 글 $4 기대 FAIL 이름
  cp -p "$KIT/ft-index-lint.sh" "$T/bin/ft-index-lint.sh"
  python3 -I - "$T/bin/ft-index-lint.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  ( run_cases "$T/bin" "변이 $1" ) > "$T/mut.log" 2>&1   # 하위 셸 — 변이가 만든 FAIL 이 이 시험의 fail 을 올리지 않게
  grep -q "^FAIL 변이 $1 $4" "$T/mut.log"; ck "변이 $1 → $4 FAIL" $?
  cp -p "$KIT/ft-index-lint.sh" "$T/bin/ft-index-lint.sh"
}
mutate "M1 ts 검사 지움" '    [ -n "$ts" ] && continue' "    continue" "①"
mutate "M2 오빠 낱말 판정 지움" '    case "$body" in *오빠*) ;; *) continue;; esac' "    :" "④"
mutate "M3 없음 머리 줄 빼기 지움" '    case "$body" in 없음*) continue;; esac' "    :" "⑤-a"
mutate "M3b 취소선 빼기 지움" '    body="$(printf '"'"'%s'"'"' "$body" | sed -E '"'"'s/~~[^~]*~~//g'"'"')"' "    :" "⑤-b"
mutate "M4 스위치 무시(늘 REJECT)" 'if [ "${FT_LINT_HUMAN_WAIT:-}" = reject ]; then' "if true; then" "③"
sha_after="$(shasum "$KIT/ft-index-lint.sh" | awk '{print $1}')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?
lap 변이
echo "fail=$fail"; [ "$fail" -eq 0 ]
