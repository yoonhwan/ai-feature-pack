#!/usr/bin/env bash
# R10/R11 integration — 명단 밖 팀 카드는 제외하고, 현역 ref 누락을 별도 집계한다.
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; ROOT="$TMP/root"
git init -q --bare "$ORIGIN"; git init -q -b main "$SEED"
mkdir -p "$SEED/design/teams/base/indices" "$SEED/design/teams/dead/indices/대기"
cat > "$SEED/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 | 상태 |
|---|---|---|---|
| base | design/teams/base/ | x | 현역 |
| zztest | design/teams/zztest/ | x | 현역 |
EOF
printf '# base marker\n' > "$SEED/design/teams/base/indices/README.md"
printf '# deleted card\n- 배정: 없음\n' > "$SEED/design/teams/dead/indices/대기/deadcard.md"
git -C "$SEED" -c user.name=t -c user.email=t@t add design
git -C "$SEED" -c user.name=t -c user.email=t@t commit -q -m fixture
git -C "$SEED" remote add origin "$ORIGIN"; git -C "$SEED" push -q -u origin main
git clone -q -b main "$ORIGIN" "$ROOT"
mkdir -p "$ROOT/.fable-team/state"
printf '*\t.\torigin/main\tdesign/teams/*/indices\n' > "$ROOT/.fable-team/state/directive-roots.tsv"
NOW="$(date +%s)"
export FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_CARD_ASSIGN_NOW="$NOW"
out="$(python3 "$BIN/ft_card_assign_watch.py" prepare 2>&1)"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL prepare rc=$rc $out"; exit 1; }
out="$(python3 "$BIN/ft_card_assign_watch.py" status --now "$NOW" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"명단 밖 팀 1"* ]] && [[ "$out" == *"ref 미반영 팀 1"* ]] && [[ "$out" == "배정 없는 카드 0"* ]]; } \
  && echo "PASS R10 ref 미반영 1 · R11 명단 밖 팀 1 · 삭제 카드 제외" || { echo "FAIL rc=$rc $out"; exit 1; }

