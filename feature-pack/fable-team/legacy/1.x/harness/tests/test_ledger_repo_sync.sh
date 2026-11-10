#!/bin/bash
# test_ledger_repo_sync.sh — r503: 원장 사본 체크아웃 전진(ft-ledger-repo-sync.sh)
# ⓐ 깨끗한 detached 사본 → SYNC <a>..<b> rc0 · HEAD = origin/main
# ⓑ 이미 최신 → SYNC up-to-date rc0 · 쓰기 0(HEAD·index 그대로)
# ⓒ 추적 파일 미커밋 수정 1 → ERROR … 미커밋 추적 변경 1 — 전진 0 (<경로>) rc3 · HEAD 그대로 · 미추적 파일만 있으면 «깨끗함»
# ⓓ 사본이 가지 위 → ERROR ledger 사본이 가지 <이름> 위 — 전진 0 rc3
# ⓔ fetch 실패(origin 경로 없음) → ERROR ledger 사본 fetch 실패: <첫 줄> rc4
# 뉴스·매거진 호출(가짜 sync rc3) = tests/scripts/test_ft_news_ledger.py · test_ft_news_html.py 의 test_r503_*
# 픽스처 = 임시 bare origin + main 커밋 2 · 외부 호출 0 · GIT_* env 0(시험 전후 공용 config 비교)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SYNC="$HERE/../../harness/bin/ft-ledger-repo-sync.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CFG_BEFORE="$(git -C "$HERE" config --list --local 2>/dev/null | sort)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

g init -q --bare "$T/origin.git"
g clone -q "$T/origin.git" "$T/w" 2>/dev/null
mkdir -p "$T/w/design/teams/planner"
echo "v1" > "$T/w/design/teams/planner/PLAN-oppa-ledger.md"
g -C "$T/w" add -A && g -C "$T/w" commit -qm one
A="$(git -C "$T/w" rev-parse HEAD)"
echo "v2" > "$T/w/design/teams/planner/PLAN-oppa-ledger.md"
g -C "$T/w" commit -qam two
B="$(git -C "$T/w" rev-parse HEAD)"
g -C "$T/w" push -q origin HEAD:main
g clone -q "$T/origin.git" "$T/C" 2>/dev/null
git -C "$T/C" checkout -q --detach "$A"

# ⓐ
OUT="$(bash "$SYNC" "$T/C")"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = "SYNC ${A:0:10}..${B:0:10}" ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$B" ] && ok "ⓐ 깨끗한 detached → $OUT" || bad "ⓐ rc=$RC out=$OUT"
git -C "$T/C" symbolic-ref -q HEAD >/dev/null && bad "ⓐ 전진 뒤 가지 위가 됨" || ok "ⓐ 전진 뒤에도 detached"

# ⓑ
echo "news" > "$T/C/NEWS-untracked.html"   # 미추적 파일 = 깨끗함
IDX="$(git -C "$T/C" write-tree)"
OUT="$(bash "$SYNC" "$T/C")"; RC=$?
[ "$RC" = 0 ] && [ "${OUT%% "${B:0:10}"}" = "SYNC up-to-date" ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$B" ] && [ "$(git -C "$T/C" write-tree)" = "$IDX" ] && ok "ⓑ 이미 최신(미추적 파일 있음) → $OUT · 쓰기 0" || bad "ⓑ rc=$RC out=$OUT"

# ⓒ
echo "v3" > "$T/w/design/teams/planner/PLAN-oppa-ledger.md"; g -C "$T/w" commit -qam three; g -C "$T/w" push -q origin HEAD:main
echo "손댐" >> "$T/C/design/teams/planner/PLAN-oppa-ledger.md"
OUT="$(bash "$SYNC" "$T/C")"; RC=$?
[ "$RC" = 3 ] && [ "$OUT" = "ERROR ledger 사본 미커밋 추적 변경 1 — 전진 0 (design/teams/planner/PLAN-oppa-ledger.md)" ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$B" ] && ok "ⓒ 더러운 사본 → rc3 · HEAD 그대로" || bad "ⓒ rc=$RC out=$OUT"
git -C "$T/C" checkout -q -- design/teams/planner/PLAN-oppa-ledger.md

# ⓓ
git -C "$T/C" checkout -q -b someone-work
OUT="$(bash "$SYNC" "$T/C")"; RC=$?
[ "$RC" = 3 ] && [ "$OUT" = "ERROR ledger 사본이 가지 someone-work 위 — 전진 0 ($T/C)" ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$B" ] && ok "ⓓ 가지 위 → rc3 · 전진 0" || bad "ⓓ rc=$RC out=$OUT"
git -C "$T/C" checkout -q --detach "$B"

# ⓔ
git -C "$T/C" remote set-url origin "$T/no-such-origin.git"
OUT="$(bash "$SYNC" "$T/C")"; RC=$?
case "$OUT" in "ERROR ledger 사본 fetch 실패: "?*) F=1;; *) F=0;; esac
[ "$RC" = 4 ] && [ "$F" = 1 ] && [ "$(git -C "$T/C" rev-parse HEAD)" = "$B" ] && ok "ⓔ fetch 실패 → rc4 · ${OUT:0:80}" || bad "ⓔ rc=$RC out=$OUT"

# usage
bash "$SYNC" >/dev/null 2>&1; [ $? = 2 ] && ok "usage rc2" || bad "usage rc≠2"

[ "$CFG_BEFORE" = "$(git -C "$HERE" config --list --local 2>/dev/null | sort)" ] && ok "공용 git config 불변" || bad "공용 git config 바뀜"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
