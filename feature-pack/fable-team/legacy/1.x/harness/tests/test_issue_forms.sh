#!/usr/bin/env bash
# test_issue_forms.sh — C15 Issue 폼 시험: YAML 6/6 파싱 · 보강 칸 id 존재 · 기존 필드 id 삭제 0(BASE 대비) · 폼 라벨이 GitHub 에 존재.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DIR=".github/ISSUE_TEMPLATE"
BASE="${FT_ISSUE_FORMS_BASE:-5fbe72746463c286269751d1ed87a75526b051fd}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

FORMS="byz_agent_work_unit harness_request hil_request live_bug planner_task satellite_open"

python3 - "$ROOT" "$DIR" "$BASE" $FORMS <<'PY'
import subprocess, sys, yaml
root, d, base, *forms = sys.argv[1:]
need = {"live_bug": {"live_customer_impact", "confirm_request"},
        "planner_task": {"summary_path", "prerequisite"}}
def ids(doc):
    return {b["id"] for b in doc.get("body", []) if isinstance(b, dict) and "id" in b}
parsed = 0
bad = 0
for f in forms:
    path = f"{d}/{f}.yml"
    try:
        cur = yaml.safe_load(open(f"{root}/{path}", encoding="utf-8"))
        parsed += 1
    except Exception as e:
        print(f"FAIL parse {path}: {e}"); bad += 1; continue
    old = subprocess.run(["git", "-C", root, "show", f"{base}:{path}"], capture_output=True, text=True)
    if old.returncode != 0:
        print(f"FAIL base missing {path}: {old.stderr.strip()}"); bad += 1; continue
    lost = ids(yaml.safe_load(old.stdout)) - ids(cur)
    if lost:
        print(f"FAIL {f}: 기존 필드 id 삭제 {sorted(lost)}"); bad += 1
    miss = need.get(f, set()) - ids(cur)
    if miss:
        print(f"FAIL {f}: 보강 칸 id 없음 {sorted(miss)}"); bad += 1
print(f"{'PASS' if parsed == len(forms) else 'FAIL'} YAML 파싱 {parsed}/{len(forms)} OK")
print("PASS 기존 필드 id 삭제 0 · 보강 칸 id 존재" if bad == 0 else f"FAIL 필드 검사 {bad}건")
sys.exit(1 if bad or parsed != len(forms) else 0)
PY
[ $? -eq 0 ] || fail=$((fail+1))

# config.yml 무변경 · 새 폼 파일 0
git -C "$ROOT" diff --quiet "$BASE" -- "$DIR/config.yml" && ok "config.yml 무변경" || bad "config.yml 변경됨"
cnt="$(ls "$ROOT/$DIR"/*.yml | grep -vc '/config.yml$')"
[ "$cnt" -eq 6 ] && ok "폼 파일 6개 유지" || bad "폼 파일 수 $cnt != 6"

# 폼에 쓴 라벨이 GitHub 에 존재(gh 읽기)
have="$(gh label list --limit 500 --json name -q '.[].name' 2>&1)" || { bad "gh label list 실패: $have"; have=""; }
used="$(python3 - "$ROOT/$DIR" <<'PY'
import glob, sys, yaml
s = set()
for p in sorted(glob.glob(sys.argv[1] + "/*.yml")):
    if p.endswith("config.yml"): continue
    s.update(yaml.safe_load(open(p, encoding="utf-8")).get("labels", []) or [])
print("\n".join(sorted(s)))
PY
)"
if [ -n "$have" ]; then
  missing=""
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    if grep -Fxq -- "$l" <<<"$have"; then echo "  label OK  $l"; else missing="$missing $l"; fi
  done <<<"$used"
  [ -z "$missing" ] && ok "폼 라벨 전부 존재" || bad "없는 라벨:$missing"
fi

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
