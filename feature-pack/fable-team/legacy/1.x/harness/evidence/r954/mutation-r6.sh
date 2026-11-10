#!/usr/bin/env bash
# mutation-r6.sh — r954 r6 변이 2종(임시 사본에서 한 자리씩 되돌리고 그 시험이 FAIL 하는지 본다)
#   ① python→셸 esc 삭제(카드 줄·사유 줄을 날것으로)        → ⓥ5(개행 이름)·ⓥ7(사유 잘림) FAIL
#   ② 대기 목록을 «읽지 않고 길이만» 셈(listmd len)        → ⓥ6(대기 카드 000 = EACCES) FAIL
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
mutate() {  # <이름> <파일> <옛 글자> <새 글자> [<옛 글자2> <새 글자2>]
  local name="$1" rel="$2"; shift 2
  patch "$rel" "$1" "$2" || return
  if [ $# -ge 4 ]; then patch "$rel" "$3" "$4" || { restore "$rel"; return; }; fi
  if judge; then echo "SURVIVED $name"; fail=1; else
    echo "KILLED $name — $(test_run | grep -E '^FAIL' | head -2 | tr '\n' ' ')"
  fi
  restore "$rel"
}
F=ft-card-flow.sh
mutate "①esc 삭제(카드 줄·사유 줄 날것)" "$F" \
  "    print('C',st,int(live),esc(slug))" \
  "    print('C',st,int(live),slug)" \
  '    print(esc(msg)); sys.exit(3)' \
  '    print(msg); sys.exit(3)'
mutate "②대기 목록을 읽지 않고 길이만" "$F" \
  "for _f in listmd('대기'):" \
  "wait=len(listmd('대기'))
for _f in []:"
echo "---"
[ "$fail" = 0 ] && echo "ALL KILLED" || echo "MUTATION FAIL $fail"
exit $fail
