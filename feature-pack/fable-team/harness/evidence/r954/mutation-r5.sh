#!/usr/bin/env bash
# mutation-r5.sh — r954 r5 변이 4종(임시 사본에서 한 자리씩 되돌리고 그 시험이 FAIL 하는지 본다)
#   ① read_dir 앞에 os.path.lexists 선판정 되살림        → ⓥ1(상위 000 = EACCES) FAIL  (r4-a 재발 · 권한 오류가 «없음» 으로)
#   ② 카드 읽기 앞에 isfile 선판정 되살림                 → ⓥ2-③(폴더 카드 = EISDIR) FAIL (r4 «폴더 아님» 뭉갬 재발)
#   ③ fail() exit 0 + 셸의 rc 3 판정 삭제(글자 판정만)   → ⓥ1 rc FAIL                  (조용한 0 재발 · 표 1 r4-b)
#   ④ FileNotFoundError 도 «확인 불가»(없음을 오류로)     → ⓥ3-①(대기/ 없음 = 카드 0장 정상) FAIL
# 출력: 무변이 기준 ALL PASS 1줄 + 변이마다 KILLED|SURVIVED 1줄 · 전부 KILLED = rc0
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${PYTHON:-python3}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PACK="$(cd -- "$H/../../.." && pwd)"   # 팩 워크트리 루트 — 시험 ⓕ 가 git show <OLDREF>: 로 옛 판을 읽으므로 «오브젝트가 있는 사본» 이어야 한다
git clone -q --shared --no-hardlinks "$PACK" "$T/pack" || { echo "ERROR 사본 clone 실패"; exit 1; }
D="$T/pack/feature-pack/fable-team/harness"
for rel in bin/ft-card-flow.sh kit/fable-team/bin/ft-card-flow.sh tests/test_card_flow_r954.sh; do cp "$H/$rel" "$D/$rel"; done
find "$D" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
test_run() { (cd "$D" && PYTHONDONTWRITEBYTECODE=1 /bin/bash tests/test_card_flow_r954.sh 2>&1 | tail -n 30); }
judge() { test_run | grep -q '^ALL PASS' && return 0 || return 1; }   # rc0 = 변이 생존(시험이 못 잡음)
fail=0
if judge; then echo "PASS 무변이 기준 ALL PASS"; else echo "ERROR 무변이 기준 FAIL — 변이 판정 무효"; exit 1; fi
patch() {  # <파일 상대경로> <옛 글자> <새 글자> — bin·kit 두 사본에 «같이» 적용(kit cmp 시험이 먼저 깨지지 않게)
  local rel="$1"
  for f in "$D/bin/$rel" "$D/kit/fable-team/bin/$rel"; do
    [ -f "$f" ] || { echo "ERROR 사본 없음 $f"; fail=1; return 1; }
    [ -f "$f.orig" ] || cp "$f" "$f.orig"   # 여러 자리 변이에서도 «원본» 을 보존(되돌림 1회)
    OLD="$2" NEW="$3" "$PY" -c '
import os,sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read(); o=os.environ["OLD"]; n=os.environ["NEW"]
assert o in s, "변이 자리 없음: "+p
assert s.count(o)==1, "변이 자리 %d곳(1곳이어야 함): %s" % (s.count(o), p)
open(p,"w",encoding="utf-8").write(s.replace(o,n,1))
' "$f" || { echo "ERROR $rel 변이 자리 없음"; fail=1; return 1; }
  done
}
restore() { local rel="$1" f; for f in "$D/bin/$rel" "$D/kit/fable-team/bin/$rel"; do mv "$f.orig" "$f"; done; }
mutate() {  # <이름> <파일> <옛 글자> <새 글자> <새 글자2(선택)>
  local name="$1" rel="$2"; shift 2
  patch "$rel" "$1" "$2" || return
  if [ $# -ge 4 ]; then patch "$rel" "$3" "$4" || { restore "$rel"; return; }; fi
  if judge; then echo "SURVIVED $name"; fail=1; else
    echo "KILLED $name — $(test_run | grep -E '^FAIL' | head -2 | tr '\n' ' ')"
  fi
  restore "$rel"
}
F=ft-card-flow.sh
mutate "①lexists 선판정 되살림" "$F" \
  '    try: return os.listdir(p)' \
  '    if not os.path.lexists(p): return None
    try: return os.listdir(p)'
mutate "②isfile 선판정 되살림" "$F" \
  "    try: body=open(c,encoding='utf-8',errors='replace').read()" \
  "    if not os.path.isfile(c): fail('카드 파일 못 읽음 '+c)
    try: body=open(c,encoding='utf-8',errors='replace').read()"
mutate "③fail exit0 + rc3 판정 삭제" "$F" \
  '    print(msg); sys.exit(3)' \
  '    print(msg); sys.exit(0)' \
  '[ "$PYRC" -eq 3 ] && unavailable' \
  ': unused_unavailable'
mutate "④ENOENT 도 확인 불가" "$F" \
  '        except FileNotFoundError: return None' \
  "        except FileNotFoundError: fail('카드 폴더 못 읽음 '+p+' (ENOENT)')"
[ "$fail" = 0 ] && echo "MUTATION ALL KILLED" || echo "MUTATION FAILED"
exit $fail
