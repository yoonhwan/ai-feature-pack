#!/usr/bin/env bash
# R18 — local file, local commit, then pushed/fetched TEAMSET row.
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; CLONE="$TMP/clone"; FAKE="$TMP/fakebin"
git init -q --bare "$ORIGIN"; git init -q -b main "$SEED"
mkdir -p "$SEED/design/teams/zztest"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zztest | design/teams/zztest/ | x | 현역 |\n' > "$SEED/design/TEAMS.md"
cat > "$SEED/design/TEAMSET.md" <<'EOF'
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | sonnet | high | _master | a | b |
| arch | 상시 | opus | high | _arch | a | b |
| nano | 상한 N | sonnet | high | - | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: _name _doc _closed
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| planner | 3 | 0 | 상시 |
EOF
git -C "$SEED" -c user.name=t -c user.email=t@t add design
git -C "$SEED" -c user.name=t -c user.email=t@t commit -q -m seed
git -C "$SEED" remote add origin "$ORIGIN"; git -C "$SEED" push -q -u origin main
git clone -q -b main "$ORIGIN" "$CLONE"; mkdir -p "$FAKE"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && exit 0\nexit 1\n' > "$FAKE/tmux"; chmod +x "$FAKE/tmux"
export FT_ROOT="$CLONE" FT_TEAMS_MD="$CLONE/design/TEAMS.md" FT_TEAMSET_MD="$CLONE/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 PATH="$FAKE:$PATH"
bash "$BIN/ft-team-attach.sh" zztest --apply >/dev/null
cap() { python3 "$BIN/ft_teamset.py" cap --root "$CLONE" --md gitref:origin/main:design/TEAMSET.md --prefix byz-zztest-nano- 2>&1; }
out="$(cap)"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"TEAMSET 행 없음"* ]] || { echo "FAIL file rc=$rc $out"; exit 1; }
git -C "$CLONE" -c user.name=t -c user.email=t@t add design/TEAMSET.md
git -C "$CLONE" -c user.name=t -c user.email=t@t commit -q -m local
out="$(cap)"; rc=$?
[ "$rc" = 3 ] || { echo "FAIL local commit rc=$rc $out"; exit 1; }
git -C "$CLONE" push -q origin main; git -C "$CLONE" fetch -q origin
out="$(cap)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == CAP* ]] && echo "PASS R18 file-only=3 local-commit=3 push-fetch=0" || { echo "FAIL fetch rc=$rc $out"; exit 1; }

