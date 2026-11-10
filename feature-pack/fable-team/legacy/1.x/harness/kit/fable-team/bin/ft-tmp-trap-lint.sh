#!/usr/bin/env bash
# ft-tmp-trap-lint.sh — «만들면 지운다» 린트 (R246). 읽기 전용.
#   셸의 `mktemp -d` 는 같은 파일에 `trap '… rm -rf … $변수 …'` 가 있어야 한다. 변수 없이 쓴 `mktemp -d` 는 지울 방법이 없으니 REJECT.
#   사용: ft-tmp-trap-lint.sh <파일…>            위반 있으면 `REJECT 파일:줄: 사유` exit 1 · 없으면 `PASS 파일` exit 0 · 파일 없음 exit 2
#         ft-tmp-trap-lint.sh --all [--root <폴더>]  tests/**/*.sh · scripts/**/*.sh 전체 목록만(exit 0) + 끝줄 `위반 N`
#   범위 밖: python `tempfile.mkdtemp` · 다른 함수에서 정리하는 패턴(필요하면 같은 파일에 trap 도 둔다).
set -uo pipefail
ROOT=""; ALL=0; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1;;
    --root) shift; ROOT="${1:-}";;
    *) FILES+=("$1");;
  esac; shift
done
if [ "$ALL" = 1 ]; then
  [ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "usage: --all 은 git 안이거나 --root 필요" >&2; exit 2; }
  DIRS=(); for d in tests scripts; do [ -d "$ROOT/$d" ] && DIRS+=("$ROOT/$d"); done; [ "${#DIRS[@]}" -gt 0 ] || DIRS=("$ROOT")
  while IFS= read -r f; do FILES+=("$f"); done < <(find "${DIRS[@]}" -name '*.sh' -not -path '*/node_modules/*' 2>/dev/null | sort -u)
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "usage: ft-tmp-trap-lint.sh <파일…> | --all [--root <폴더>]" >&2; exit 2; }
for f in "${FILES[@]}"; do [ -f "$f" ] || { echo "REJECT $f: 파일 없음" >&2; exit 2; }; done

python3 - "$ALL" "${FILES[@]}" <<'PY'
import re, sys
all_mode, files = sys.argv[1] == "1", sorted(set(sys.argv[2:]))
MK = re.compile(r'mktemp\s+(?:-\S*d\S*|--directory)\b')
ASSIGN = re.compile(r'(?:^|[\s;&|(])(?:local\s+|declare\s+|export\s+)?([A-Za-z_]\w*)=(?:"?\$\(|`)\s*mktemp\s')
TRAP = re.compile(r'(?:^|[;&|(])\s*trap\s+.*\brm\s+-\w*[rR]')
bad = 0
for path in files:
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    traps = [l for l in lines if TRAP.search(l)]
    hits = []
    for n, l in enumerate(lines, 1):
        if l.lstrip().startswith("#") or not MK.search(l):
            continue
        m = ASSIGN.search(l)
        if not m:
            hits.append((n, "변수 없이 mktemp -d — 지울 방법이 없다(변수에 담고 trap 으로 지운다)"))
            continue
        v = m.group(1)
        if not any(re.search(r'\$\{?%s\b' % re.escape(v), t) for t in traps):
            hits.append((n, f"mktemp -d → ${v} 인데 같은 파일에 trap … 지우기 … ${v} 가 없다"))
    for n, why in hits:
        print(f"REJECT {path}:{n}: {why}")
    bad += len(hits)
    if not hits and not all_mode:
        print(f"PASS {path}")
if all_mode:
    print(f"위반 {bad}")
    sys.exit(0)
sys.exit(1 if bad else 0)
PY
