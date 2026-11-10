#!/usr/bin/env bash
# rework-r4-mutation.sh — r958 r4(재설계: ⑤ 비교 기준 = 좌석 .worktree-info base 우선)의 변이 시험.
#   변이 = «env FT_NANO_FEAT 우선» 옛 규칙 되살리기(info base 를 읽지 않는다) → 새 시험 1칸(ⓐ)이 FAIL 해야 한다.
#   임시 사본(mktemp)만 고친다 — 이 워크트리 파일은 건드리지 않는다. kit·bin 같은 바이트로 고쳐 cmp 단언은 통과시킨다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/../.."                          # feature-pack/fable-team/harness
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -R "$H/." "$T/harness"

for f in "$T/harness/kit/fable-team/bin/ft-nano-close.sh" "$T/harness/bin/ft-nano-close.sh"; do
  python3 - "$f" <<'PY' || { echo "변이 실패: $f"; exit 1; }
import sys
p = sys.argv[1]
lines = open(p, encoding='utf-8').read().split('\n')
i = next(k for k, l in enumerate(lines) if '.get("base","")' in l and '_FEAT=' in l)
lines[i] = ': # 변이 — info base 를 읽지 않는다(옛 규칙 = env 우선)'
j = next(k for k, l in enumerate(lines) if k < i and l == '_FEAT=""')
lines[j] = '_FEAT="${_ENV_FEAT}"'
open(p, 'w', encoding='utf-8').write('\n'.join(lines))
print('MUTATED', p)
PY
done
cmp -s "$T/harness/kit/fable-team/bin/ft-nano-close.sh" "$T/harness/bin/ft-nano-close.sh" && echo "변이본 kit·bin 같은 바이트(cmp0 — 시험의 cmp 단언은 통과시킨다)"
sed -n '856,862p' "$T/harness/bin/ft-nano-close.sh" | sed 's/^/  변이본: /'

echo
echo "================ 변이본으로 새 시험 1칸(ⓐ) 실행 — ⓐ 가 FAIL 해야 한다 ================"
bash "$T/harness/tests/test_nano_close_suspended.sh" > "$T/mut.txt" 2>&1; mrc=$?
sed -n '/== ⓐ r958 r4/,/ⓐ base 와 env/p' "$T/mut.txt"
echo "==> 변이판 rc=$mrc (기대 1) · FAIL 줄 수 = $(grep -c '^FAIL' "$T/mut.txt")"
