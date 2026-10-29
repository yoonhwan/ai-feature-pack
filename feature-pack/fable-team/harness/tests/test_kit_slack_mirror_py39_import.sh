#!/usr/bin/env bash
# test_kit_slack_mirror_py39_import.sh — kit/slack-mirror 3파일이 mini python 3.9.6 에서 import 된다 (r956 반송 · arch#165).
# 실측 근거: mini python3 = 3.9.6 · `def share_guard(s: str | None)` 의 PEP 604 유니언은 3.9 에서 «정의 시점» 평가 → TypeError
#   → ops_intake_write rc2 «공용 비밀 꼴 적재 실패: TypeError» · 게시기도 같은 이유로 못 돈다.
# 이 칸이 보는 것 = from __future__ import annotations 1줄이 «docstring 바로 뒤» 에 있고, 그 덕에 주석이 문자열(str)로 미뤄지는가
#   (3.9 는 문자열 주석을 평가하지 않는다 = import 안전) · 변이(그 줄 삭제)에서 빨강이 되는가.
# 실제 슬랙·네트워크·launchd 호출 0 · 임시 폴더 사본만 쓴다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
KM="${KIT_SLACK_MIRROR:-$ROOT/harness/kit/slack-mirror}"
FILES="mirror_share.py mirror_lib.py post_guard.py status_head.py"  # status_head.py = r1089 post_guard 가 부른다
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# 주석 검사기 — 인자 = 폴더 · 모든 함수 주석이 str 이어야 rc0 (아니면 rc1 + 첫 위반 출력)
cat > "$T/ann.py" <<'PY'
import sys, types, importlib
d = sys.argv[1]
sys.path.insert(0, d)
bad = []
for name in ("mirror_share", "mirror_lib", "post_guard"):
    m = importlib.import_module(name)
    for k, v in vars(m).items():
        if not isinstance(v, types.FunctionType):
            continue
        for an, av in v.__annotations__.items():
            if not isinstance(av, str):
                bad.append("%s.%s %s=%r" % (name, k, an, av))
if bad:
    print("NOT-STR " + bad[0]); sys.exit(1)
print("ANNOTATIONS-STR-OK"); sys.exit(0)
PY

# ⓐ 세 파일 = docstring 바로 뒤에 `from __future__ import annotations` · 첫 import 보다 앞
for f in $FILES; do
  p="$KM/$f"
  [ -f "$p" ] || { bad "ⓐ $f 없음($p)"; continue; }
  n=$(awk '/^from __future__ import annotations/{print NR; exit}' "$p")
  [ -n "${n:-}" ] && ok "ⓐ $f 에 future 줄 있음(줄 $n)" || { bad "ⓐ $f 에 future 줄 없음"; continue; }
  # docstring 끝 줄(=둘째 `"""` 줄) 다음 «첫 코드 줄» 이 future 줄이어야 한다 — 사이에 import·식 0
  first=$(awk 'BEGIN{q=0} /^"""/{q++; if(q==2){next}} q>=2 && NF && $0 !~ /^[[:space:]]*#/{print NR; exit}' "$p")
  [ "${first:-0}" -eq "$n" ] && ok "ⓐ $f future 줄이 docstring 직후(첫 코드 줄 $first)" || bad "ⓐ $f future 줄 위치 틀림(future=$n 첫 코드 줄=${first:-없음})"
done

# ⓑ 3.9 문법(AST feature_version 3.9) + 실제 import + 주석이 전부 str(3.9 는 문자열 주석을 평가하지 않는다)
for f in $FILES; do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read(), feature_version=(3,9))' "$KM/$f" \
    && ok "ⓑ $f = py3.9 문법 AST 통과" || bad "ⓑ $f = py3.9 문법 AST 실패"
done
out=$(python3 "$T/ann.py" "$KM" 2>&1) && ok "ⓑ 3파일 import OK · 함수 주석 전부 str($out)" || bad "ⓑ import·주석 지연 실패: $out"

# ⓒ 변이 — 사본에서 future 줄을 지우면 같은 검사가 «빨강» 이어야 한다(검사가 살아 있음)
[ -d "$T/mut" ] || mkdir -p "$T/mut"
for f in $FILES; do cp "$KM/$f" "$T/mut/$f"; done
grep -v '^from __future__ import annotations' "$KM/mirror_share.py" > "$T/mut/mirror_share.py"
out=$(python3 "$T/ann.py" "$T/mut" 2>&1) && bad "변이: future 줄 지워도 주석이 str(검사 무력)" || ok "변이: future 줄 삭제 → 주석 비-str 로 빨강(${out%%$'\n'*})"

# ⓓ 실 python3.9 가 있으면 진짜 import 도 본다(없으면 SKIP — 이 맥 기본 python3 는 3.14)
PY39="${PY39:-$(command -v python3.9 || true)}"
if [ -n "$PY39" ]; then
  out=$("$PY39" -c 'import sys;sys.path.insert(0,sys.argv[1]);import mirror_share,mirror_lib,post_guard;print("PY39-IMPORT-OK",sys.version.split()[0])' "$KM" 2>&1) \
    && ok "ⓓ 실 python3.9 import OK($out)" || bad "ⓓ 실 python3.9 import 실패: $out"
else
  echo "SKIP ⓓ 실 python3.9 없음 — AST(3.9) + str 주석으로 대신 본다"
fi

echo "fail=$fail"
[ "$fail" -eq 0 ]
