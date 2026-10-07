#!/usr/bin/env bash
# test_tmm_group.sh — tmm 그룹 탭 일반화 시험: 신 이름 6 · 구 이름 6 · 충돌 1 · 규칙파일 우선 1 · bash -n · ROLES 일치.
# tmux·~/.tmm 은 건드리지 않는다 (TMM_CATEGORIES·TMM_CAT_SESSIONS 로 격리).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMM="$HERE/../../scripts/harness-install/tmm/tmm"
LINT="$HERE/../../scripts/fable-team-bin/ft-name-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$TMM" && ok "bash -n tmm" || bad "bash -n tmm"

# 역할 예약어가 ft-name-lint.sh 와 같은 값인가
lint_roles="$(sed -n 's/^ROLES="\(.*\)"/\1/p' "$LINT")"
tmm_roles="$(sed -n 's/.*local roles=" \(.*\) " t1.*/\1/p' "$TMM")"
[ -n "$lint_roles" ] && [ "$lint_roles" = "$tmm_roles" ] && ok "ROLES 일치 ($lint_roles)" || bad "ROLES 불일치 lint='$lint_roles' tmm='$tmm_roles'"

CATS="$(mktemp)"; trap 'rm -f "$CATS"' EXIT
printf 'KakaoBot\tkakao\ncfo_*\tCFO\n' > "$CATS"

# label <TMM_CAT_SESSIONS> <세션명> [카테고리 파일]
label() { TMM_CATEGORIES="${3:-$CATS}" TMM_CAT_SESSIONS="$1" bash -c 'source "$0" __lib; cat_of "$1"' "$TMM" "$2"; }
check() { # <기대> <세션 목록> <세션명> [카테고리 파일]
  got="$(label "$2" "$3" "${4:-}")"
  [ "$got" = "$1" ] && ok "$3 → $got" || bad "$3 → '$got' (기대 '$1')"
}

NEW_ALL=$'byz-v65-master-claude#143\nbyz-cfo-master-claude#53\nbyz-planner-arch#3\nbyz-issues-da-codex#2\nbyz-v65-nano-card-slug#0\nbyz-harness-tester-claude#1'
# 신 이름 6 — 프로젝트(byz)가 아니라 팀으로 갈라진다
check v65     "$NEW_ALL" "byz-v65-master-claude#143"
check cfo     "$NEW_ALL" "byz-cfo-master-claude#53"
check planner "$NEW_ALL" "byz-planner-arch#3"
check issues  "$NEW_ALL" "byz-issues-da-codex#2"
check v65     "$NEW_ALL" "byz-v65-nano-card-slug#0"
check harness "$NEW_ALL" "byz-harness-tester-claude#1"

# 구 이름 6 — 기존 경로 그대로(회귀 0)
OLD_ALL=$'ft-v65-master-claude#140\nft-harness-ops#6\nft-airag-helm-claude#5\nFB_CFO#52\nKakaoBot#14\nft-v65-temp-m5-autovad-longpara#0'
check v65     "$OLD_ALL" "ft-v65-master-claude#140"
check harness "$OLD_ALL" "ft-harness-ops#6"
check airag   "$OLD_ALL" "ft-airag-helm-claude#5"
check cfo     "$OLD_ALL" "FB_CFO#52"
check kakao   "$OLD_ALL" "KakaoBot#14"
check v65     "$OLD_ALL" "ft-v65-temp-m5-autovad-longpara#0"

# 구·신 공존 — ft-v65 와 byz-v65 는 같은 팀 계보라 같은 탭(ft- 는 프로젝트가 아니다)
MIX=$'ft-v65-master-claude#142\nbyz-v65-master-claude#143'
check v65 "$MIX" "ft-v65-master-claude#142"
check v65 "$MIX" "byz-v65-master-claude#143"

# 충돌 1 — 다른 프로젝트가 같은 팀 글자(bot)를 쓰는 라이브 세션이 있을 때만 프로젝트 첫 글자 접두
CLASH=$'byz-bot-master-claude#1\nkakao-bot-master-claude#2'
check b-bot "$CLASH" "byz-bot-master-claude#1"
check k-bot "$CLASH" "kakao-bot-master-claude#2"
check bot   "byz-bot-master-claude#1" "byz-bot-master-claude#1"

# 규칙파일 우선 — categories 글롭이 P6 규칙보다 먼저 걸린다
printf 'byz-v65-*\tvx\n' > "$CATS.prio"
check vx "$NEW_ALL" "byz-v65-master-claude#143" "$CATS.prio"; rm -f "$CATS.prio"

echo "---"; [ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"; exit $fail
