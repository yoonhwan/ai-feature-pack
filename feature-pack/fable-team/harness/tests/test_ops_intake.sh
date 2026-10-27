#!/usr/bin/env bash
# test_ops_intake.sh — r955 접수 도구 시험 러너 (ⓐ~ⓗ). 실 슬랙·실 gh·실 ssh·실 mini 호출 0.
#   bash tests/test_ops_intake.sh            전체 + 변이 6종
#   bash tests/test_ops_intake.sh --no-mutate
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in "$HERE/../kit/ops-intake"/*.py; do
  python3 -m py_compile "$f" && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")"
done
for f in "$HERE/../kit/ops-intake"/*.plist.template; do
  plutil -lint "$f" >/dev/null && ok "plutil $(basename "$f")" || bad "plutil $(basename "$f")"
done

# ⓔ 변경 금지 파일 — write.py 는 이 카드 커밋에서 «한 줄도» 바뀌지 않는다(가림 자리는 common 한 곳).
ROOT="$(cd -- "$HERE/../../../.." && pwd)"
KIT_WRITE="feature-pack/fable-team/harness/kit/ops-intake/ops_intake_write.py"
if git -C "$ROOT" diff --quiet "HEAD^" HEAD -- "$KIT_WRITE"; then
  ok "write.py diff 0 (r6 커밋 $(git -C "$ROOT" rev-parse --short HEAD))"
else
  bad "write.py diff 0"
fi

python3 "$HERE/test_ops_intake.py" || bad "cases ⓐ~ⓖ"
[ "${1:-}" = "--no-mutate" ] && exit "$fail"

for m in mask-off rescan-off declared-off guard-ts ledger-off notice-off header-block-off path-rule-off queue-recount-off timeout-off poster-secrets-off ledger-after-post-off lock-off cr-after-mask-off own-rules-off lock-scope-off own-mask-regex-off timer-after-urlopen pin-off; do
  python3 "$HERE/test_ops_intake.py" --mutate "$m" >/dev/null 2>&1 && ok "mutate $m" || bad "mutate $m"
done
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit "$fail"
