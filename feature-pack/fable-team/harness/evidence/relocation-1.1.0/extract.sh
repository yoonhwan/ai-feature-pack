#!/bin/bash
# r384 — BYZ 6경로 이력 추출 (scratchpad 독립 clone · 원본 저장소 쓰기 0)
set -euo pipefail
SP="$1"; SRC=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents; SHA=711199fd627deb033dd0ab5f54263282a458253d
C="$SP/byz-filter3"
test ! -e "$C" || { echo "ERR $C exists"; exit 2; }
git clone -q --shared --no-checkout --single-branch --branch main "$SRC" "$C"
cd "$C"
git branch -q harness-extract "$SHA"
git filter-repo --force --refs harness-extract \
  --path scripts/fable-team-bin/ --path scripts/harness-install/ --path tools/comm-canonical/ \
  --path design/teams/harness/ --path design/harness/ --path tests/harness/ \
  --path-glob 'tests/scripts/test_mbox*' --path-glob 'tests/scripts/test_magazine*' --path-glob 'tests/scripts/_magazine_*' --path tests/scripts/_thread_fakes.py --path tests/scripts/_proposal_fakes.py --path tests/scripts/conftest.py --path tests/scripts/fake_resource_env.py \
  --path-glob '.fable-team/state/v6-*' \
  --path-rename scripts/fable-team-bin/:feature-pack/fable-team/harness/bin/ --path-rename scripts/harness-install/:feature-pack/fable-team/harness/kit/ \
  --path-rename tools/comm-canonical/:feature-pack/fable-team/harness/comm/ --path-rename design/teams/harness/:feature-pack/fable-team/harness/design/harness/ \
  --path-rename tests/harness/:feature-pack/fable-team/harness/tests/ --path-rename .fable-team/state/:feature-pack/fable-team/harness/evidence/state-v6/ \
  --path-rename design/harness/:feature-pack/fable-team/harness/design/harness/ --path-rename tests/scripts/:feature-pack/fable-team/harness/tests/scripts/
echo "commits=$(git rev-list --count harness-extract)"
git ls-tree -r --name-only harness-extract | awk -F/ '{print $1}' | sort | uniq -c
