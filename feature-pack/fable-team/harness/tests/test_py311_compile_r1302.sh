#!/usr/bin/env bash
# test_py311_compile_r1302.sh — r1302: 팩 harness/bin + kit/bin 의 모든 .py 가 python3.11 에서 컴파일된다 · python3.11 이 없으면 SKIP 아닌 ERROR · bin↔kit 같은 판 · 변이 1 = 중첩 f-string 을 되돌리면 C1 FAIL
# 계기: r1298 격리(arch#203)에서 `/opt/homebrew/bin/python3.11 -m compileall harness/bin` 이 ft_card_assign_watch.py 의 중첩 f-string(PEP 701 = 3.12+ 문법)에서 SyntaxError — 팩 pytest 인터프리터가 3.11 이라 그 파일을 import 하는 시험이 전부 수집 실패했다. 재발 방지용 칸.
# 자기 재호출 0 · 고정 sleep 0 · 실 좌석·실 STATE·실 쪽지 0 · 임시 폴더만 쓴다. 돌리기: timeout 70 bash harness/tests/test_py311_compile_r1302.sh
[ -z "${R1302_PY311_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1302_PY311_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1302_PY311_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; H="$REPO/harness"
PY="${FT_PY311:-/opt/homebrew/bin/python3.11}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export PYTHONPYCACHEPREFIX="$T/pycache"  # 저장소에 __pycache__ 를 남기지 않는다
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }

compile_with() {  # <인터프리터> <폴더…> — 인터프리터가 없으면 ERROR 1줄 rc1(조용한 SKIP 0 · 하드 룰 20)
  local py="$1"; shift
  [ -x "$py" ] || { echo "ERROR python3.11 없음(시험 전제) — $py"; return 1; }
  "$py" -m compileall -q "$@"
}

# C1 ── 3.11 컴파일 rc0 (팩 harness/bin + kit/bin 전부)
if out="$(compile_with "$PY" "$H/bin" "$H/kit/fable-team/bin" 2>&1)"; then ok "C1 python3.11 compileall harness/bin + kit/bin rc=0"; else bad "C1 python3.11 compileall rc≠0 — $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
lap C1

# C2 ── python3.11 부재 = ERROR rc1 (SKIP 0)
if out="$(compile_with "$T/no-such-python3.11" "$H/bin" 2>&1)"; then
  bad "C2 python3.11 부재인데 rc=0 — 조용한 SKIP 은 금지"
else
  rc=$?
  if [ "$rc" = 1 ] && case "$out" in *"ERROR python3.11 없음"*) true;; *) false;; esac; then ok "C2 python3.11 부재 = ERROR 1줄 rc=1 (SKIP 0)"; else bad "C2 python3.11 부재 판정이 다르다 — rc=$rc out=$(printf '%s' "$out" | head -1)"; fi
fi
lap C2

# C3 ── bin↔kit 같은 판(한쪽만 고치면 뒤에서 갈린다)
if cmp -s "$H/bin/ft_card_assign_watch.py" "$H/kit/fable-team/bin/ft_card_assign_watch.py"; then ok "C3 bin↔kit cmp0 (ft_card_assign_watch.py)"; else bad "C3 bin≠kit — ft_card_assign_watch.py 두 판이 다르다"; fi
lap C3

# 변이 1 ── 치환 전 줄(같은 따옴표 중첩 f-string)로 되돌리면 C1 이 FAIL 해야 한다
mkdir -p "$T/mut/bin"
cat > "$T/mut_line.txt" <<'EOF'
    out = [f"배정 없는 카드 {len(n['없음'])} · 대기 초과 {len(n['초과'])}{'(' + ' · '.join(by) + ')' if by else ''} · 정지 중 {len(n['정지 중'])}{f" · 보류 중 {len(n['보류 중'])}" if n['보류 중'] else ''}{f" · 판정 불가 Q {len(n['판정 불가'])}" if n['판정 불가'] else ''} · 카드 없는 발주 {len(n['발주'])} · 판본 {stamp}"]
EOF
awk -v mut="$T/mut_line.txt" '
  /^    (by_s|held|q) = / { next }
  /^    out = \[f"배정 없는 카드/ { while ((getline l < mut) > 0) print l; close(mut); next }
  { print }' "$H/bin/ft_card_assign_watch.py" > "$T/mut/bin/ft_card_assign_watch.py"
if cmp -s "$H/bin/ft_card_assign_watch.py" "$T/mut/bin/ft_card_assign_watch.py"; then
  bad "변이 1 이 안 먹었다 — 대상 줄을 못 찾음(카드 대상: ft_card_assign_watch.py 의 out = [...] 한 줄)"
elif out="$(compile_with "$PY" "$T/mut/bin" 2>&1)"; then
  bad "변이 1 중첩 f-string 인데 compileall rc=0 — 시험이 재발을 못 잡는다"
else
  ok "변이 1 중첩 f-string 되돌림 = 3.11 compileall FAIL"
fi
lap 변이1

echo "STEP$STEP"
if [ "$fail" = 0 ]; then echo "OK test_py311_compile_r1302 (4/4)"; exit 0; fi
echo "FAIL test_py311_compile_r1302 (${fail}건)"; exit 1
