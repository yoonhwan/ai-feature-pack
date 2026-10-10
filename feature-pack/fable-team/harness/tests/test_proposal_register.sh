#!/usr/bin/env bash
# test_proposal_register.sh — 옛 진입점 ft-proposal-register.sh 는 R77 r1(판정 826)에서 폐기됐다: 어떤 인자로 불러도 rc 1 + 안내(조용한 통과 0) · Tank 호출 0.
#   open/approve/inbox 의 시험은 test_proposal_open.sh · test_proposal_approve_inbox.sh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REG="$HERE/../../scripts/harness-install/proposal/ft-proposal-register.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$REG" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '#!/usr/bin/env bash\necho called >> "%s/tank.log"\n' "$T" > "$T/tank.sh"
for args in "" "x.md" "x.md --apply" "x.md --check" "--apply --force-create"; do
  # shellcheck disable=SC2086
  out="$(FT_TANK_CMD="bash $T/tank.sh" bash "$REG" $args 2>&1)"; rc=$?
  [ "$rc" = 1 ] && echo "$out" | grep -q 'ft-proposal-open.sh' && echo "$out" | grep -q 'ft-proposal-approve.sh' && ok "인자 「${args:-없음}」 → rc 1 + open/approve 안내" || bad "인자 「$args」 rc=$rc $out"
done
[ ! -e "$T/tank.log" ] && ok "Tank 호출 0" || bad "Tank 가 불렸다"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
