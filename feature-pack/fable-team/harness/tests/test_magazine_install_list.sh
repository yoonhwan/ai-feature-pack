#!/usr/bin/env bash
# test_magazine_install_list.sh — 판정 601: 아침 매거진 키트의 «같은 폴더 모듈 import 닫힘 집합» ⊆ install-magazine.sh REQUIRED ∪ COMPANION
# (미러 설치 선행 가정 0 — 매거진 설치기 하나로 닫힘). 빠진 이름은 새 머신에서 ImportError 가 된다 — 이름을 출력하고 rc=1.
# 변이: REQUIRED 에서 magazine_collect_open.py · mirror_lib.py 를 각각 뺀 복사본은 rc=1 이어야 한다. 실 ~/.hermes·launchd 는 건드리지 않는다(읽기 전용).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../scripts/harness-install/slack-mirror"
PY="${PYTHON:-$HERE/../../.venv/bin/python}"; [ -x "$PY" ] || PY="python3"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 닫힘 집합 계산 + 목록 대조. $1 = 대조할 install-magazine.sh. 빠진 이름을 stdout 에 한 줄씩, 하나라도 있으면 rc=1.
check() {
  "$PY" -I - "$KIT" "$1" <<'PYEOF'
import ast, re, sys
from pathlib import Path

kit, magazine_sh = Path(sys.argv[1]), Path(sys.argv[2])
mods = {p.stem for p in kit.glob("*.py")}


def listed(text: str, var: str) -> set[str]:
    m = re.search(rf'^{var}="([^"]*)"', text, re.M)
    return set(m.group(1).split()) if m else set()


def imported(py: Path) -> set[str]:
    out: set[str] = set()
    for n in ast.walk(ast.parse(py.read_text(encoding="utf-8"))):
        if isinstance(n, ast.Import):
            out |= {a.name.split(".")[0] for a in n.names}
        elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
            out.add(n.module.split(".")[0])
    return out & mods


seen: set[str] = set()
stack = ["byz_morning_magazine", "byz_proposal_publish", "byz_thread_post"]
while stack:
    m = stack.pop()
    if m not in seen:
        seen.add(m)
        stack += sorted(imported(kit / f"{m}.py"))

text = magazine_sh.read_text(encoding="utf-8")
installed = listed(text, "REQUIRED") | listed(text, "COMPANION")
missing = sorted(f"{m}.py" for m in seen if f"{m}.py" not in installed)
print("\n".join(missing))
sys.exit(1 if missing else 0)
PYEOF
}

OUT="$(check "$KIT/install-magazine.sh")"; rc=$?
[ $rc -eq 0 ] && ok "닫힘 집합 ⊆ 설치 목록" || bad "설치 목록에 빠진 모듈(rc=$rc): $(echo "$OUT" | tr '\n' ' ')"

# 변이 — 목록에서 한 모듈씩 뺀 복사본은 걸러져야 한다
for mod in magazine_collect_open mirror_lib; do
  sed "s/$mod\\.py //" "$KIT/install-magazine.sh" > "$T/mutant.sh"
  grep -q "$mod" "$T/mutant.sh" && bad "변이 복사본 제작 실패: $mod" || ok "변이 복사본: $mod 제거됨"
  MOUT="$(check "$T/mutant.sh")"; mrc=$?
  [ $mrc -eq 1 ] && echo "$MOUT" | grep -qx "$mod.py" && ok "변이 → rc=1 · $mod.py 출력" || bad "변이가 안 걸림($mod rc=$mrc): $MOUT"
done

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
