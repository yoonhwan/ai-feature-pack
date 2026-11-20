#!/usr/bin/env bash
# test_install_pending_clear_on_recheck_mut_r2325.sh — r2325 짝 시험: 기준판 Red ① + 변이 M1~M6(bin 사본 · 그 자리만) + 원본 대조
#   사례 본체 = test_install_pending_clear_on_recheck_r2325.sh(FT_R2325_BIN · FT_R2325_ONLY 로 그 사례만) · 나눈 까닭 = 시험 1개 70초 상한(하드 룰 22)
#   M1 지움 줄 지움 → ① FAIL · M2 조상 검사 지움 → ③ FAIL · M3 검사 rc0 조건 지움 → ④ FAIL · M4 옵션 없어도 지움 → ⑥ FAIL · M5 rc≥2 를 rc1 과 같이 KEEP → ⑩ FAIL · M6 하네스 밖 OK 갈래 지움 0 → ⑫ FAIL(DA#39 ⓐ)
#   실 좌석·실 리포·실 gh·네트워크 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; CASES="$HERE/test_install_pending_clear_on_recheck_r2325.sh"
BIN="$(cd "$HERE/../../harness/bin" && pwd -P)"; BASE_SHA=0f6b778e399adfbe3826029270f100829e6ec80a   # r2325 다시 쌓은 base(팩 main) = 기준판(옵션 모름 → ① Red)
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mut() {  # mut <이름> <파일> <옛 글> <새 글> → MB
  MB="$T/mut-$1"; rm -rf "$MB"; cp -R "$BIN" "$MB"; rm -rf "$MB/__pycache__"
  python3 - "$MB/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
runc() {  # runc <bin> <사례…> → rc · out(PASS/FAIL 이름만)
  local o; o="$(FT_R2325_BIN="$1" FT_R2325_ONLY="$2" bash "$CASES" 2>&1)"; rc=$?
  out="$(printf '%s\n' "$o" | grep -E '^(PASS|FAIL)' | sed 's/ :: .*//' | tr '\n' ' ')"
}
red() { runc "$2" "$3"; [ "$rc" != 0 ]; ck "$1 → $3 FAIL(기대) :: $out" $?; }   # red <이름> <bin> <사례…>

echo "### 원본 대조: 추적본 bin 으로 c1 c3 c4 c6 c10 c12 → PASS"
runc "$BIN" "c1 c3 c4 c6 c10 c12"; [ "$rc" = 0 ]; ck "원본 c1 c3 c4 c6 c10 c12 PASS :: $out" $?
S1=$SECONDS
echo "### 변이 M1~M6"
mut m1 ft_live_install_check.py "        os.unlink(pf)" "        pass" && red "M1 지움 줄 지움" "$MB" c1
mut m2 ft_live_install_check.py '    are = run(["git", "-C", repo, "merge-base", "--is-ancestor", a, m.strip()])' '    are = run(["git", "-C", repo, "merge-base", "--is-ancestor", a, a])' && red "M2 조상 검사 지움" "$MB" c3
mut m3 ft_live_install_check.py "        keep_pending(repo, landed, 1)  # r2325: 검사 PENDING = 파일 그대로 · KEEP 1줄" "        clear_pending(repo, o, landed)" && red "M3 검사 rc0 조건 지움" "$MB" c4
mut m4 ft_live_install_check.py '"project": None, "clear": None}' '"project": None, "clear": os.path.join(os.path.expanduser("~"), "..")}' && red "M4 옵션 없어도 지움" "$MB" c6
mut m5 ft_live_install_check.py "    if are.returncode == 1:" "    if are.returncode >= 1:" && red "M5 rc≥2 를 rc1 과 같이 KEEP" "$MB" c10
mut m6 ft_live_install_check.py "        clear_pending(repo, o, b)" "        pass" && red "M6 하네스 밖 OK 갈래 지움 0" "$MB" c12   # DA#39 ⓐ 반례 ⑫ 짝
S2=$SECONDS
echo "### 기준판 Red ① (팩 $BASE_SHA = 착지 전 bin)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$HERE/.." archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-live-install-check.sh" ]; then
  runc "$BASE/bin" c1; [ "$rc" != 0 ] && [[ "$out" == *"FAIL ①"* ]]
  ck "기준판 ① FAIL(기대) :: $out" $?
else rc=1; out="git archive 실패"; ck "기준판 꺼내기" 1; fi
echo "단계별 초: 원본 대조 $((S1 - T0)) · 변이 $((S2 - S1)) · 기준판 $((SECONDS - S2)) · 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
